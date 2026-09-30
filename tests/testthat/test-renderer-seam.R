# Renderer seam: the R leaks that made admiralagent's output R-shaped rather
# than language-shaped, and the seam that lets a second language be added
# without moving derivation semantics out of the registry.
#
#   1. admiral's *DTF/*TMF naming is part of the DEPENDENCY GRAPH, so it is
#      declared by the registry `products()` hook, not re-synthesised.
#   2. literal quoting is per-language (`quote_literal()`), not JSON escaping.
#   3. filters carry a structured predicate AST alongside their text.
#   4. `aa_layers()[[l]]$render[[language]]`, R implemented, others stubs.
#   5. `render_study()` emits deliverables in topological order plus a driver.
#
# The headline requirement is that none of this moves a single byte of the
# rendered R output.

SEAM_ARGS <- list(
  assign = list(target = "TRT01P", from = "ARM"),
  merge_var = list(target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
                   by_vars = c("STUDYID", "USUBJID"), order = "EXSTDTM", mode = "first"),
  lookup_join = list(target = "PARAMCD", source = "PARNCD", dataset_lookup = "lk",
                     by_vars = "VSTESTCD"),
  impute_dtc = list(target = "EXSTDTM", dtc = "EXSTDTC", output_class = "dtm",
                    highest_imputation = "M", date_imputation = "first"),
  dtm_to_dt = list(target = "TRTSDT", source = "TRTSDTM"),
  duration = list(target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years",
                  add_one = FALSE, trunc_out = TRUE),
  date_shift = list(target = "TRTEDT", source = "TRTSDT", days = 7),
  compute_param = list(paramcd = "BMI", param = "Body Mass Index",
                       parameters = c("WEIGHT", "HEIGHT"),
                       formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
                       by_vars = c("STUDYID", "USUBJID")),
  summary_record = list(paramcd = "AVERAGE", param = "Average", by_vars = "USUBJID",
                        summary_fun = "mean"),
  extreme_flag = list(target = "ABLFL", by_vars = "USUBJID", order = "ADT", mode = "last"),
  codelist_var = list(target = "RACEN", from = "RACE", decode_to_code = TRUE),
  obs_number = list(target = "ASEQ", by_vars = "USUBJID", order = "ADT"),
  categorize = list(target = "AGEGR1", from = "AGE", breaks = c(0, 18, 65, 200),
                    labels = c("<18", "18-64", ">=65")),
  compute_var = list(target = "CHG", formula = "AVAL - BASE")
)

# The pre-seam quoter, kept here so the apostrophe claim below is a real
# comparison and not an assertion about code that no longer exists.
legacy_q_chr <- function(x) {
  vapply(x, function(value) as.character(jsonlite::toJSON(enc2utf8(value), auto_unbox = TRUE)),
         character(1), USE.NAMES = FALSE)
}

# ---- 4. render is a per-language renderer set -------------------------------

test_that("every layer exposes an r renderer and stubs for the other languages", {
  layers <- aa_layers()
  for (nm in layer_names()) {
    expect_true(is.function(layers[[nm]]$render[["r"]]), info = nm)
    expect_true(layer_implements(layers[[nm]], "r"), info = nm)
    for (language in c("sas", "python")) {
      expect_false(layer_implements(layers[[nm]], language), info = paste(nm, language))
      expect_error(
        layers[[nm]]$render[[language]](SEAM_ARGS[[nm]], "adsl"),
        "NotImplemented", info = paste(nm, language)
      )
    }
  }
})

test_that("an unknown render language is rejected by name", {
  expect_error(aa_layers()$assign$render[["cobol"]], "known languages")
  expect_error(
    render_program(classify_variables(mock_spec_adsl(), "ADSL", backend = "rules"), language = "cobol"),
    "language must be one of"
  )
})

test_that("GOLDEN: $render[['r']] is byte-identical to the legacy $render call", {
  layers <- aa_layers()
  for (nm in layer_names()) {
    legacy <- layers[[nm]]$render(SEAM_ARGS[[nm]], "adsl")
    seam <- layers[[nm]]$render[["r"]](SEAM_ARGS[[nm]], "adsl")
    expect_identical(seam, legacy, info = nm)
  }
})

test_that("GOLDEN: pinned rendered text for the quoting-sensitive layers", {
  layers <- aa_layers()
  expect_identical(
    layers$impute_dtc$render[["r"]](SEAM_ARGS$impute_dtc, "ex"),
    paste0(
      "ex <- ex |>\n  admiral::derive_vars_dtm(\n",
      "    new_vars_prefix = \"EXST\",\n",
      "    dtc = EXSTDTC,\n",
      "    highest_imputation = \"M\",\n",
      "    date_imputation = \"first\",\n",
      "    flag_imputation = \"auto\"\n  )"
    )
  )
  expect_identical(
    layers$compute_var$render[["r"]](SEAM_ARGS$compute_var, "advs"),
    "advs <- advs |> dplyr::mutate(CHG = AVAL - BASE)"
  )
})

test_that("render_program(language = 'sas') errors naming the unimplemented layers", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  err <- tryCatch(render_program(ir, language = "sas"), error = function(e) conditionMessage(e))

  expect_match(err, "NotImplemented", fixed = TRUE)
  expect_match(err, "sas", fixed = TRUE)
  # Every executable layer the spec actually uses must be named in the message.
  used <- sort(unique(unlist(lapply(ir, function(v) {
    if (isTRUE(v$needs_human)) return(character())
    vapply(v$steps, function(s) s$layer, character(1))
  }))))
  expect_gt(length(used), 0L)
  for (nm in used) expect_match(err, nm, fixed = TRUE)
  # ... and no layer the spec does not use is named.
  for (nm in setdiff(layer_names(), used)) expect_false(grepl(nm, err, fixed = TRUE))
})

test_that("render_program(language = 'r') is unchanged", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_identical(render_program(ir, language = "r"), render_program(ir))
})

# ---- 2. per-language literal quoting ----------------------------------------

test_that("an apostrophe in PARAM text round-trips through quote_literal()", {
  param <- "Investigator's choice of therapy"

  literal <- quote_literal(param, "r")
  expect_identical(eval(parse(text = literal)), param)
  # R output is byte-for-byte what the JSON quoter produced, so no golden moves.
  expect_identical(literal, legacy_q_chr(param))

  # ... but the JSON quoter was never a quoting rule, only a coincidence with
  # R's. It leaves the apostrophe bare, which terminates a SAS literal early;
  # the per-language quoter doubles it.
  expect_identical(quote_literal(param, "sas"), "'Investigator''s choice of therapy'")
  expect_false(grepl("''", legacy_q_chr(param), fixed = TRUE))
  expect_identical(quote_literal(param, "python"), "'Investigator\\'s choice of therapy'")

  expect_error(quote_literal(param, "cobol"), "no literal quoting rule")
})

test_that("quote_literal('r') survives quotes, backslashes and non-ASCII", {
  for (value in c("a\"b", "back\\slash", "café", "Don't", "Y")) {
    expect_identical(eval(parse(text = quote_literal(value, "r"))), value, info = value)
  }
})

test_that("apostrophe PARAM text reaches the rendered program intact", {
  param <- "Subject's Global Impression"
  args <- utils::modifyList(SEAM_ARGS$compute_param, list(param = param))
  code <- aa_layers()$compute_param$render[["r"]](args, "advs")

  expect_true(grepl(paste0("PARAM = ", quote_literal(param, "r")), code, fixed = TRUE))
  literal <- regmatches(code, regexpr("(?<=PARAM = )\"[^\"]*\"", code, perl = TRUE))
  expect_identical(eval(parse(text = literal)), param)
})

# ---- 3. structured predicate AST alongside the filter text ------------------

test_that("the predicate AST reconstructs the original filter text", {
  for (text in c("EXDOSE > 0",
                 "VISIT == \"BASELINE\"",
                 "PARAMCD == \"BMI\"",
                 "EXDOSE > 0 & VISIT == \"BASELINE\"",
                 "!(AVAL < 0) | ABLFL == \"Y\"")) {
    ast <- parse_predicate(text)
    expect_identical(deparse_predicate(ast, "r"), text, info = text)
  }
})

test_that("a single-quoted source filter deparses to canonical R and is a fixed point", {
  # The rules backend writes filters with single quotes; R's canonical literal
  # form uses double quotes, so the AST normalises rather than echoes.
  ast <- parse_predicate("ABLFL == 'Y'")
  canonical <- deparse_predicate(ast, "r")

  expect_identical(canonical, "ABLFL == \"Y\"")
  expect_identical(parse_predicate(canonical), ast)
  expect_true(identical(parse(text = "ABLFL == 'Y'")[[1]], parse(text = canonical)[[1]]))
})

test_that("predicate deparsing refuses languages it has not implemented", {
  ast <- parse_predicate("EXDOSE > 0")
  expect_error(deparse_predicate(ast, "sas"), "NotImplemented")
})

test_that("predicate column and PARAMCD extraction match the pre-AST behaviour", {
  for (text in c("EXDOSE > 0", "VISIT == \"BASELINE\"", "ABLFL == 'Y'",
                 "PARAMCD == 'BMI' & AVAL > 0", "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
                 "AVAL - BASE")) {
    expect_identical(predicate_names(parse_predicate(text)),
                     all.vars(parse(text = text)), info = text)
  }
  expect_identical(filter_parameters("PARAMCD == 'BMI'"), "BMI")
  expect_identical(filter_parameters("'HEIGHT' == PARAMCD & VISIT == 'BASELINE'"), "HEIGHT")
  expect_identical(filter_parameters("EXDOSE > 0"), character())
  expect_null(parse_predicate("this is ( not parseable"))
})

test_that("step_predicates carries text and AST for registry-declared filter args", {
  step <- new_step("merge_var", list(
    target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
    by_vars = c("STUDYID", "USUBJID"), mode = "first", filter = "EXDOSE > 0"
  ))
  preds <- step_predicates(step)

  expect_identical(names(preds), "filter")
  expect_identical(preds$filter$text, "EXDOSE > 0")
  expect_identical(deparse_predicate(preds$filter$ast, "r"), "EXDOSE > 0")

  # A step without a filter carries no predicate, and layers that declare no
  # predicate args never produce one.
  bare <- new_step("assign", list(target = "TRT01P", from = "ARM"))
  expect_identical(step_predicates(bare), list())
  expect_identical(aa_layers()$assign$predicates, character())
  expect_identical(aa_layers()$extreme_flag$predicates, "restrict_filter")
})

# ---- 1. *DTF/*TMF naming promoted into the registry -------------------------

test_that("the registry products() hook owns the *DTF/*TMF naming", {
  layers <- aa_layers()
  expect_identical(
    layers$impute_dtc$products(SEAM_ARGS$impute_dtc)$columns,
    c("EXSTDTM", "EXSTDTF", "EXSTTMF")
  )
  expect_identical(
    layers$impute_dtc$products(list(target = "TRTSDT", output_class = "dt"))$columns,
    c("TRTSDT", "TRTSDTF")
  )
  # Parameter-adding layers produce parameters, never a column ...
  expect_identical(layers$compute_param$products(SEAM_ARGS$compute_param),
                   list(parameters = "BMI"))
  expect_identical(layers$summary_record$products(SEAM_ARGS$summary_record),
                   list(parameters = "AVERAGE"))
  # ... and every other layer produces its target column by default.
  for (nm in setdiff(layer_names(), c("impute_dtc", "compute_param", "summary_record"))) {
    expect_identical(layers[[nm]]$products(SEAM_ARGS[[nm]]),
                     list(columns = SEAM_ARGS[[nm]]$target), info = nm)
  }
})

test_that("MIRROR: registry naming agrees with the execution idempotency guard", {
  # step_products() (R/dependency.R) and step_output_columns() (R/execute.R)
  # must agree on the imputation output columns, or the idempotency guard stops
  # recognising columns a variable already produced and re-running corrupts it.
  cases <- list(
    list(target = "TRTSDTM", dtc = "RFSTDTC", output_class = "dtm",
         highest_imputation = "M", date_imputation = "first"),
    list(target = "TRTEDT", dtc = "RFENDTC", output_class = "dt",
         highest_imputation = "M", date_imputation = "last"),
    list(target = "EXSTDTM", dtc = "EXSTDTC", output_class = "dtm",
         highest_imputation = "D", date_imputation = "first")
  )
  for (args in cases) {
    step <- new_step("impute_dtc", args)
    expect_identical(
      impute_dtc_outputs(args$target, args$output_class),
      step_output_columns(step),
      info = args$target
    )
    v <- new_variable_ir("ADSL", args$target, list(step))
    expect_identical(step_products(v, step)$input, step_output_columns(step), info = args$target)
  }
})

# ---- 5. render_study ---------------------------------------------------------

seam_study_ir <- function() {
  list(
    new_variable_ir("ADSL", "TRTSDTM", list(
      new_step("assign", list(target = "TRTSDTM", from = "RFXSTDTC"))
    )),
    new_variable_ir("ADTTE", "STARTDTM", list(
      new_step("merge_var", list(
        target = "STARTDTM", source = "TRTSDTM", dataset_add = "ADSL",
        by_vars = c("STUDYID", "USUBJID"), mode = "first"
      ))
    ))
  )
}

test_that("render_study emits one program per deliverable in topological order", {
  ir <- seam_study_ir()
  study <- render_study(ir)

  expect_identical(study$order, c("ADSL", "ADTTE"))
  expect_identical(names(study$programs), c("ADSL", "ADTTE"))
  expect_true(grepl("# ADSL analysis dataset program", study$programs$ADSL, fixed = TRUE))
  expect_true(grepl("# ADTTE analysis dataset program", study$programs$ADTTE, fixed = TRUE))
  # The producer must come first no matter what order the IR arrives in.
  expect_identical(render_study(rev(ir))$order, c("ADSL", "ADTTE"))
})

test_that("render_study's driver sources the programs in that order with a DISCLAIMER", {
  study <- render_study(seam_study_ir())

  expect_true(grepl("DISCLAIMER: DRAFT CODE", study$driver, fixed = TRUE))
  expect_true(grepl("# CHECK:", study$driver, fixed = TRUE))
  expect_identical(unlist(study$files, use.names = FALSE), c("adsl.R", "adtte.R"))
  expect_lt(
    regexpr("source(\"adsl.R\")", study$driver, fixed = TRUE),
    regexpr("source(\"adtte.R\")", study$driver, fixed = TRUE)
  )
})

test_that("a cyclic deliverable graph is unscheduleable and named as such", {
  ir <- c(seam_study_ir(), list(
    new_variable_ir("ADTTE", "CNSR", list(
      new_step("assign", list(target = "CNSR", literal = "0"))
    )),
    new_variable_ir("ADSL", "LSTCNSR", list(
      new_step("merge_var", list(
        target = "LSTCNSR", source = "CNSR", dataset_add = "ADTTE",
        by_vars = c("STUDYID", "USUBJID"), mode = "first"
      ))
    ))
  ))

  # deliverable_order() degrades rather than erroring, marking the members ...
  expect_identical(attr(deliverable_order(ir), "cycle_datasets"), c("ADSL", "ADTTE"))
  # ... and render_study() never emits a driver for an unscheduleable study.
  expect_error(render_study(ir), "cyclic")
  expect_error(render_study(ir), "ADSL")
})

test_that("render_study propagates the unimplemented-language failure", {
  expect_error(render_study(seam_study_ir(), language = "sas"), "NotImplemented")
})

test_that("deliverable_order is a valid permutation of the deliverable nodes", {
  ir <- seam_study_ir()
  expect_setequal(deliverable_order(ir), deliverable_graph(ir)$nodes)
  expect_identical(deliverable_order(list()), character())
  # A single-deliverable spec is trivially ordered and carries no cycle mark.
  adsl <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_identical(as.character(deliverable_order(adsl)), "ADSL")
  expect_null(attr(deliverable_order(adsl), "cycle_datasets"))
})

# ---- REGRESSION GUARD --------------------------------------------------------

test_that("REGRESSION: pinned artifact hash and variable order are unchanged", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")

  expect_equal(artifact_hash(ir), "84a18650")
  expect_equal(
    vapply(order_variables(ir), function(v) v$variable, character(1)),
    c("TRTSDTM", "TRTEDTM", "AGE", "RACEN", "STUDYID", "USUBJID", "BMIBL", "SUBJID", "TRT01P", "AGEGR1")
  )
  expect_length(validate_ir(ir), 0L)

  # The flag columns really do reach the graph through the registry hook: this
  # is the edge that makes TRTSDTM's imputation visible to later consumers.
  trtsdtm <- Filter(function(v) v$variable == "TRTSDTM", ir)[[1]]
  keys <- variable_product_keys(trtsdtm)
  expect_true(any(grepl("::column::TRTSDTF$", keys)))
  expect_true(any(grepl("::column::TRTSTMF$", keys)))
})
