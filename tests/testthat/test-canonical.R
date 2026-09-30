aa_duration <- function(...) {
  args <- c(list(target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years"), list(...))
  new_variable_ir("ADSL", "AGE", list(new_step("duration", args)))
}

aa_merge <- function(...) {
  args <- utils::modifyList(
    list(target = "BMIBL", source = "AVAL", dataset_add = "vs",
         by_vars = c("STUDYID", "USUBJID"), order = "AVAL", mode = "first",
         filter = "PARAMCD == 'BMI'"),
    list(...)
  )
  new_variable_ir("ADSL", "BMIBL", list(new_step("merge_var", args)))
}

# The rules engine mints a private temp column per consuming variable
# (temp_target()); an LLM writes the bare stem. Same derivation either way.
aa_impute_chain <- function(temp) {
  new_variable_ir("ADSL", "TRTSDTM", list(
    new_step("impute_dtc", list(
      target = temp, dtc = "EXSTDTC", output_class = "dtm",
      highest_imputation = "M", date_imputation = "first", on = "ex"
    )),
    new_step("merge_var", list(
      target = "TRTSDTM", source = temp, dataset_add = "ex",
      by_vars = c("STUDYID", "USUBJID"), order = "EXSTDTC", mode = "first",
      filter = "EXDOSE > 0"
    ))
  ))
}

test_that("registry defaults make an omitted arg equal to the explicit one", {
  # duration$trunc_out defaults to TRUE for out_unit = "years"
  expect_identical(
    ir_fingerprint(aa_duration()),
    ir_fingerprint(aa_duration(add_one = FALSE, trunc_out = TRUE))
  )
  expect_false(identical(
    ir_fingerprint(aa_duration()),
    ir_fingerprint(aa_duration(trunc_out = FALSE))
  ))
})

test_that("applying defaults in the registry leaves rendered code unchanged", {
  out <- render_variable(aa_duration())
  expect_true(grepl("add_one = FALSE", out, fixed = TRUE))
  expect_true(grepl("trunc_out = TRUE", out, fixed = TRUE))
  expect_identical(out, render_variable(aa_duration(add_one = FALSE, trunc_out = TRUE)))
})

test_that("argument insertion order is not semantics", {
  a <- new_variable_ir("ADSL", "TRTSDTM", list(new_step("merge_var", list(
    target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
    by_vars = c("STUDYID", "USUBJID"), mode = "first"
  ))))
  b <- new_variable_ir("ADSL", "TRTSDTM", list(new_step("merge_var", list(
    mode = "first", by_vars = c("STUDYID", "USUBJID"), dataset_add = "ex",
    source = "EXSTDTM", target = "TRTSDTM"
  ))))
  expect_identical(ir_fingerprint(a), ir_fingerprint(b))
  expect_identical(artifact_hash(list(a)), artifact_hash(list(b)))
})

test_that("an absent `on` is the variable's own dataset", {
  implicit <- new_variable_ir("ADSL", "SITEID",
                              list(new_step("assign", list(target = "SITEID", from = "SITEID"))))
  explicit <- new_variable_ir("ADSL", "SITEID",
                              list(new_step("assign", list(target = "SITEID", from = "SITEID", on = "ADSL"))))
  expect_identical(ir_fingerprint(implicit), ir_fingerprint(explicit))
})

test_that("by_vars is a set but order is a sequence", {
  expect_identical(
    ir_fingerprint(aa_merge(by_vars = c("STUDYID", "USUBJID"), order = c("AVAL", "ADT"))),
    ir_fingerprint(aa_merge(by_vars = c("USUBJID", "STUDYID"), order = c("AVAL", "ADT")))
  )
  expect_false(identical(
    ir_fingerprint(aa_merge(order = c("AVAL", "ADT"))),
    ir_fingerprint(aa_merge(order = c("ADT", "AVAL")))
  ))
})

test_that("expression spacing and quote style are not semantics", {
  expect_identical(
    ir_fingerprint(aa_merge(filter = "PARAMCD=='BMI'")),
    ir_fingerprint(aa_merge(filter = 'PARAMCD == "BMI"'))
  )
  expect_false(identical(
    ir_fingerprint(aa_merge(filter = "PARAMCD == 'BMI'")),
    ir_fingerprint(aa_merge(filter = "PARAMCD == 'BSA'"))
  ))
})

test_that("privately named intermediates do not count as disagreement", {
  rules_style <- aa_impute_chain("EXST_TRTSDTM")
  llm_style <- aa_impute_chain("EXSTDTM")
  expect_length(validate_ir(list(rules_style)), 0)
  expect_length(validate_ir(list(llm_style)), 0)
  expect_identical(ir_fingerprint(rules_style), ir_fingerprint(llm_style))
})

test_that("alpha-renaming does not hide a real divergence", {
  a <- aa_impute_chain("EXSTDTM")
  b <- a
  b$steps[[1]]$args$date_imputation <- "last"
  expect_false(identical(ir_fingerprint(a), ir_fingerprint(b)))
  d <- a
  d$steps[[2]]$args$filter <- "EXDOSE >= 0"
  expect_false(identical(ir_fingerprint(a), ir_fingerprint(d)))
})

test_that("fingerprint levels separate shape from arguments", {
  first <- aa_merge(mode = "first")
  last <- aa_merge(mode = "last")
  expect_identical(ir_fingerprint(first, "layer_chain"), ir_fingerprint(last, "layer_chain"))
  expect_identical(ir_fingerprint(first, "abstention"), ir_fingerprint(last, "abstention"))
  expect_false(identical(ir_fingerprint(first, "full"), ir_fingerprint(last, "full")))
})

test_that("abstention is distinguishable from derivation", {
  abstain <- new_variable_ir("ADSL", "AGEGR1", list(), needs_human = TRUE,
                             rationale = "breakpoints require human decision")
  expect_false(identical(
    ir_fingerprint(abstain, "abstention"),
    ir_fingerprint(aa_duration(), "abstention")
  ))
})

test_that("provenance fields are not semantics", {
  a <- aa_merge()
  b <- a
  b$spec_origin <- "wholly different spec text"
  b$rationale <- "a different explanation"
  b$confidence <- 0.8
  expect_identical(ir_fingerprint(a), ir_fingerprint(b))
})

test_that("a sidecar round-trip is canonically identical", {
  v <- new_variable_ir("ADSL", "AGEGR1", list(new_step("categorize", list(
    target = "AGEGR1", from = "AGE", breaks = c(-Inf, 65, Inf),
    labels = c("<65", ">=65")
  ))))
  dir <- tempfile()
  dir.create(dir)
  paths <- write_artifact(list(v), dir)
  back <- read_artifact(file.path(dir, paths[2]))$ir[[1]]
  expect_identical(ir_fingerprint(v), ir_fingerprint(back))
})
