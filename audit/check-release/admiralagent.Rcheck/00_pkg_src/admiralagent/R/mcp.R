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
        "then run validate_ir(). Returns the IR list and the problems array",
        "(empty when the IR passes the gate)."
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
        "and DISCLAIMER header. Returns {code: string, hash: artifact hash (8 chars),",
        "warnings: admiral compatibility messages}."
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
  if (is.na(dataset)) stop("`dataset` (string) is required", call. = FALSE)
  rows <- args$spec_rows
  if (!is.list(rows) || length(rows) == 0L) {
    stop("`spec_rows` must be a non-empty array of spec row objects", call. = FALSE)
  }
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
  ir <- classify_variables(spec, dataset, backend = "rules")
  list(ir = ir, problems = validate_ir(ir))
}

mcp_ir_from_args <- function(args) {
  raw <- args$ir
  if (is.null(raw) || !is.list(raw)) {
    stop("`ir` must be an array of variable IR objects", call. = FALSE)
  }
  ir <- parse_ir_json(jsonlite::toJSON(raw, auto_unbox = TRUE, null = "null"))
  if (is.null(ir)) {
    stop("`ir` could not be parsed as a variable IR array", call. = FALSE)
  }
  ir
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
  warnings <- as.character(check_admiral_compat(ir))
  code <- render_program(ir, backend_label = backend_label)
  list(code = code, hash = artifact_hash(ir), warnings = warnings)
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
    stop("unknown tool '", name, "'", call. = FALSE)
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
    return(mcp_jsonrpc_error_response(
      req$id, -32602L,
      sprintf(
        "Invalid params: unknown tool '%s'; allowed: %s",
        paste(name, collapse = ""),
        paste(names(specs), collapse = ", ")
      )
    ))
  }
  arguments <- if (is.list(params$arguments)) params$arguments else list()
  out <- tryCatch(mcp_run_tool(name, arguments), error = function(e) e)
  if (inherits(out, "error")) {
    return(list(jsonrpc = "2.0", id = req$id, result = list(
      content = list(list(type = "text", text = conditionMessage(out))),
      isError = TRUE
    )))
  }
  list(jsonrpc = "2.0", id = req$id, result = list(
    content = list(list(
      type = "text",
      text = jsonlite::toJSON(out, auto_unbox = TRUE, null = "null", na = "null")
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
      message = "Invalid Request: expected a JSON-RPC 2.0 object with a string `method`"
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
  mcp_jsonrpc_error_response(req$id, -32601L, paste0("Method not found: ", req$method))
}

mcp_process_line <- function(line) {
  line <- trimws(as.character(line))
  if (!nzchar(line)) return(NULL)
  parsed <- tryCatch(
    list(ok = TRUE, value = jsonlite::fromJSON(line, simplifyVector = FALSE)),
    error = function(e) list(ok = FALSE, value = conditionMessage(e))
  )
  if (!parsed$ok) {
    return(mcp_jsonrpc_error_response(NULL, -32700L, paste0("Parse error: ", parsed$value)))
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
    line <- readLines(con, n = 1L, warn = FALSE)
    if (length(line) == 0L) break
    resp <- mcp_process_line(line)
    if (!is.null(resp)) {
      cat(jsonlite::toJSON(resp, auto_unbox = TRUE, null = "null", na = "null"), "\n")
      flush(stdout())
    }
  }
  invisible(NULL)
}
