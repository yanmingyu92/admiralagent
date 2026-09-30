make_ir <- function() classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")

test_that("dependency report flags undefined duration endpoints (AGE -> TRTSDT/BRTHDT)", {
  rep <- ir_dependency_report(make_ir(), known_columns = names(mock_spec_adsl()))
  age_inputs <- rep$input[rep$variable == "AGE"]
  expect_true("TRTSDT" %in% age_inputs)
  expect_true("BRTHDT" %in% age_inputs)
})

test_that("dependency report whitelists known base columns (ARM from dm)", {
  rep_bare <- ir_dependency_report(make_ir())
  expect_true("ARM" %in% rep_bare$input[rep_bare$variable == "TRT01P"])
  rep_dm <- ir_dependency_report(make_ir(), known_columns = c("ARM", "BRTHDTC"))
  expect_false("ARM" %in% rep_dm$input)
})

test_that("dependency report includes source and imputation inputs", {
  rep <- ir_dependency_report(make_ir(), known_columns = c("ARM"))
  flagged <- rep$input[rep$variable %in% c("TRTSDTM", "TRTEDTM", "BMIBL", "RACEN")]
  expect_true("RFSTDTC" %in% flagged)
  expect_true("RACE" %in% flagged)
})

test_that("dependency report flags foreign-dataset targets used on the target dataset", {
  ir <- list(new_variable_ir("ADSL", "X", list(
    new_step("impute_dtc", list(
      target = "EXSTDTM", dtc = "EXSTDTC", output_class = "dtm",
      highest_imputation = "M", date_imputation = "first", on = "ex"
    )),
    new_step("duration", list(target = "TRTDUR", start = "EXSTDTM", end = "TRTEDTM",
                              out_unit = "days"))
  )))
  rep <- ir_dependency_report(ir)
  expect_true("EXSTDTM" %in% rep$input)
  expect_identical(rep$dataset[rep$input == "EXSTDTM"], "ADSL")
  expect_true("TRTEDTM" %in% rep$input)
})

test_that("same-dataset step targets satisfy dependencies without flags", {
  ir <- list(new_variable_ir("ADSL", "X", list(
    new_step("impute_dtc", list(
      target = "BRTHDT", dtc = "BRTHDTC", output_class = "dt",
      highest_imputation = "M", date_imputation = "first"
    )),
    new_step("impute_dtc", list(
      target = "TRTSDT", dtc = "TRTSDTC", output_class = "dt",
      highest_imputation = "M", date_imputation = "first"
    )),
    new_step("duration", list(target = "AGE", start = "BRTHDT", end = "TRTSDT",
                              out_unit = "years"))
  )))
  rep <- ir_dependency_report(ir, known_columns = c("BRTHDTC", "TRTSDTC"))
  expect_equal(nrow(rep), 0)
})

test_that("needs_human variables are skipped by the report", {
  rep <- ir_dependency_report(make_ir())
  expect_false("AGEGR1" %in% rep$variable)
})

test_that("compute_param without `on` requires BDS columns in the target dataset", {
  on_adsl <- list(new_variable_ir("ADSL", "BMIBL", list(
    new_step("compute_param", list(
      paramcd = "BMI", param = "BMI", parameters = c("WEIGHT", "HEIGHT"),
      formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
      by_vars = c("STUDYID", "USUBJID")
    ))
  )))
  rep <- ir_dependency_report(on_adsl, known_columns = c("STUDYID", "USUBJID"))
  expect_true("PARAMCD" %in% rep$input)
  expect_true("AVAL" %in% rep$input)

  on_vs <- list(new_variable_ir("ADVS", "BMI", list(
    new_step("compute_param", list(
      paramcd = "BMI", param = "BMI", parameters = c("WEIGHT", "HEIGHT"),
      formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
      by_vars = c("STUDYID", "USUBJID")
    ))
  )))
  rep_bds <- ir_dependency_report(on_vs, known_columns = c("STUDYID", "USUBJID", "PARAMCD", "AVAL", "WEIGHT", "HEIGHT"))
  expect_equal(nrow(rep_bds), 0)

  foreign <- list(new_variable_ir("ADSL", "BMIBL", list(
    new_step("compute_param", list(
      paramcd = "BMI", param = "BMI", parameters = c("WEIGHT", "HEIGHT"),
      formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
      by_vars = c("STUDYID", "USUBJID"), on = "vs"
    ))
  )))
  rep_f <- ir_dependency_report(foreign)
  expect_true(all(c("PARAMCD", "AVAL", "WEIGHT", "HEIGHT") %in% rep_f$input))
})

test_that("empty report has correct shape", {
  ir <- list(new_variable_ir("ADSL", "X", list(
    new_step("impute_dtc", list(
      target = "BRTHDT", dtc = "BRTHDTC", output_class = "dt",
      highest_imputation = "M", date_imputation = "first"
    )),
    new_step("impute_dtc", list(
      target = "TRTSDT", dtc = "TRTSDTC", output_class = "dt",
      highest_imputation = "M", date_imputation = "first"
    )),
    new_step("duration", list(target = "AGE", start = "BRTHDT", end = "TRTSDT",
                              out_unit = "years"))
  )))
  rep <- ir_dependency_report(ir, known_columns = c("BRTHDTC", "TRTSDTC"))
  expect_equal(nrow(rep), 0)
  expect_named(rep, c("variable", "input", "dataset", "issue"))
})
