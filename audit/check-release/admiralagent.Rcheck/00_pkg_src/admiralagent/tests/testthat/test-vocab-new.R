ir_1_5 <- list(new_variable_ir(
  "ADSL", "TRTSDTM",
  list(new_step("impute_dtc", list(
    target = "TRTSDTM", dtc = "RFSTDTC", output_class = "dtm",
    highest_imputation = "M", date_imputation = "first"
  ))),
  spec_origin = "first dose datetime"
))

ir_plain <- list(new_variable_ir(
  "ADSL", "AGE",
  list(new_step("duration", list(
    target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years"
  ))),
  spec_origin = "age"
))

test_that("dtm_to_dt renders the installed admiral 1.5 API", {
  code <- aa_layers()$dtm_to_dt$render(list(target = "TRTSDT", source = "TRTSDTM"), "adsl")
  expect_true(grepl("admiral::derive_vars_dtm_to_dt", code, fixed = TRUE))
  expect_true(grepl("source_vars = exprs(TRTSDTM)", code, fixed = TRUE))
  expect_false(grepl("convert_dtm_to_dt", code, fixed = TRUE))
})

test_that("date_shift renders mutate with as.Date arithmetic, negative days included", {
  plus <- aa_layers()$date_shift$render(list(target = "TRTEDT", source = "TRTSDT", days = 30), "adsl")
  expect_true(grepl("dplyr::mutate(TRTEDT = as.Date(TRTSDT) + 30)", plus, fixed = TRUE))
  minus <- aa_layers()$date_shift$render(list(target = "TRTEDT", source = "TRTSDT", days = -7), "adsl")
  expect_true(grepl("TRTEDT = as.Date(TRTSDT) + -7", minus, fixed = TRUE))
})

test_that("categorize renders cut() with explicit args and always appends its CHECK comment", {
  args <- list(target = "AGEGR1", from = "AGE", breaks = c(0, 18, 65, 200),
               labels = c("<18", "18-64", ">=65"))
  code <- aa_layers()$categorize$render(args, "adsl")
  expect_true(grepl("AGEGR1 = cut(", code, fixed = TRUE))
  expect_true(grepl("breaks = c(0, 18, 65, 200)", code, fixed = TRUE))
  expect_true(grepl('labels = c("<18", "18-64", ">=65")', code, fixed = TRUE))
  expect_true(grepl("right = TRUE", code, fixed = TRUE))
  expect_true(grepl("include.lowest = TRUE", code, fixed = TRUE))
  expect_identical(
    tail(strsplit(code, "\n")[[1]], 1),
    "# CHECK: human must confirm breakpoints and labels before use"
  )
  flipped <- aa_layers()$categorize$render(
    c(args, list(right = FALSE, include_lowest = FALSE)), "adsl")
  expect_true(grepl("right = FALSE", flipped, fixed = TRUE))
  expect_true(grepl("include.lowest = FALSE", flipped, fixed = TRUE))
  expect_identical(
    tail(strsplit(flipped, "\n")[[1]], 1),
    "# CHECK: human must confirm breakpoints and labels before use"
  )
})

test_that("valid IR for the three new layers passes the gate", {
  ir <- list(
    new_variable_ir("ADSL", "TRTSDT", list(new_step("dtm_to_dt", list(
      target = "TRTSDT", source = "TRTSDTM"
    )))),
    new_variable_ir("ADSL", "TRTEDT", list(new_step("date_shift", list(
      target = "TRTEDT", source = "TRTSDT", days = 7
    )))),
    new_variable_ir("ADSL", "AGEGR1", list(new_step("categorize", list(
      target = "AGEGR1", from = "AGE", breaks = c(0, 18, 65, 200),
      labels = c("<18", "18-64", ">=65")
    ))))
  )
  expect_length(validate_ir(ir), 0)
})

test_that("categorize label length mismatch and non-numeric breaks are rejected", {
  bad_len <- list(new_variable_ir("ADSL", "AGEGR1", list(new_step("categorize", list(
    target = "AGEGR1", from = "AGE", breaks = c(0, 18, 65, 200), labels = c("<18", "18+")
  )))))
  probs <- validate_ir(bad_len)
  expect_true(any(grepl("labels", probs, fixed = TRUE)))
  expect_true(any(grepl("length(breaks) - 1", probs, fixed = TRUE)))

  bad_breaks <- list(new_variable_ir("ADSL", "AGEGR1", list(new_step("categorize", list(
    target = "AGEGR1", from = "AGE", breaks = c("0", "18"), labels = "x"
  )))))
  expect_true(any(grepl("'breaks' must be a numeric", validate_ir(bad_breaks), fixed = TRUE)))
})

test_that("date_shift non-numeric days is rejected", {
  bad <- list(new_variable_ir("ADSL", "TRTEDT", list(new_step("date_shift", list(
    target = "TRTEDT", source = "TRTSDT", days = "one"
  )))))
  expect_true(any(grepl("'days' must be numeric", validate_ir(bad), fixed = TRUE)))
})

test_that("check_admiral_compat flags versions older than the layer requirement", {
  msg <- check_admiral_compat(ir_1_5, installed = "1.4.0")
  expect_length(msg, 1)
  expect_true(grepl("admiral", msg))
  expect_true(grepl("1.4.0", msg, fixed = TRUE))
  expect_true(grepl("1.5.0", msg, fixed = TRUE))
  expect_true(grepl("impute_dtc", msg, fixed = TRUE))
})

test_that("check_admiral_compat passes at and above the required version", {
  expect_length(check_admiral_compat(ir_1_5, installed = "1.5.0"), 0)
  expect_length(check_admiral_compat(ir_1_5, installed = "1.5.0.9011"), 0)
})

test_that("check_admiral_compat without admiral installed returns an annotated empty result", {
  out <- check_admiral_compat(ir_1_5, installed = NULL)
  expect_length(out, 0)
  expect_false(is.null(attr(out, "note")))
  expect_true(grepl("admiral", attr(out, "note")))
})

test_that("ir without admiral-1.5-only layers never requires an upgrade", {
  expect_length(check_admiral_compat(ir_plain, installed = "0.3.0"), 0)
})

test_that("layer_docs and build_system_prompt expose the new vocabulary", {
  docs <- paste(layer_docs(), collapse = "\n\n")
  for (nm in c("dtm_to_dt", "date_shift", "categorize")) {
    expect_true(grepl(paste0("layer: ", nm), docs, fixed = TRUE), info = nm)
  }
  prompt <- build_system_prompt()
  expect_true(grepl("dtm_to_dt", prompt, fixed = TRUE))
  expect_true(grepl("date_shift", prompt, fixed = TRUE))
  expect_true(grepl("categorize", prompt, fixed = TRUE))
})

test_that("render_program still renders a real ir under the guard", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  prog <- render_program(ir)
  expect_true(grepl("DISCLAIMER: DRAFT CODE", prog, fixed = TRUE))
})

test_that("render_program stops when the compat guard reports a version problem", {
  guard_env <- environment(render_program)
  mock <- function(ir, installed = NA) {
    "admiral 1.5.0 or newer is required by layer(s) impute_dtc, but admiral 1.4.0 is installed"
  }
  if (bindingIsLocked("check_admiral_compat", guard_env)) {
    local_mocked_bindings(check_admiral_compat = mock, .package = "admiralagent")
  } else {
    orig <- get("check_admiral_compat", envir = guard_env)
    assign("check_admiral_compat", mock, envir = guard_env)
    on.exit(assign("check_admiral_compat", orig, envir = guard_env), add = TRUE)
  }
  expect_error(
    render_program(ir_1_5),
    "admiral 1.5.0 or newer is required"
  )
})
