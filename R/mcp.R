# ---- MCP ingress limits ---------------------------------------------------
# Every cap is enforced BEFORE the payload reaches a parser, so a hostile or
# broken client cannot force unbounded work in jsonlite::fromJSON(), in
# read_spec_df() or in normalize_ir_records().
#
# KNOWN RESIDUAL, deliberately accepted - see the note on mcp_serve(): the byte
# cap below bounds what the PARSER sees, not what the READ allocates.
MCP_MAX_LINE_BYTES <- 1048576L        # bytes in one newline-delimited JSON-RPC line
MCP_MAX_ARRAY_ITEMS <- 1000L          # elements allowed in any client-supplied array
MCP_MAX_ARGUMENT_NODES <- 50000L      # total nodes in one tools/call `arguments` tree
MCP_MAX_ARGUMENT_DEPTH <- 32L         # nesting depth of that tree
MCP_ORIGIN_DIGEST_CHARS <- 16L        # hex characters kept from a spec-origin digest

# ---- Fixed client-facing error catalogue ----------------------------------
# Reachable condition messages interpolate caller-controlled text (spec
# dataset names, IR field values, layer names), so they are never returned
# over the wire. Clients get one of these fixed strings; the underlying
# message is only ever emitted to stderr, and only when the operator opts in
# via options(admiralagent.mcp_debug = TRUE).
MCP_ERRORS <- list(
  invalid_request   = "Invalid Request: expected a JSON-RPC 2.0 object with a string `method`",
  parse_error       = "Parse error: the line is not a valid JSON-RPC 2.0 object",
  method_not_found  = "Method not found",
  unknown_tool      = "Invalid params: unknown tool; call tools/list for the allowed tool names",
  request_too_large = "Request rejected: input exceeds the MCP ingress limits",
  invalid_arguments = "Invalid tool arguments: see the tool inputSchema",
  invalid_ir        = "Invalid IR: it failed schema or semantic validation; call aa_validate_ir for the problem list",
  render_failed     = "Render failed: this IR cannot be rendered into an admiral program",
  internal_error    = "Internal tool error"
)

# Fallback catalogue entry per tool, used when a tool raises a plain error.
MCP_TOOL_ERRORS <- c(
  aa_classify = "invalid_arguments",
  aa_validate_ir = "invalid_ir",
  aa_render_program = "render_failed",
  aa_dependency_report = "invalid_ir",
  aa_evals = "internal_error"
)

mcp_error_message <- function(code) {
  msg <- if (is.character(code) && length(code) == 1L && !is.na(code)) MCP_ERRORS[[code]] else NULL
  if (is.null(msg)) MCP_ERRORS$internal_error else msg
}

mcp_condition <- function(code) {
  structure(
    class = c("mcp_catalogue_error", "error", "condition"),
    list(message = mcp_error_message(code), call = NULL, aa_code = code)
  )
}

mcp_abort <- function(code) stop(mcp_condition(code))

# Out-of-band only: detail goes to stderr for the operator, never to the client.
mcp_log_detail <- function(tool, cond) {
  if (!isTRUE(getOption("admiralagent.mcp_debug", FALSE))) return(invisible(NULL))
  cat(paste0("[admiralagent-mcp] ", tool, ": ", conditionMessage(cond), "\n"), file = stderr())
  invisible(NULL)
}

# Bounds the parsed `arguments` tree before any tool parses it into a spec or
# an IR: total node count, nesting depth, and the length of every array.
mcp_ingress_ok <- function(x) {
  remaining <- MCP_MAX_ARGUMENT_NODES
  ok <- function(v, depth) {
    remaining <<- remaining - 1L
    if (remaining < 0L || depth > MCP_MAX_ARGUMENT_DEPTH) return(FALSE)
    if (length(v) > MCP_MAX_ARRAY_ITEMS) return(FALSE)
    if (!is.list(v)) return(TRUE)
    for (el in v) if (!ok(el, depth + 1L)) return(FALSE)
    TRUE
  }
  ok(x, 0L)
}

# Client free text is never echoed back. A digest keeps provenance traceable
# and comparable across calls while removing the echo channel into responses
# and generated code comments. The prefix names the field it replaced, so a
# digest is never mistaken for the text and the two fields stay distinguishable
# even when they carried identical input.
mcp_text_digest <- function(x, prefix) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) return(NA_character_)
  paste0(prefix, ":", substr(
    digest::digest(x, algo = "xxhash64", serialize = FALSE), 1, MCP_ORIGIN_DIGEST_CHARS
  ))
}

mcp_origin_digest <- function(x) mcp_text_digest(x, "origin")

# THE free-text boundary for MCP. Both client-supplied free-text fields of
# `aa_variable_ir` are digested here, and every tool that accepts or produces
# IR routes through this one function.
#
# `spec_origin` (client spec `derivation`) and `rationale` have the identical
# shape: machine-written from a closed vocabulary on the `aa_classify` path,
# but arbitrary client text on the `aa_render_program` / `aa_validate_ir` /
# `aa_dependency_report` paths, where `rationale` is reproduced verbatim into a
# generated code comment (R/codegen.R). Injection was already closed by
# `comment_text()`; what is closed here is the ECHO channel, per the AGENTS.md
# rule that no client free text is carried into responses, generated code or
# sidecars. Redaction is unconditional on purpose: a client cannot tell whether
# a given rationale was machine- or client-authored, so a conditional rule
# would not be one anybody could rely on.
mcp_redact_ir <- function(ir) {
  lapply(ir, function(v) {
    v$spec_origin <- mcp_origin_digest(v$spec_origin)
    v$rationale <- mcp_text_digest(v$rationale, "rationale")
    v
  })
}

mcp_spec_row_schema <- function() {
  list(
    type = "object",
    properties = list(
      dataset = list(type = "string"),
      variable = list(type = "string"),
      label = list(type = "string"),
      type = list(type = "string"),
      origin = list(type = "string"),
      derivation = list(type = "string"),
      source_dataset = list(type = "string"),
      source_variable = list(type = "string")
    ),
    required = c("variable", "label", "type", "origin", "derivation")
  )
}

mcp_ir_schema <- function() {
  list(
    type = "array",
    items = list(
      type = "object",
      properties = list(
        dataset = list(type = "string"),
        variable = list(type = "string"),
        steps = list(
          type = "array",
          items = list(
            type = "object",
            properties = list(
              layer = list(type = "string"),
              args = list(type = "object"),
              on = list(type = "string")
            ),
            required = I("layer")
          )
        ),
        confidence = list(type = "number"),
        needs_human = list(type = "boolean"),
        rationale = list(type = "string"),
        spec_origin = list(type = "string")
      ),
      required = c("dataset", "variable", "steps")
    )
  )
}

#' Tool specifications for the admiralagent MCP server
#'
#' @description Defines the five deterministic tools exposed over MCP stdio:
#'   `aa_classify`, `aa_validate_ir`, `aa_render_program`,
#'   `aa_dependency_report`, and `aa_evals`. Every tool is pure base-package
#'   logic (no network, no LLM): spec rows in, layer IR / admiral code /
#'   validation problems out.
#' @return A named list of tool definitions, each with `name`, `description`,
#'   and `inputSchema` (a JSON-Schema-style list).
#' @export
mcp_tool_specs <- function() {
  list(
    aa_classify = list(
      name = "aa_classify",
      description = paste(
        "Classify spec rows into admiralagent layer IR using the deterministic rules backend,",
        "then run validate_ir(). Returns {ir, problems}: `problems` is empty when the IR",
        "passes the gate, and `ir` is null whenever `problems` is non-empty.",
        "The free-text fields are digested, never echoed: `spec_origin` comes back as",
        "'origin:<hex>' and `rationale` as 'rationale:<hex>'."
      ),
      inputSchema = list(
        type = "object",
        properties = list(
          dataset = list(type = "string", description = "target dataset to classify, e.g. 'ADSL'"),
          spec_rows = list(
            type = "array",
            description = "spec rows; a row's own `dataset` (optional) falls back to the top-level dataset",
            items = mcp_spec_row_schema()
          )
        ),
        required = c("dataset", "spec_rows")
      )
    ),
    aa_validate_ir = list(
      name = "aa_validate_ir",
      description = paste(
        "Parse and normalize a variable IR array through the same path as LLM output",
        "(step-level `on` is absorbed into args), then run validate_ir().",
        "Returns {valid: bool, problems: string[]}."
      ),
      inputSchema = list(
        type = "object",
        properties = list(ir = mcp_ir_schema()),
        required = I("ir")
      )
    ),
    aa_render_program = list(
      name = "aa_render_program",
      description = paste(
        "Render a variable IR into a deterministic admiral program with CHECK comments",
        "and DISCLAIMER header. Returns {code: string, hash: artifact hash (8 chars)}.",
        "Both free-text fields are digested at ingress, so the 'Spec origin' and",
        "'Agent rationale' code comments carry 'origin:<hex>' / 'rationale:<hex>',",
        "not the submitted text. The digests are part of the IR that is hashed,",
        "so `hash` is a function of the digests rather than of the free text."
      ),
      inputSchema = list(
        type = "object",
        properties = list(
          ir = mcp_ir_schema(),
          backend_label = list(type = "string", description = "backend label for the program header; default 'rules'")
        ),
        required = I("ir")
      )
    ),
    aa_dependency_report = list(
      name = "aa_dependency_report",
      description = paste(
        "Report IR step inputs that are defined neither by the spec, by another step,",
        "nor by known_columns. Returns rows {variable, input, dataset, issue}."
      ),
      inputSchema = list(
        type = "object",
        properties = list(
          ir = mcp_ir_schema(),
          known_columns = list(
            type = "array",
            items = list(type = "string"),
            description = "column names assumed to pre-exist in the source data"
          )
        ),
        required = I("ir")
      )
    ),
    aa_evals = list(
      name = "aa_evals",
      description = paste(
        "Run the bundled spec-to-IR eval corpus against the rules backend.",
        "Returns {cases: n, rules_accuracy: number, failures: array}."
      ),
      inputSchema = list(
        type = "object",
        properties = list()
      )
    )
  )
}

mcp_row_chr <- function(row, field) {
  v <- row[[field]]
  if (is.null(v) || is.list(v) || length(v) != 1L || is.na(v)) NA_character_ else as.character(v)
}

mcp_tool_classify <- function(args) {
  dataset <- mcp_row_chr(args, "dataset")
  if (is.na(dataset)) mcp_abort("invalid_arguments")
  rows <- args$spec_rows
  if (!is.list(rows) || length(rows) == 0L) mcp_abort("invalid_arguments")
  ds <- vapply(rows, function(row) {
    d <- mcp_row_chr(row, "dataset")
    if (is.na(d)) dataset else d
  }, character(1))
  col <- function(field) vapply(rows, mcp_row_chr, character(1), field = field)
  spec <- read_spec_df(data.frame(
    dataset = ds,
    variable = col("variable"),
    label = col("label"),
    type = col("type"),
    origin = col("origin"),
    derivation = col("derivation"),
    source_dataset = col("source_dataset"),
    source_variable = col("source_variable"),
    stringsAsFactors = FALSE
  ))
  ir <- mcp_redact_ir(classify_variables(spec, dataset, backend = "rules"))
  problems <- validate_ir(ir)
  # A failing IR is diagnostic material, not a deliverable: withhold it so no
  # client can treat gate-rejected IR as usable output.
  if (length(problems) > 0L) return(list(ir = NULL, problems = problems))
  list(ir = jsonlite::fromJSON(canonical_ir(ir), simplifyVector = FALSE), problems = problems)
}

mcp_ir_from_args <- function(args) {
  raw <- args$ir
  if (is.null(raw) || !is.list(raw)) mcp_abort("invalid_ir")
  ir <- tryCatch(normalize_ir_records(raw), error = function(e) mcp_abort("invalid_ir"))
  mcp_redact_ir(ir)
}

mcp_tool_validate_ir <- function(args) {
  ir <- mcp_ir_from_args(args)
  problems <- validate_ir(ir)
  list(valid = length(problems) == 0L, problems = problems)
}

mcp_tool_render_program <- function(args) {
  ir <- mcp_ir_from_args(args)
  backend_label <- mcp_row_chr(args, "backend_label")
  if (is.na(backend_label)) backend_label <- "rules"
  # render_program() aborts on any check_admiral_compat() message, so a
  # `warnings` field here could only ever be empty: dropped rather than kept
  # as a signal clients would wrongly trust.
  code <- render_program(ir, backend_label = backend_label)
  list(code = code, hash = artifact_hash(ir))
}

mcp_tool_dependency_report <- function(args) {
  ir <- mcp_ir_from_args(args)
  known <- if (is.null(args$known_columns)) character() else as.character(unlist(args$known_columns))
  rows <- ir_dependency_report(ir, known_columns = known)
  unname(lapply(seq_len(nrow(rows)), function(i) as.list(rows[i, , drop = FALSE])))
}

mcp_tool_evals <- function(args) {
  cases <- load_evals()
  datasets <- unique(vapply(cases, function(c) as.character(c$dataset), character(1)))
  res <- do.call(rbind, lapply(datasets, function(ds) {
    suppressMessages(run_evals(backend = "rules", dataset = ds))
  }))
  bad <- res[!res$ok, , drop = FALSE]
  list(
    cases = nrow(res),
    rules_accuracy = evals_accuracy(res),
    failures = unname(lapply(seq_len(nrow(bad)), function(i) as.list(bad[i, , drop = FALSE])))
  )
}

mcp_run_tool <- function(name, arguments) {
  switch(name,
    aa_classify = mcp_tool_classify(arguments),
    aa_validate_ir = mcp_tool_validate_ir(arguments),
    aa_render_program = mcp_tool_render_program(arguments),
    aa_dependency_report = mcp_tool_dependency_report(arguments),
    aa_evals = mcp_tool_evals(arguments),
    mcp_abort("unknown_tool")
  )
}

mcp_jsonrpc_error_response <- function(id = NULL, code, message) {
  list(jsonrpc = "2.0", id = id, error = list(code = code, message = message))
}

mcp_tools_call <- function(req) {
  params <- req$params
  if (!is.list(params)) params <- list()
  specs <- mcp_tool_specs()
  name <- params$name
  if (is.null(name) || !is.character(name) || length(name) != 1L || is.na(name) ||
        !name %in% names(specs)) {
    return(mcp_jsonrpc_error_response(req$id, -32602L, mcp_error_message("unknown_tool")))
  }
  arguments <- if (is.list(params$arguments)) params$arguments else list()
  # Size gate runs before the tool touches the payload, so oversized arrays
  # never reach read_spec_df() or normalize_ir_records().
  if (!mcp_ingress_ok(arguments)) {
    return(mcp_jsonrpc_error_response(req$id, -32602L, mcp_error_message("request_too_large")))
  }
  out <- tryCatch(mcp_run_tool(name, arguments), error = function(e) e)
  if (inherits(out, "error")) {
    mcp_log_detail(name, out)
    code <- if (inherits(out, "mcp_catalogue_error")) out$aa_code else MCP_TOOL_ERRORS[[name]]
    return(list(jsonrpc = "2.0", id = req$id, result = list(
      content = list(list(type = "text", text = mcp_error_message(code))),
      isError = TRUE
    )))
  }
  list(jsonrpc = "2.0", id = req$id, result = list(
    content = list(list(
      type = "text",
      text = jsonlite::toJSON(out, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
    )),
    isError = FALSE
  ))
}

#' Handle one MCP / JSON-RPC 2.0 request
#'
#' @description Dispatches a parsed JSON-RPC 2.0 request list against the
#'   admiralagent MCP methods: `initialize`, `notifications/initialized`,
#'   `tools/list`, and `tools/call`. Tool results are wrapped as MCP text
#'   content (\{content: [\{type: "text", text: <json>\}], isError: false\});
#'   tool execution errors come back with `isError: true`. Unknown methods
#'   return a JSON-RPC error (-32601), structurally invalid requests -32600.
#'   The function is pure: it never touches stdin/stdout, so the whole server
#'   can be unit-tested in-process.
#' @param req Parsed request: a JSON-RPC 2.0 object as an R list (typically
#'   `jsonlite::fromJSON(line, simplifyVector = FALSE)`).
#' @return A JSON-RPC response list, or `NULL` for notifications (no response
#'   may be sent).
#' @export
mcp_handle_request <- function(req) {
  if (!is.list(req) || is.null(req$method) || !is.character(req$method) ||
        length(req$method) != 1L || is.na(req$method)) {
    return(mcp_jsonrpc_error_response(
      id = if (is.list(req)) req$id else NULL,
      code = -32600L,
      message = mcp_error_message("invalid_request")
    ))
  }
  if (startsWith(req$method, "notifications/") || is.null(req$id)) return(NULL)

  if (identical(req$method, "initialize")) {
    return(list(jsonrpc = "2.0", id = req$id, result = list(
      protocolVersion = "2024-11-05",
      capabilities = list(tools = list()),
      serverInfo = list(name = "admiralagent-mcp", version = pkg_ver())
    )))
  }
  if (identical(req$method, "tools/list")) {
    return(list(jsonrpc = "2.0", id = req$id, result = list(tools = unname(mcp_tool_specs()))))
  }
  if (identical(req$method, "tools/call")) {
    return(mcp_tools_call(req))
  }
  mcp_jsonrpc_error_response(req$id, -32601L, mcp_error_message("method_not_found"))
}

mcp_process_line <- function(line) {
  line <- as.character(line)
  if (length(line) != 1L || is.na(line)) {
    return(mcp_jsonrpc_error_response(NULL, -32600L, mcp_error_message("invalid_request")))
  }
  # Byte cap first: the parser never sees an oversized line.
  if (nchar(line, type = "bytes") > MCP_MAX_LINE_BYTES) {
    return(mcp_jsonrpc_error_response(NULL, -32600L, mcp_error_message("request_too_large")))
  }
  line <- trimws(line)
  if (!nzchar(line)) return(NULL)
  parsed <- tryCatch(
    list(ok = TRUE, value = jsonlite::fromJSON(line, simplifyVector = FALSE)),
    error = function(e) list(ok = FALSE, value = conditionMessage(e))
  )
  if (!parsed$ok) {
    return(mcp_jsonrpc_error_response(NULL, -32700L, mcp_error_message("parse_error")))
  }
  mcp_handle_request(parsed$value)
}

#' Run the admiralagent MCP stdio server
#'
#' @description Blocking newline-delimited JSON-RPC 2.0 loop over stdin/stdout
#'   (MCP stdio transport, protocol version 2024-11-05). One request per line
#'   in, zero or one response line out, flushed immediately. EOF on stdin ends
#'   the loop cleanly. Refuses to run in interactive sessions so an accidental
#'   call cannot hang the console. Meant to be launched via
#'   `Rscript tools/mcp_server.R`.
#' @return Invisible `NULL` when stdin reaches EOF.
#' @export
mcp_serve <- function() {
  if (interactive()) {
    stop(
      "mcp_serve() blocks on a newline-delimited JSON-RPC stdin/stdout loop; ",
      "run it non-interactively via `Rscript tools/mcp_server.R`",
      call. = FALSE
    )
  }
  con <- file("stdin", open = "r")
  on.exit(close(con), add = TRUE)
  repeat {
    # KNOWN RESIDUAL (decided, not overlooked). readLines() materialises the
    # whole line before MCP_MAX_LINE_BYTES can reject it in mcp_process_line(),
    # so a client that writes a multi-gigabyte line without a newline can still
    # exhaust this process's memory. The cap therefore bounds PARSING work, not
    # READ allocation; it is not a complete input-size defence and must not be
    # read as one.
    #
    # Why it is not fixed by reading in bounded chunks: base R has no bounded
    # line read that keeps stdio request/response semantics. Measured on this
    # platform, readBin(con, "raw", n = 65536) and readChar(con, 65536) both
    # block until the chunk is full OR stdin closes - a client that sends one
    # small request and waits for its answer gets no answer, i.e. the fix
    # deadlocks every normal session. Only n = 1 returns promptly, and
    # byte-at-a-time framing measured ~8.3 s/MiB against ~0.02 s/MiB for
    # readLines(), which would make a legitimate large-but-under-cap request
    # hundreds of times slower.
    #
    # Weighed against that: this surface writes nothing to disk and has no
    # code-eval path (re-verified), it holds no credentials and no study data,
    # and stdin is the pipe of a child process the operator launched. The worst
    # case is that this restartable translator process dies. A mitigation whose
    # failure mode is "every request hangs" is worse than the exposure, so the
    # residual is accepted. Revisit if the transport ever becomes a socket or a
    # multi-client listener, where the caller is no longer the operator and
    # non-blocking bounded reads become available.
    line <- readLines(con, n = 1L, warn = FALSE)
    if (length(line) == 0L) break
    resp <- mcp_process_line(line)
    if (!is.null(resp)) {
      cat(jsonlite::toJSON(resp, auto_unbox = TRUE, null = "null", na = "null", digits = NA), "\n")
      flush(stdout())
    }
  }
  invisible(NULL)
}
