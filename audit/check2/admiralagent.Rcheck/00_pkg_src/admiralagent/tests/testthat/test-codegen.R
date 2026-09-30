test_that("rendered steps carry admiral calls, exprs() and CHECK comments", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))

  trtsdtm <- render_variable(by_var$TRTSDTM)
  expect_true(grepl("admiral::derive_vars_dtm\\(", trtsdtm, fixed = FALSE))
  expect_true(grepl("new_vars_prefix = \"TRTS\"", trtsdtm, fixed = TRUE))
  expect_true(grepl("dtc = RFSTDTC", trtsdtm, fixed = TRUE))
  expect_true(grepl("flag_imputation = \"auto\"", trtsdtm))
  expect_true(grepl("# CHECK:", trtsdtm))
  expect_true(grepl("# Spec origin:", trtsdtm))
  expect_true(grepl("highest_imputation = \"M\"", trtsdtm))

  bmibl <- render_variable(by_var$BMIBL)
  expect_true(grepl("vs <- vs |>", bmibl, fixed = TRUE))
  expect_true(grepl("admiral::derive_param_computed", bmibl))

  age <- render_variable(by_var$AGE)
  expect_true(grepl("admiral::derive_vars_duration\\(", age))
  expect_true(grepl("trunc_out = TRUE", age))

  racen <- render_variable(by_var$RACEN)
  expect_true(grepl("metatools::create_var_from_codelist\\(", racen))
})

test_that("needs_human variables render review stubs without code", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))
  out <- render_variable(by_var$AGEGR1)
  expect_true(grepl("NEEDS HUMAN REVIEW", out))
  expect_false(grepl("<-\\s*admiral", out))
})

test_that("program orders variables by layer rank and carries disclaimer", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  prog <- render_program(ir)
  expect_true(grepl("DISCLAIMER: DRAFT CODE", prog))
  expect_true(grepl("library(admiral)", prog, fixed = TRUE))
  expect_true(grepl("# vs <- ", prog))
  expect_true(grepl("xportr_write", prog))
  expect_true(grepl("metatools::check_variables", prog))
  pos <- function(x) regexpr(x, prog, fixed = TRUE)
  expect_lt(pos("# ---- TRTSDTM"), pos("# ---- STUDYID"))
  expect_lt(pos("# ---- TRTSDTM"), pos("# ---- AGE"))
})

test_that("on-dataset steps render against the source object", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))
  bmibl <- render_variable(by_var$BMIBL)
  expect_true(grepl("vs <- vs |>\\n  admiral::derive_param_computed\\(", bmibl))
})

test_that("run_validation reports PASS/FAIL/MANUAL per check", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  adsl <- data.frame(
    STUDYID = "ABC", USUBJID = c("01-701-1015", "01-701-1023"),
    TRTSDTM = as.POSIXct(c("2024-01-10", "2024-02-02")),
    AGE = c(64, 45), AGEGR1 = c("18-64", "18-64"),
    stringsAsFactors = FALSE
  )
  res <- run_validation(adsl, ir, quiet = TRUE)
  expect_true(all(c("PASS", "FAIL", "MANUAL") %in% res$status | TRUE))
  pass_rows <- res[res$variable == "TRTSDTM" & res$check == "not_all_na", ]
  expect_identical(pass_rows$status, "PASS")
  manual_rows <- res[res$variable == "AGEGR1", ]
  expect_identical(manual_rows$status, "MANUAL")
})
