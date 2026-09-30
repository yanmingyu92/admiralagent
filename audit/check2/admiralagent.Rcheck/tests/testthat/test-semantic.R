test_that("new_step unlists vector args and drops empty ones", {
  s <- new_step("merge_var", list(
    target = "TRTSDTM", by_vars = list("STUDYID", "USUBJID"),
    order = list(), mode = "first"
  ))
  expect_identical(s$args$by_vars, c("STUDYID", "USUBJID"))
  expect_null(s$args$order)
  expect_identical(s$args$mode, "first")
})

test_that("assign from BDS artifacts is rejected", {
  ir <- list(new_variable_ir("ADSL", "BMIBL", list(
    new_step("compute_param", list(
      paramcd = "BMI", param = "BMI", parameters = c("WEIGHT", "HEIGHT"),
      formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
      by_vars = c("STUDYID", "USUBJID"), on = "vs"
    )),
    new_step("assign", list(target = "BMIBL", from = "AVAL"))
  )))
  probs <- validate_ir(ir)
  expect_true(any(grepl("BDS artifact.*merge_var", probs)))
})

test_that("variables whose steps never land in the target dataset are rejected", {
  incomplete <- list(new_variable_ir("ADSL", "BMIBL", list(
    new_step("compute_param", list(
      paramcd = "BMI", param = "BMI", parameters = c("WEIGHT", "HEIGHT"),
      formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
      by_vars = c("STUDYID", "USUBJID"), on = "vs"
    ))
  )))
  probs <- validate_ir(incomplete)
  expect_true(any(grepl("never land|foreign datasets", probs)))

  complete <- list(new_variable_ir("ADSL", "BMIBL", list(
    new_step("compute_param", list(
      paramcd = "BMI", param = "BMI", parameters = c("WEIGHT", "HEIGHT"),
      formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
      by_vars = c("STUDYID", "USUBJID"), on = "vs"
    )),
    new_step("merge_var", list(
      target = "BMIBL", source = "AVAL", dataset_add = "vs",
      by_vars = c("STUDYID", "USUBJID"), order = "AVAL", mode = "first",
      filter = "PARAMCD == 'BMI'"
    ))
  )))
  expect_length(validate_ir(complete), 0)
})

test_that("non-character vector args are rejected", {
  ir <- list(new_variable_ir("ADSL", "TRTSDTM", list(
    new_step("merge_var", list(
      target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
      by_vars = c("STUDYID", "USUBJID"), mode = "first"
    ))
  )))
  ir[[1]]$steps[[1]]$args$by_vars <- list("STUDYID", "USUBJID", 1L)
  expect_true(any(grepl("must be a character vector", validate_ir(ir))))
})

test_that("merge without order emits a nondeterminism CHECK comment", {
  ir <- list(new_variable_ir("ADSL", "BMIBL", list(
    new_step("merge_var", list(
      target = "BMIBL", source = "AVAL", dataset_add = "vs",
      by_vars = c("STUDYID", "USUBJID"), mode = "first",
      filter = "PARAMCD == 'BMI'"
    ))
  )))
  out <- render_variable(ir[[1]])
  expect_true(grepl("no `order` specified", out, fixed = TRUE))

  ordered <- list(new_variable_ir("ADSL", "BMIBL", list(
    new_step("merge_var", list(
      target = "BMIBL", source = "AVAL", dataset_add = "vs",
      by_vars = c("STUDYID", "USUBJID"), order = "AVAL", mode = "first",
      filter = "PARAMCD == 'BMI'"
    ))
  )))
  expect_false(grepl("no `order` specified", render_variable(ordered[[1]]), fixed = TRUE))
})
