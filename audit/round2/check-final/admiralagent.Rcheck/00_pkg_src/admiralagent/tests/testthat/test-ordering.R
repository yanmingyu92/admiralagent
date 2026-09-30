var_names <- function(ir) vapply(ir, function(v) v$variable, character(1))

test_that("same-dataset consumer is placed after its producer", {
  ir_in <- list(
    new_variable_ir("ADSL", "TRTDUR", list(
      new_step("duration", list(target = "TRTDUR", start = "TRTSDT", end = "TRTEDT",
                                out_unit = "days"))
    )),
    new_variable_ir("ADSL", "TRTSDT", list(
      new_step("impute_dtc", list(target = "TRTSDT", dtc = "TRTSDTC", output_class = "dt",
                                  highest_imputation = "M", date_imputation = "first"))
    ))
  )
  out <- order_variables(ir_in)
  expect_identical(var_names(out), c("TRTSDT", "TRTDUR"))
})

test_that("dependency overrides layer rank when the consumer would rank earlier", {
  trtsdt <- new_variable_ir("ADSL", "TRTSDT", list(
    new_step("impute_dtc", list(target = "TRTSDT", dtc = "TRTSDTC", output_class = "dt",
                                highest_imputation = "M", date_imputation = "first"))
  ))
  consumer <- new_variable_ir("ADSL", "AVISITN", list(
    new_step("merge_var", list(target = "AVISITN", source = "AVAL", dataset_add = "vs",
                               by_vars = c("STUDYID", "USUBJID"), mode = "first")),
    new_step("duration", list(target = "AVDUR", start = "TRTSDT", end = "TRTEDT",
                              out_unit = "days"))
  ))
  ir_in <- list(consumer, trtsdt)
  naive <- order(vapply(ir_in, step_rank, numeric(1)), seq_along(ir_in))
  expect_identical(naive, c(1L, 2L))
  out <- order_variables(ir_in)
  expect_identical(var_names(out), c("TRTSDT", "AVISITN"))
})

test_that("foreign-dataset producer orders before merge_var consumer of its target", {
  ir_in <- list(
    new_variable_ir("ADSL", "TRTSDTM", list(
      new_step("merge_var", list(target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
                                 by_vars = c("STUDYID", "USUBJID"), order = "EXSTDTM",
                                 mode = "first"))
    )),
    new_variable_ir("ADSL", "EXDTM", list(
      new_step("impute_dtc", list(on = "ex", target = "EXSTDTM", dtc = "EXSTDTC",
                                  output_class = "dtm", highest_imputation = "M",
                                  date_imputation = "first"))
    ))
  )
  naive <- order(vapply(ir_in, step_rank, numeric(1)), seq_along(ir_in))
  expect_identical(naive, c(1L, 2L))
  out <- order_variables(ir_in)
  expect_identical(var_names(out), c("EXDTM", "TRTSDTM"))
})

test_that("independent variables of equal rank keep original spec order", {
  ir_in <- list(
    new_variable_ir("ADSL", "ZZ", list(new_step("assign", list(target = "ZZ", from = "ZZSRC")))),
    new_variable_ir("ADSL", "AA", list(new_step("assign", list(target = "AA", from = "AASRC")))),
    new_variable_ir("ADSL", "MM", list(new_step("assign", list(target = "MM", from = "MMSRC"))))
  )
  out <- order_variables(ir_in)
  expect_identical(var_names(out), c("ZZ", "AA", "MM"))
})

test_that("cycles fall back gracefully to a valid permutation without error", {
  ir_in <- list(
    new_variable_ir("ADSL", "A", list(
      new_step("impute_dtc", list(target = "ADT", dtc = "ADTC", output_class = "dt",
                                  highest_imputation = "M", date_imputation = "first")),
      new_step("duration", list(target = "DURA", start = "BDT", end = "ADT",
                                out_unit = "days"))
    )),
    new_variable_ir("ADSL", "B", list(
      new_step("impute_dtc", list(target = "BDT", dtc = "BDTC", output_class = "dt",
                                  highest_imputation = "M", date_imputation = "first")),
      new_step("duration", list(target = "DURB", start = "ADT", end = "BDT",
                                out_unit = "days"))
    )),
    new_variable_ir("ADSL", "DOWN", list(
      new_step("duration", list(target = "DOWNDUR", start = "ADT", end = "BDT",
                                out_unit = "days"))
    )),
    new_variable_ir("ADSL", "PLAIN", list(
      new_step("assign", list(target = "PLAIN", literal = "1"))
    ))
  )
  out <- order_variables(ir_in)
  expect_length(out, 4L)
  expect_setequal(var_names(out), c("A", "B", "DOWN", "PLAIN"))
  nm_out <- var_names(out)
  expect_gt(match("DOWN", nm_out), match("A", nm_out))
  expect_gt(match("DOWN", nm_out), match("B", nm_out))
  expect_identical(var_names(out), var_names(order_variables(ir_in)))
})

test_that("render_program emits the producer block before the consumer block", {
  ir_in <- list(
    new_variable_ir("ADSL", "TRTSDTM", list(
      new_step("merge_var", list(target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
                                 by_vars = c("STUDYID", "USUBJID"), order = "EXSTDTM",
                                 mode = "first"))
    )),
    new_variable_ir("ADSL", "EXSTDTM", list(
      new_step("impute_dtc", list(on = "ex", target = "EXSTDTM", dtc = "EXSTDTC",
                                  output_class = "dtm", highest_imputation = "M",
                                  date_imputation = "first"))
    ))
  )
  naive <- order(vapply(ir_in, step_rank, numeric(1)), seq_along(ir_in))
  expect_identical(naive, c(1L, 2L))
  # Foreign-only intermediate IR must not bypass the public rendering gate.
  expect_error(render_program(ir_in), "foreign datasets")
  ir_in[[2]]$dataset <- "EX"
  ir_in[[2]]$steps[[1]]$args$on <- NULL
  ir_in[[1]]$steps[[1]]$args$dataset_add <- "EX"
  prog <- render_program(ir_in)
  expect_lt(
    regexpr("# ---- EXSTDTM | step", prog, fixed = TRUE),
    regexpr("# ---- TRTSDTM | step", prog, fixed = TRUE)
  )
})

test_that("mock spec orders deterministically and respects key producers", {
  ir1 <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  o1 <- order_variables(ir1)
  o2 <- order_variables(ir1)
  expect_identical(var_names(o1), var_names(o2))
  expect_identical(var_names(o1), c("TRTSDTM", "TRTEDTM", "AGE", "RACEN", "STUDYID",
                                    "USUBJID", "BMIBL", "SUBJID", "TRT01P", "AGEGR1"))
  expect_identical(render_program(ir1), render_program(ir1))
})

test_that("render_program smoke on mock spec keeps the disclaimer", {
  ir1 <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  prog <- render_program(ir1)
  expect_true(grepl("DISCLAIMER: DRAFT CODE", prog, fixed = TRUE))
  expect_true(grepl("library(admiral)", prog, fixed = TRUE))
})
