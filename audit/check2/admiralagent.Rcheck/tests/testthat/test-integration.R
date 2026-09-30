build_pilot_adsl <- function(env = new.env(parent = globalenv())) {
  skip_if_not_installed("pharmaversesdtm")
  skip_if_not_installed("pharmaverseadam")
  skip_if_not_installed("admiral")
  suppressMessages(library(pharmaversesdtm))
  suppressMessages(library(admiral))
  data("dm", envir = env); data("ex", envir = env); data("vs", envir = env)
  data("adsl", package = "pharmaverseadam", envir = env)

  spec <- mock_spec_adsl()
  ir <- classify_variables(spec, "ADSL", backend = "rules")
  expect_length(validate_ir(ir), 0)

  env$ADSL <- dm
  env$dm <- dm
  env$ex <- ex
  env$vs <- vs
  env$vs$AVAL <- vs$VSSTRESN
  env$vs$PARAMCD <- vs$VSTESTCD

  for (v in ir) {
    if (isTRUE(v$needs_human)) next
    try(eval(parse(text = render_variable(v)), envir = env), silent = TRUE)
  }
  ir
}

test_that("key columns and TRT01P match the published ADSL oracle exactly", {
  env <- new.env(parent = globalenv())
  build_pilot_adsl(env)
  m <- merge(env$ADSL[, c("USUBJID", "STUDYID", "TRT01P")],
             env$adsl[, c("USUBJID", "STUDYID", "TRT01P")], by = "USUBJID",
             suffixes = c(".g", ".o"))
  expect_gte(nrow(m), 250)
  expect_equal(mean(m$STUDYID.g == m$STUDYID.o), 1)
  expect_equal(mean(m$TRT01P.g == m$TRT01P.o), 1)
})

test_that("TRTSDTM from RFSTDTC matches the published oracle (>= 98%)", {
  env <- new.env(parent = globalenv())
  build_pilot_adsl(env)
  m <- merge(env$ADSL[, c("USUBJID", "TRTSDTM")],
             env$adsl[, c("USUBJID", "TRTSDTM")], by = "USUBJID",
             suffixes = c(".g", ".o"))
  a <- as.Date(m$TRTSDTM.g); b <- as.Date(m$TRTSDTM.o)
  expect_gte(mean(a == b, na.rm = TRUE), 0.98)
  expect_gte(mean(is.na(a) == is.na(b)), 0.98)
})

test_that("TRTEDTM from RFENDTC captures the dominant production rule", {
  env <- new.env(parent = globalenv())
  build_pilot_adsl(env)
  m <- merge(env$ADSL[, c("USUBJID", "TRTEDTM")],
             env$adsl[, c("USUBJID", "TRTEDTM")], by = "USUBJID",
             suffixes = c(".g", ".o"))
  a <- as.Date(m$TRTEDTM.g); b <- as.Date(m$TRTEDTM.o)
  expect_gte(mean(a == b, na.rm = TRUE), 0.4)
})

test_that("BMIBL (revised baseline) agrees with pilot1 within tolerance", {
  skip_if_not_installed("haven")
  p1_path <- file.path("..", "..", "..", "cdisc_data", "pilot1", "m5",
                       "datasets", "rconsortiumpilot1", "analysis", "adam",
                       "datasets", "adsl.xpt")
  if (!file.exists(p1_path)) skip("pilot1 adsl.xpt not cloned")
  env <- new.env(parent = globalenv())
  ir <- build_pilot_adsl(env)

  bmi_idx <- which(vapply(ir, function(x) x$variable == "BMIBL", logical(1)))
  ir2 <- ir
  ir2[[bmi_idx]]$steps[[1]]$args$filter <- "VISIT == 'SCREENING 1'"
  env$ADSL$BMIBL <- NULL
  keep <- is.na(env$vs$PARAMCD) | env$vs$PARAMCD != "BMI"
  env$vs <- env$vs[keep, ]
  eval(parse(text = render_variable(ir2[[bmi_idx]])), envir = env)

  p1 <- haven::read_xpt(p1_path)
  m <- merge(env$ADSL[, c("USUBJID", "BMIBL")], p1[, c("USUBJID", "BMIBL")],
             by = "USUBJID", suffixes = c(".g", ".o"))
  both <- !is.na(m$BMIBL.g) & !is.na(m$BMIBL.o)
  expect_gte(nrow(m), 200)
  expect_gte(mean(abs(m$BMIBL.g[both] - m$BMIBL.o[both]) < 0.5), 0.8)
})

test_that("read_define parses pilot1 define.xml into a usable spec", {
  skip_if_not_installed("metacore")
  d1 <- file.path("..", "..", "..", "cdisc_data", "pilot1", "m5",
                  "datasets", "rconsortiumpilot1", "analysis", "adam",
                  "datasets", "define.xml")
  if (!file.exists(d1)) skip("pilot1 define.xml not cloned")
  spec <- read_define(d1)
  expect_true(is.data.frame(spec))
  expect_true("ADSL" %in% spec$dataset)
  adsl_rows <- spec[spec$dataset == "ADSL", ]
  expect_gte(nrow(adsl_rows), 40)
})
