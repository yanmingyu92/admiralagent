mcp_call <- function(name, arguments) {
  mcp_handle_request(list(
    jsonrpc = "2.0",
    id = 7,
    method = "tools/call",
    params = list(name = name, arguments = arguments)
  ))
}

mcp_tool_out <- function(name, arguments = list()) {
  resp <- mcp_call(name, arguments)
  expect_false(resp$result$isError, label = paste("tool", name, "returned isError"))
  jsonlite::fromJSON(resp$result$content[[1]]$text, simplifyVector = FALSE)
}

valid_ir_arg <- list(
  dataset = "ADSL",
  variable = "TRTSDTM",
  steps = list(list(
    layer = "impute_dtc",
    args = list(
      target = "TRTSDTM",
      dtc = "RFSTDTC",
      output_class = "dtm",
      highest_imputation = "M",
      date_imputation = "first"
    )
  )),
  confidence = 0.9,
  needs_human = FALSE,
  rationale = "impute DM RFSTDTC",
  spec_origin = "Date of first study treatment, imputed from DM RFSTDTC"
)

test_that("mcp_tool_specs exposes the five deterministic tools with input schemas", {
  specs <- mcp_tool_specs()
  expect_setequal(
    names(specs),
    c("aa_classify", "aa_validate_ir", "aa_render_program", "aa_dependency_report", "aa_evals")
  )
  for (nm in names(specs)) {
    expect_identical(specs[[nm]]$name, nm)
    expect_type(specs[[nm]]$description, "character")
    expect_identical(specs[[nm]]$inputSchema$type, "object")
    expect_type(specs[[nm]]$inputSchema$properties, "list")
  }
})

test_that("initialize returns the 2024-11-05 protocol, tools capability, and serverInfo", {
  resp <- mcp_handle_request(list(jsonrpc = "2.0", id = 1, method = "initialize", params = list()))
  expect_identical(resp$jsonrpc, "2.0")
  expect_identical(resp$id, 1)
  expect_identical(resp$result$protocolVersion, "2024-11-05")
  expect_type(resp$result$capabilities$tools, "list")
  expect_identical(resp$result$serverInfo$name, "admiralagent-mcp")
  expect_type(resp$result$serverInfo$version, "character")
})

test_that("tools/list returns all five tools with name and inputSchema", {
  resp <- mcp_handle_request(list(jsonrpc = "2.0", id = 2, method = "tools/list"))
  names <- vapply(resp$result$tools, function(t) t$name, character(1))
  expect_setequal(
    names,
    c("aa_classify", "aa_validate_ir", "aa_render_program", "aa_dependency_report", "aa_evals")
  )
  for (t in resp$result$tools) {
    expect_identical(t$inputSchema$type, "object")
    expect_type(t$inputSchema$properties, "list")
  }
})

test_that("aa_classify maps an RFSTDTC spec row to impute_dtc with zero problems", {
  out <- mcp_tool_out("aa_classify", list(
    dataset = "ADSL",
    spec_rows = list(list(
      variable = "TRTSDTM",
      label = "Date of First Study Treatment",
      type = "datetime",
      origin = "Derived",
      derivation = "Date of first study treatment, imputed from DM RFSTDTC",
      source_dataset = "dm",
      source_variable = "RFSTDTC"
    ))
  ))
  expect_identical(out$ir[[1]]$dataset, "ADSL")
  expect_identical(out$ir[[1]]$variable, "TRTSDTM")
  expect_identical(out$ir[[1]]$steps[[1]]$layer, "impute_dtc")
  expect_identical(out$ir[[1]]$steps[[1]]$args$dtc, "RFSTDTC")
  expect_length(out$problems, 0)
})

test_that("aa_classify abstention row returns needs_human true", {
  out <- mcp_tool_out("aa_classify", list(
    dataset = "ADSL",
    spec_rows = list(list(
      variable = "AGEGR1",
      label = "Age Group",
      type = "text",
      origin = "Assigned",
      derivation = "Age group categories from AGE: <18, 18-64, >=65"
    ))
  ))
  expect_true(out$ir[[1]]$needs_human)
  expect_length(out$ir[[1]]$steps, 0)
  expect_length(out$problems, 0)
})

test_that("aa_validate_ir accepts a well-formed IR", {
  out <- mcp_tool_out("aa_validate_ir", list(ir = list(valid_ir_arg)))
  expect_true(out$valid)
  expect_length(out$problems, 0)
})

test_that("aa_validate_ir rejects assign-from-AVAL with the BDS artifact problem", {
  aval_ir <- list(
    dataset = "ADSL",
    variable = "AVAL2",
    steps = list(list(layer = "assign", args = list(target = "AVAL2", from = "AVAL"))),
    confidence = 0.9,
    needs_human = FALSE,
    rationale = "copy AVAL",
    spec_origin = "copy AVAL"
  )
  out <- mcp_tool_out("aa_validate_ir", list(ir = list(aval_ir)))
  expect_false(out$valid)
  problems <- as.character(out$problems)
  expect_true(any(grepl("BDS artifact", problems)), label = paste(problems, collapse = " | "))
})

test_that("aa_validate_ir absorbs a step-level on into args (foreign-only detection)", {
  ex_ir <- list(
    dataset = "ADSL",
    variable = "TRTSDTM",
    steps = list(list(
      layer = "impute_dtc",
      args = list(
        target = "EXSTDTM",
        dtc = "EXSTDTC",
        output_class = "dtm",
        highest_imputation = "M",
        date_imputation = "first"
      ),
      on = "ex"
    )),
    confidence = 0.9,
    needs_human = FALSE,
    rationale = "impute on ex",
    spec_origin = "impute on ex"
  )
  out <- mcp_tool_out("aa_validate_ir", list(ir = list(ex_ir)))
  expect_false(out$valid)
  problems <- as.character(out$problems)
  expect_true(
    any(grepl("all steps run on foreign datasets", problems)),
    label = paste(problems, collapse = " | ")
  )
})

test_that("aa_render_program returns DISCLAIMER, admiral::derive_vars_dtm, and an 8-char hash", {
  out <- mcp_tool_out("aa_render_program", list(ir = list(valid_ir_arg), backend_label = "rules"))
  expect_true(grepl("DISCLAIMER", out$code, fixed = TRUE))
  expect_true(grepl("admiral::derive_vars_dtm", out$code, fixed = TRUE))
  expect_identical(nchar(out$hash), 8L)
  # `warnings` was always empty (render_program aborts on compat messages) and is gone.
  expect_null(out$warnings)
  expect_setequal(names(out), c("code", "hash"))
})

test_that("aa_render_program wraps render errors as isError content", {
  bogus_ir <- list(
    dataset = "ADSL",
    variable = "TRTSDTM",
    steps = list(list(layer = "bogus_layer", args = list(target = "TRTSDTM"))),
    confidence = 0.9,
    needs_human = FALSE,
    rationale = "x",
    spec_origin = "x"
  )
  resp <- mcp_call("aa_render_program", list(ir = list(bogus_ir)))
  expect_true(resp$result$isError)
  expect_identical(resp$result$content[[1]]$text, MCP_ERRORS$invalid_ir)
})

test_that("aa_render_program hashes are stable for identical IR", {
  out1 <- mcp_tool_out("aa_render_program", list(ir = list(valid_ir_arg)))
  out2 <- mcp_tool_out("aa_render_program", list(ir = list(valid_ir_arg)))
  expect_identical(out1$hash, out2$hash)
})

test_that("aa_dependency_report flags undefined duration endpoints (AGE style)", {
  age_ir <- list(
    dataset = "ADSL",
    variable = "AGE",
    steps = list(list(
      layer = "duration",
      args = list(
        target = "AGE",
        start = "BRTHDT",
        end = "TRTSDT",
        out_unit = "years",
        add_one = FALSE,
        trunc_out = TRUE
      )
    )),
    confidence = 1,
    needs_human = FALSE,
    rationale = "age in years",
    spec_origin = "Age in years between BRTHDT and TRTSDT"
  )
  out <- mcp_tool_out("aa_dependency_report", list(ir = list(age_ir)))
  inputs <- vapply(out, function(r) r$input, character(1))
  expect_setequal(inputs, c("BRTHDT", "TRTSDT"))
  expect_true(all(vapply(out, function(r) identical(r$variable, "AGE"), logical(1))))
  expect_true(all(vapply(out, function(r) grepl("not defined by earlier executable steps", r$issue, fixed = TRUE), logical(1))))
})

test_that("aa_dependency_report whitelists known_columns", {
  age_ir <- list(
    dataset = "ADSL",
    variable = "AGE",
    steps = list(list(
      layer = "duration",
      args = list(target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years")
    )),
    confidence = 1,
    needs_human = FALSE,
    rationale = "age",
    spec_origin = "age"
  )
  out <- mcp_tool_out("aa_dependency_report", list(
    ir = list(age_ir),
    known_columns = list("BRTHDT", "TRTSDT")
  ))
  expect_length(out, 0)
})

test_that("aa_evals reports the corpus with rules accuracy 1 and no failures", {
  out <- mcp_tool_out("aa_evals", list())
  expect_gte(out$cases, 18)
  expect_identical(out$rules_accuracy, 1L)
  expect_length(out$failures, 0)
})

test_that("notifications return NULL and unknown methods return -32601", {
  expect_null(mcp_handle_request(list(jsonrpc = "2.0", method = "notifications/initialized")))
  expect_null(mcp_handle_request(list(jsonrpc = "2.0", method = "tools/list")))
  resp <- mcp_handle_request(list(jsonrpc = "2.0", id = 5, method = "wat/wat"))
  expect_identical(resp$error$code, -32601L)
  expect_match(resp$error$message, "Method not found")
})

test_that("malformed requests are handled with JSON-RPC error objects", {
  resp <- mcp_handle_request(list(jsonrpc = "2.0", id = 1))
  expect_identical(resp$error$code, -32600L)
  resp2 <- mcp_handle_request(42)
  expect_identical(resp2$error$code, -32600L)
  resp3 <- mcp_process_line("{not valid json")
  expect_identical(resp3$error$code, -32700L)
  expect_null(mcp_process_line("   "))
})

test_that("unknown tool names return a JSON-RPC error, not a tool result", {
  resp <- mcp_call("aa_no_such_tool", list())
  expect_identical(resp$error$code, -32602L)
  expect_match(resp$error$message, "unknown tool")
})

test_that("end-to-end: request lines round-trip through mcp_process_line as valid JSON", {
  lines <- c(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}',
    '{"jsonrpc":"2.0","method":"notifications/initialized"}',
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"aa_evals","arguments":{}}}',
    '{"jsonrpc":"2.0","id":4,"method":"wat"}',
    "   "
  )
  resp_lines <- unname(vapply(lines, function(l) {
    r <- mcp_process_line(l)
    if (is.null(r)) "" else jsonlite::toJSON(r, auto_unbox = TRUE, null = "null")
  }, character(1)))
  expect_identical(resp_lines[[3]], "")
  expect_identical(resp_lines[[6]], "")
  init <- jsonlite::fromJSON(resp_lines[[1]], simplifyVector = FALSE)
  expect_identical(init$result$protocolVersion, "2024-11-05")
  lst <- jsonlite::fromJSON(resp_lines[[2]], simplifyVector = FALSE)
  expect_length(lst$result$tools, 5L)
  ev <- jsonlite::fromJSON(resp_lines[[4]], simplifyVector = FALSE)
  expect_false(ev$result$isError)
  expect_gte(jsonlite::fromJSON(ev$result$content[[1]]$text, simplifyVector = FALSE)$cases, 18)
  err <- jsonlite::fromJSON(resp_lines[[5]], simplifyVector = FALSE)
  expect_identical(err$error$code, -32601L)
})

# ---- ingress hardening ----------------------------------------------------

test_that("an over-long line is rejected by the byte cap before the parser runs", {
  # Deliberately unterminated JSON: if fromJSON() ran first this would be a
  # -32700 parse error, so the size verdict proves the cap comes first.
  oversize <- paste0(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"pad":"',
    strrep("A", MCP_MAX_LINE_BYTES), '"'
  )
  expect_gt(nchar(oversize, type = "bytes"), MCP_MAX_LINE_BYTES)
  resp <- mcp_process_line(oversize)
  expect_identical(resp$error$code, -32600L)
  expect_identical(resp$error$message, MCP_ERRORS$request_too_large)
  expect_false(grepl("Parse error", resp$error$message, fixed = TRUE))
  # a normal line is unaffected by the cap
  expect_length(mcp_process_line('{"jsonrpc":"2.0","id":9,"method":"tools/list"}')$result$tools, 5L)
})

test_that("an over-long spec_rows array is rejected before any spec parsing", {
  row <- list(
    variable = "STUDYID", label = "Study Identifier", type = "text",
    origin = "CRF", derivation = "Copied directly from DM.STUDYID"
  )
  resp <- mcp_call("aa_classify", list(
    dataset = "ADSL",
    spec_rows = rep(list(row), MCP_MAX_ARRAY_ITEMS + 1L)
  ))
  expect_null(resp$result)
  expect_identical(resp$error$code, -32602L)
  expect_identical(resp$error$message, MCP_ERRORS$request_too_large)
})

test_that("deeply nested tool arguments are rejected by the depth cap", {
  deep <- list("leaf")
  for (i in seq_len(MCP_MAX_ARGUMENT_DEPTH + 2L)) deep <- list(deep)
  expect_false(mcp_ingress_ok(deep))
  expect_true(mcp_ingress_ok(list(ir = list(valid_ir_arg))))
})

test_that("a marker injected into derivation never reaches the aa_classify response", {
  marker <- "ZZ_PROMPT_INJECTION_MARKER_ZZ"
  resp <- mcp_call("aa_classify", list(dataset = "ADSL", spec_rows = list(list(
    variable = "TRTSDTM",
    label = "Date of First Study Treatment",
    type = "datetime",
    origin = "Derived",
    derivation = paste("Date of first study treatment, imputed from DM RFSTDTC", marker),
    source_dataset = "dm",
    source_variable = "RFSTDTC"
  ))))
  expect_false(resp$result$isError)
  text <- resp$result$content[[1]]$text
  expect_false(grepl(marker, text, fixed = TRUE))
  out <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  expect_match(out$ir[[1]]$spec_origin, "^origin:[0-9a-f]+$")
  expect_identical(out$ir[[1]]$steps[[1]]$layer, "impute_dtc")
})

test_that("a marker injected into spec_origin never reaches generated code comments", {
  marker <- "ZZ_CODE_COMMENT_MARKER_ZZ"
  injected <- valid_ir_arg
  injected$spec_origin <- paste("Date of first study treatment", marker)
  resp <- mcp_call("aa_render_program", list(ir = list(injected)))
  expect_false(resp$result$isError)
  expect_false(grepl(marker, resp$result$content[[1]]$text, fixed = TRUE))
  out <- jsonlite::fromJSON(resp$result$content[[1]]$text, simplifyVector = FALSE)
  expect_false(grepl(marker, out$code, fixed = TRUE))
  expect_true(grepl("# Spec origin: \"origin:", out$code, fixed = TRUE))
})

test_that("tool errors return only the catalogue message, never interpolated caller input", {
  marker <- "ZZ_ERROR_ECHO_MARKER_ZZ"
  # spec_variables() interpolates `dataset` into its condition message.
  resp <- mcp_call("aa_classify", list(dataset = marker, spec_rows = list(list(
    dataset = "ADSL", variable = "STUDYID", label = "Study Identifier",
    type = "text", origin = "CRF", derivation = "Copied directly from DM.STUDYID"
  ))))
  expect_true(resp$result$isError)
  expect_identical(resp$result$content[[1]]$text, MCP_ERRORS$invalid_arguments)
  expect_false(grepl(marker, resp$result$content[[1]]$text, fixed = TRUE))

  # normalize_ir_records() sees an attacker-chosen layer name.
  injected <- valid_ir_arg
  injected$steps <- list(list(layer = paste0("bogus_", marker), args = list(target = "TRTSDTM")))
  resp2 <- mcp_call("aa_render_program", list(ir = list(injected)))
  expect_true(resp2$result$isError)
  expect_identical(resp2$result$content[[1]]$text, MCP_ERRORS$invalid_ir)
  expect_false(grepl(marker, resp2$result$content[[1]]$text, fixed = TRUE))

  # unknown tool and unknown method no longer echo the requested name
  resp3 <- mcp_call(paste0("aa_", marker), list())
  expect_identical(resp3$error$message, MCP_ERRORS$unknown_tool)
  resp4 <- mcp_handle_request(list(jsonrpc = "2.0", id = 5, method = paste0("wat/", marker)))
  expect_identical(resp4$error$message, MCP_ERRORS$method_not_found)
  expect_false(grepl(marker, resp4$error$message, fixed = TRUE))
})

test_that("aa_classify withholds the IR when validate_ir reports problems", {
  out <- mcp_tool_out("aa_classify", list(dataset = "ADSL", spec_rows = list(list(
    variable = "AVAL2", label = "Copy of AVAL", type = "float", origin = "Derived",
    derivation = "Copied directly from the source record",
    source_variable = "AVAL"
  ))))
  expect_null(out$ir)
  expect_gt(length(out$problems), 0)
  problems <- as.character(out$problems)
  expect_true(any(grepl("BDS artifact", problems)), label = paste(problems, collapse = " | "))
})

test_that("spec origin digests are stable and collision-distinct", {
  expect_identical(mcp_origin_digest("same text"), mcp_origin_digest("same text"))
  expect_false(identical(mcp_origin_digest("text a"), mcp_origin_digest("text b")))
  expect_true(is.na(mcp_origin_digest(NA_character_)))
  expect_true(is.na(mcp_origin_digest("")))
})

# ---- free-text redaction: rationale, symmetrically with spec_origin -------

test_that("free-text digests are prefixed by field so the two never collide", {
  expect_identical(mcp_text_digest("same text", "rationale"),
                   mcp_text_digest("same text", "rationale"))
  expect_false(identical(mcp_text_digest("a", "rationale"), mcp_text_digest("b", "rationale")))
  expect_true(is.na(mcp_text_digest(NA_character_, "rationale")))
  expect_true(is.na(mcp_text_digest("", "rationale")))
  # identical input in the two fields must not produce identical output
  expect_false(identical(mcp_origin_digest("x"), mcp_text_digest("x", "rationale")))
  expect_match(mcp_text_digest("x", "rationale"), "^rationale:[0-9a-f]+$")
})

test_that("mcp_redact_ir digests both free-text fields and leaves semantics alone", {
  red <- mcp_redact_ir(list(valid_ir_arg))[[1]]
  expect_match(red$spec_origin, "^origin:[0-9a-f]+$")
  expect_match(red$rationale, "^rationale:[0-9a-f]+$")
  expect_identical(red$dataset, valid_ir_arg$dataset)
  expect_identical(red$variable, valid_ir_arg$variable)
  expect_identical(red$steps, valid_ir_arg$steps)
  expect_identical(red$confidence, valid_ir_arg$confidence)
  expect_identical(red$needs_human, valid_ir_arg$needs_human)
})

test_that("a marker injected into rationale never reaches any MCP tool response", {
  marker <- "ZZ_RATIONALE_ECHO_MARKER_ZZ"
  injected <- valid_ir_arg
  injected$rationale <- paste("impute DM RFSTDTC", marker)

  for (tool in c("aa_validate_ir", "aa_render_program", "aa_dependency_report")) {
    resp <- mcp_call(tool, list(ir = list(injected)))
    expect_false(resp$result$isError, label = paste("tool", tool, "returned isError"))
    expect_false(
      grepl(marker, resp$result$content[[1]]$text, fixed = TRUE),
      label = paste("marker echoed by", tool)
    )
  }
})

test_that("a marker injected into rationale never reaches generated code comments", {
  marker <- "ZZ_RATIONALE_CODE_MARKER_ZZ"
  injected <- valid_ir_arg
  injected$rationale <- paste("impute DM RFSTDTC", marker)
  out <- mcp_tool_out("aa_render_program", list(ir = list(injected)))
  expect_false(grepl(marker, out$code, fixed = TRUE))
  expect_true(grepl("# Agent rationale: rationale:", out$code, fixed = TRUE))
  # the spec_origin redaction A13 added still holds in the same program
  expect_true(grepl("# Spec origin: \"origin:", out$code, fixed = TRUE))
})

test_that("aa_classify returns the rationale as a digest, not the rule text", {
  out <- mcp_tool_out("aa_classify", list(
    dataset = "ADSL",
    spec_rows = list(list(
      variable = "TRTSDTM",
      label = "Date of First Study Treatment",
      type = "datetime",
      origin = "Derived",
      derivation = "Date of first study treatment, imputed from DM RFSTDTC",
      source_dataset = "dm",
      source_variable = "RFSTDTC"
    ))
  ))
  expect_match(out$ir[[1]]$rationale, "^rationale:[0-9a-f]+$")
  expect_match(out$ir[[1]]$spec_origin, "^origin:[0-9a-f]+$")
  # the rules backend writes "rule: ..." rationales; none of that text escapes
  expect_false(grepl("rule:", out$ir[[1]]$rationale, fixed = TRUE))
  expect_identical(out$ir[[1]]$steps[[1]]$layer, "impute_dtc")
})

# ---- line-size cap: scope of the guarantee --------------------------------
#
# Decision pinned here: the byte cap bounds what the PARSER sees, not what
# mcp_serve()'s readLines() allocates. Bounded chunked reads were measured on
# this platform and block until the chunk fills or stdin closes, which would
# deadlock a normal request/response session, so the read-path residual is
# accepted and documented at mcp_serve(). These tests pin what the cap does
# guarantee: oversize lines are refused before parsing, and a legitimate
# large-but-under-cap line still round-trips.

test_that("a large but under-cap request line still round-trips successfully", {
  rows <- lapply(seq_len(400L), function(i) {
    list(
      variable = sprintf("V%03d", i),
      label = "Padded Variable",
      type = "text",
      origin = "Derived",
      derivation = paste("Free text derivation", strrep("x", 500L))
    )
  })
  line <- as.character(jsonlite::toJSON(
    list(jsonrpc = "2.0", id = 11, method = "tools/call",
         params = list(name = "aa_classify", arguments = list(dataset = "ADSL", spec_rows = rows))),
    auto_unbox = TRUE
  ))
  nbytes <- nchar(line, type = "bytes")
  expect_gt(nbytes, 100000L)
  expect_lt(nbytes, MCP_MAX_LINE_BYTES)

  resp <- mcp_process_line(line)
  expect_null(resp$error)
  expect_false(resp$result$isError)
  out <- jsonlite::fromJSON(resp$result$content[[1]]$text, simplifyVector = FALSE)
  expect_length(out$problems, 0)
  expect_length(out$ir, 400L)
  # padding text is client free text and must not come back either
  expect_false(grepl(strrep("x", 500L), resp$result$content[[1]]$text, fixed = TRUE))
})
