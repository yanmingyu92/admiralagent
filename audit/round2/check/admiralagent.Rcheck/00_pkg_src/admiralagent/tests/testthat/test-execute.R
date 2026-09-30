pilot_sources <- function(mc = NULL) {
  skip_if_not_installed("admiral")
  skip_if_not_installed("pharmaversesdtm")
  suppressMessages(library(pharmaversesdtm))
  e <- new.env(parent = globalenv())
  data("dm", envir = e); data("ex", envir = e); data("vs", envir = e)
  vs_bds <- e$vs
  vs_bds$AVAL <- vs_bds$VSSTRESN
  vs_bds$PARAMCD <- vs_bds$VSTESTCD
  out <- list(base = e$dm, ex = e$ex, vs = vs_bds)
  if (!is.null(mc)) out$mc <- mc
  out
}

test_that("execute_ir requires a base element in sources", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_error(execute_ir(ir, sources = list()), "base")
  expect_error(execute_ir(ir, sources = list(ex = data.frame(a = 1))), "base")
})

test_that("execute_ir accepts the lower-cased target dataset name as base", {
  ir <- list(new_variable_ir("ADSL", "STUDYID", list(
    new_step("assign", list(target = "STUDYID", literal = "ABC")
    ))))
  res <- execute_ir(ir, sources = list(adsl = data.frame(x = 1:3)))
  expect_identical(res$adsl$STUDYID, rep("ABC", 3))
  expect_identical(res$status$status, "EXECUTED")
})

test_that("needs_human variables report REVIEW without executing", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  res <- execute_ir(ir, sources = list(base = data.frame(USUBJID = "x")), variables = "AGEGR1")
  expect_identical(res$status$status, "REVIEW")
  expect_identical(res$status$variable, "AGEGR1")
})

test_that("execution errors are captured as ERROR status, not thrown", {
  ir <- list(new_variable_ir("ADSL", "AGE", list(
    new_step("duration", list(
      target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years"
    ))
  )))
  res <- execute_ir(ir, sources = list(base = data.frame(USUBJID = "x")))
  expect_identical(res$status$status, "ERROR")
  expect_true(nzchar(res$status$note))
})

test_that("variables filter restricts execution", {
  base <- data.frame(USUBJID = c("a", "b"), ARM = c("A", "B"))
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  res <- execute_ir(ir, sources = list(base = base), variables = "TRT01P")
  expect_setequal(res$status$variable, "TRT01P")
  expect_identical(res$status$status, "EXECUTED")
  expect_true("TRT01P" %in% names(res$adsl))
  expect_false("STUDYID" %in% names(res$adsl))
})

test_that("idempotency guard drops prior outputs before re-execution", {
  base <- data.frame(USUBJID = c("a", "b"), STALE = c(1, 2))
  ir <- list(new_variable_ir("ADSL", "STUDYID", list(
    new_step("assign", list(target = "STUDYID", literal = "ABC")
    ))))
  res <- execute_ir(ir, sources = list(base = base))
  expect_true("STALE" %in% names(res$adsl))
  res2 <- execute_ir(ir, sources = list(base = base))
  expect_identical(names(res$adsl), names(res2$adsl))
  expect_equal(res$adsl, res2$adsl)
})

test_that("mock spec IR executes on pilot data, TRTSDTM derived, re-runnable", {
  sources <- pilot_sources()
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_length(validate_ir(ir), 0)

  res1 <- execute_ir(ir, sources = sources)
  st <- stats::setNames(res1$status$status, res1$status$variable)
  expect_identical(unname(st[c("STUDYID", "USUBJID", "SUBJID", "TRT01P",
                               "TRTSDTM", "TRTEDTM")]),
                   rep("EXECUTED", 6))
  expect_true("TRTSDTM" %in% names(res1$adsl))
  expect_true(any(!is.na(res1$adsl$TRTSDTM)))

  res2 <- execute_ir(ir, sources = sources)
  expect_identical(names(res1$adsl), names(res2$adsl))
  expect_equal(res1$adsl, res2$adsl)

  res3 <- execute_ir(ir, sources = list(base = res1$adsl, ex = sources$ex, vs = sources$vs))
  # re-running with the previous result as base: same columns and values;
  # column ORDER differs because pre-existing columns keep their position
  # while re-derived ones are dropped by the guard and re-appended
  expect_setequal(names(res1$adsl), names(res3$adsl))
  expect_equal(res1$adsl[names(res3$adsl)], res3$adsl)
})

test_that("two EX-impute variables execute cleanly side by side", {
  sources <- pilot_sources()
  spec <- read_spec_df(data.frame(
    dataset = rep("ADSL", 2),
    variable = c("TRTSDTM", "TRTEDTM"),
    label = "x", type = "datetime", origin = "Derived",
    derivation = c(
      "Earliest EXSTDTC among EX records with EXDOSE > 0, impute missing date parts to first",
      "Latest EXSTDTC among EX records with EXDOSE > 0, impute missing date parts to last"
    ),
    stringsAsFactors = FALSE
  ))
  ir <- classify_variables(spec, "ADSL", backend = "rules")
  expect_length(validate_ir(ir), 0)

  res1 <- execute_ir(ir, sources = sources)
  expect_identical(res1$status$status, rep("EXECUTED", 2))
  expect_true(any(!is.na(res1$adsl$TRTSDTM)))
  expect_true(any(!is.na(res1$adsl$TRTEDTM)))
  tmps <- grep("^EXST_.*DTM$", names(res1$env$ex), value = TRUE)
  expect_length(tmps, 2)

  res2 <- execute_ir(ir, sources = sources)
  expect_identical(names(res1$adsl), names(res2$adsl))
  expect_equal(res1$adsl, res2$adsl)
  res3 <- execute_ir(ir, sources = list(base = res1$adsl, ex = sources$ex))
  expect_identical(names(res1$adsl), names(res3$adsl))
  expect_equal(res1$adsl, res3$adsl)
})

test_that("full loop: execute_ir + mock_metacore closes the codelist_var branch", {
  skip_if_not_installed("metacore")
  skip_if_not_installed("metatools")
  sources <- pilot_sources()
  spec <- mock_spec_adsl()
  mc <- mock_metacore(spec, codelists = list(RACE = codelist_from_data("RACE", sources$base)))
  ir <- classify_variables(spec, "ADSL", backend = "rules")

  res <- execute_ir(ir, sources = c(sources, list(mc = mc)))
  st <- stats::setNames(res$status$status, res$status$variable)
  expect_identical(unname(st[["RACEN"]]), "EXECUTED")
  expect_true("RACEN" %in% names(res$adsl))
  expect_true(all(!is.na(res$adsl$RACEN)))

  res2 <- execute_ir(ir, sources = c(sources, list(mc = mc)))
  expect_equal(res$adsl, res2$adsl)
})
