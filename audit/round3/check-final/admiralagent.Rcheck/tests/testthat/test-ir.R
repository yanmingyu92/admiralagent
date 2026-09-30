test_that("valid IR passes the gate", {
  ir <- list(new_variable_ir(
    dataset = "ADSL", variable = "TRTSDTM",
    steps = list(
      new_step("merge_var", list(
        target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
        by_vars = c("STUDYID", "USUBJID"), order = "EXSTDTM", mode = "first"
      ))
    ),
    spec_origin = "first dose date"
  ))
  expect_true(is_valid_ir(ir))
  expect_length(validate_ir(ir), 0)
})

test_that("unknown layers are rejected", {
  ir <- list(new_variable_ir(
    dataset = "ADSL", variable = "X",
    steps = list(new_step("magic_layer", list(target = "X")))
  ))
  expect_false(is_valid_ir(ir))
  expect_true(any(grepl("unknown layer", validate_ir(ir))))
})

test_that("missing required args are rejected", {
  ir <- list(new_variable_ir(
    dataset = "ADSL", variable = "TRTSDTM",
    steps = list(new_step("merge_var", list(target = "TRTSDTM")))
  ))
  expect_true(any(grepl("missing required arg", validate_ir(ir))))
})

test_that("assign requires exactly one of from/literal", {
  both <- list(new_variable_ir("ADSL", "X", list(new_step("assign", list(
    target = "X", from = "Y", literal = "Z"
  )))))
  expect_true(any(grepl("exactly one", validate_ir(both))))

  neither <- list(new_variable_ir("ADSL", "X", list(new_step("assign", list(
    target = "X"
  )))))
  expect_true(any(grepl("exactly one", validate_ir(neither))))
})

test_that("compute_param formula is whitelisted to parameters", {
  bad <- list(new_variable_ir("ADSL", "BMIBL", list(new_step("compute_param", list(
    paramcd = "BMI", param = "Body Mass Index", parameters = c("WEIGHT", "HEIGHT"),
    formula = "AVAL.WEIGHT / (AVAL.HTCM / 100)^2", by_vars = "USUBJID"
  )))))
  expect_true(any(grepl("formula uses tokens", validate_ir(bad))))

  good <- list(new_variable_ir("ADVS", "BMI", list(new_step("compute_param", list(
    paramcd = "BMI", param = "Body Mass Index", parameters = c("WEIGHT", "HEIGHT"),
    formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2", by_vars = "USUBJID"
  )))))
  expect_length(validate_ir(good), 0)
})

test_that("enum args are enforced", {
  ir <- list(new_variable_ir("ADSL", "AGE", list(new_step("duration", list(
    target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "fortnights"
  )))))
  expect_true(any(grepl("out_unit", validate_ir(ir))))
})

test_that("needs_human variables skip step validation", {
  ir <- list(new_variable_ir(
    dataset = "ADSL", variable = "AGEGR1", steps = list(),
    needs_human = TRUE, rationale = "breakpoints"
  ))
  expect_length(validate_ir(ir), 0)
})
