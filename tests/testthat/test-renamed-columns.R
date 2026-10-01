# Regression tests for showcase finding F-01: a merge that renames a column
# (source != target) makes the old name unavailable on the target dataset, but
# validate_ir() used to accept later steps still referencing it. The gate now
# tracks rename evidence per dataset and reports the reference, naming the
# column the step should use instead.

# The verbatim F-01 chain from the pilot5 showcase: SVSTDTC is merged onto ADSL
# as TRTSDT, then impute_dtc still points at SVSTDTC on ADSL.
f01_ir <- function() {
  list(new_variable_ir("ADSL", "TRTSDT", list(
    new_step("merge_var", list(
      target = "TRTSDT", source = "SVSTDTC", dataset_add = "sv",
      by_vars = c("STUDYID", "USUBJID"), order = "SVSTDTC", mode = "first",
      filter = "VISITNUM == 3"
    )),
    new_step("impute_dtc", list(
      target = "TRTSDT", dtc = "SVSTDTC", output_class = "dt",
      highest_imputation = "D", date_imputation = "first"
    ))
  )))
}

test_that("F-01 chain is rejected by the gate, naming old and new column", {
  probs <- validate_ir(f01_ir())
  expect_true(any(grepl("SVSTDTC", probs, fixed = TRUE)))
  expect_true(any(grepl("brought that column in as 'TRTSDT'", probs, fixed = TRUE)))
  expect_false(is_valid_ir(f01_ir()))
})

test_that("referencing the NEW name after a renaming merge stays legal", {
  ir <- list(new_variable_ir("ADSL", "TRTSDT", list(
    new_step("merge_var", list(
      target = "TRTSDTC", source = "SVSTDTC", dataset_add = "sv",
      by_vars = c("STUDYID", "USUBJID"), order = "SVSTDTC", mode = "first",
      filter = "VISITNUM == 3"
    )),
    new_step("impute_dtc", list(
      target = "TRTSDT", dtc = "TRTSDTC", output_class = "dt",
      highest_imputation = "D", date_imputation = "first"
    ))
  )))
  expect_length(validate_ir(ir), 0)
})

test_that("same-name merge keeps the column referenceable under that name", {
  # The consensus backend's actual TRTSDT chain from the showcase.
  ir <- list(new_variable_ir("ADSL", "TRTSDT", list(
    new_step("merge_var", list(
      target = "SVSTDTC", source = "SVSTDTC", dataset_add = "sv",
      by_vars = c("STUDYID", "USUBJID"), order = "SVSTDTC", mode = "first",
      filter = "VISITNUM == 3"
    )),
    new_step("impute_dtc", list(
      target = "TRTSDT", dtc = "SVSTDTC", output_class = "dt",
      highest_imputation = "D", date_imputation = "first"
    ))
  )))
  expect_length(validate_ir(ir), 0)
})

test_that("self-merge does not rename the source column away", {
  ir <- list(new_variable_ir("ADSL", "TRTSDT", list(
    new_step("merge_var", list(
      target = "TRTSDTC", source = "SVSTDTC", dataset_add = "adsl",
      by_vars = c("STUDYID", "USUBJID"), order = "SVSTDTC", mode = "first"
    )),
    new_step("impute_dtc", list(
      target = "TRTSDT", dtc = "SVSTDTC", output_class = "dt",
      highest_imputation = "D", date_imputation = "first"
    ))
  )))
  expect_length(validate_ir(ir), 0)
})

test_that("the old name stays referenceable on the SOURCE dataset", {
  # merge renames SVSTDTC -> TRTSDTC on ADSL; a second merge from sv may still
  # read SVSTDTC from sv, and sv-side order/filter columns are unaffected.
  ir <- list(
    new_variable_ir("ADSL", "TRTSDT", list(
      new_step("merge_var", list(
        target = "TRTSDTC", source = "SVSTDTC", dataset_add = "sv",
        by_vars = c("STUDYID", "USUBJID"), order = "SVSTDTC", mode = "first",
        filter = "VISITNUM == 3"
      )),
      new_step("impute_dtc", list(
        target = "TRTSDT", dtc = "TRTSDTC", output_class = "dt",
        highest_imputation = "D", date_imputation = "first"
      ))
    )),
    new_variable_ir("ADSL", "TRTEDT", list(
      new_step("merge_var", list(
        target = "TRTEDTC", source = "SVSTDTC", dataset_add = "sv",
        by_vars = c("STUDYID", "USUBJID"), order = "SVSTDTC", mode = "last"
      )),
      new_step("impute_dtc", list(
        target = "TRTEDT", dtc = "TRTEDTC", output_class = "dt",
        highest_imputation = "D", date_imputation = "first"
      ))
    ))
  )
  expect_length(validate_ir(ir), 0)
})

test_that("cross-variable references to a renamed-away column are also gated", {
  ir <- list(
    new_variable_ir("ADSL", "TRTSDT", list(
      new_step("merge_var", list(
        target = "TRTSDT", source = "SVSTDTC", dataset_add = "sv",
        by_vars = c("STUDYID", "USUBJID"), order = "SVSTDTC", mode = "first"
      ))
    )),
    new_variable_ir("ADSL", "SVCOPY", list(
      new_step("assign", list(target = "SVCOPY", from = "SVSTDTC"))
    ))
  )
  probs <- validate_ir(ir)
  expect_true(any(grepl("\\[SVCOPY step 1\\].*SVSTDTC.*TRTSDT", probs)))
})

test_that("a column re-produced under its old name clears the rename evidence", {
  ir <- list(new_variable_ir("ADSL", "TRTSDT", list(
    new_step("merge_var", list(
      target = "TRTSDTC", source = "SVSTDTC", dataset_add = "sv",
      by_vars = c("STUDYID", "USUBJID"), mode = "first"
    )),
    new_step("merge_var", list(
      target = "SVSTDTC", source = "SVSTDTC", dataset_add = "sv",
      by_vars = c("STUDYID", "USUBJID"), mode = "first"
    )),
    new_step("impute_dtc", list(
      target = "TRTSDT", dtc = "SVSTDTC", output_class = "dt",
      highest_imputation = "D", date_imputation = "first"
    ))
  )))
  expect_length(validate_ir(ir), 0)
})

test_that("system prompt states the rename rule", {
  expect_true(grepl(
    "later steps MUST reference the new name",
    build_system_prompt(), fixed = TRUE
  ))
})
