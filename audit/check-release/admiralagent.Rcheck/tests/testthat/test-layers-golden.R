GOLDEN_ARGS <- list(
  assign = list(target = "TRT01P", from = "ARM"),
  merge_var = list(target = "TRTSDTM", source = "EXSTDTM", dataset_add = "ex",
                   by_vars = c("STUDYID", "USUBJID"), order = "EXSTDTM", mode = "first"),
  lookup_join = list(target = "PARAMCD", source = "PARNCD", dataset_lookup = "lk",
                     by_vars = "VSTESTCD"),
  impute_dtc = list(target = "EXSTDTM", dtc = "EXSTDTC", output_class = "dtm",
                     highest_imputation = "M", date_imputation = "first"),
  dtm_to_dt = list(target = "TRTSDT", source = "TRTSDTM"),
  duration = list(target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years",
                   add_one = FALSE, trunc_out = TRUE),
  date_shift = list(target = "TRTEDT", source = "TRTSDT", days = 7),
  compute_param = list(paramcd = "BMI", param = "Body Mass Index",
                       parameters = c("WEIGHT", "HEIGHT"),
                       formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
                       by_vars = c("STUDYID", "USUBJID")),
  summary_record = list(paramcd = "AVERAGE", param = "Average", by_vars = "USUBJID",
                        summary_fun = "mean"),
  extreme_flag = list(target = "ABLFL", by_vars = "USUBJID", order = "ADT", mode = "last"),
  codelist_var = list(target = "RACEN", from = "RACE", decode_to_code = TRUE),
  obs_number = list(target = "ASEQ", by_vars = "USUBJID", order = "ADT"),
  categorize = list(target = "AGEGR1", from = "AGE", breaks = c(0, 18, 65, 200),
                    labels = c("<18", "18-64", ">=65")),
  compute_var = list(target = "CHG", formula = "AVAL - BASE")
)

GOLDEN_SIG <- c(
  assign = "dplyr::mutate(TRT01P = ARM)",
  merge_var = "new_vars = exprs(TRTSDTM = EXSTDTM)",
  lookup_join = "new_vars = exprs(PARAMCD = PARNCD)",
  impute_dtc = "new_vars_prefix = \"EXST\"",
  dtm_to_dt = "admiral::derive_vars_dtm_to_dt",
  duration = "derive_vars_duration",
  date_shift = "TRTEDT = as.Date(TRTSDT) + 7",
  compute_param = "AVAL = AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
  summary_record = "AVAL = mean(AVAL, na.rm = TRUE)",
  extreme_flag = "admiral::derive_var_extreme_flag",
  codelist_var = "metacore = mc",
  obs_number = "admiral::derive_var_obs_number",
  categorize = "breaks = c(0, 18, 65, 200)",
  compute_var = "CHG = AVAL - BASE"
)

test_that("every layer renders valid code for canonical args (golden)", {
  layers <- aa_layers()
  for (nm in layer_names()) {
    code <- layers[[nm]]$render(GOLDEN_ARGS[[nm]], "adsl")
    expect_true(is.character(code) && nzchar(code), info = nm)
    expect_true(grepl(GOLDEN_SIG[[nm]], code, fixed = TRUE), info = paste(nm, code))
  }
})

test_that("rendering is deterministic", {
  layers <- aa_layers()
  for (nm in layer_names()) {
    a <- layers[[nm]]$render(GOLDEN_ARGS[[nm]], "adsl")
    b <- layers[[nm]]$render(GOLDEN_ARGS[[nm]], "adsl")
    expect_identical(a, b, info = nm)
  }
})

test_that("assign layer errors without from or literal", {
  expect_error(aa_layers()$assign$render(list(target = "X"), "adsl"), "exactly one")
})

test_that("impute_dtc prefix strips DTM and DT suffixes", {
  dtm <- aa_layers()$impute_dtc$render(
    list(target = "EXSTDTM", dtc = "EXSTDTC", output_class = "dtm",
         highest_imputation = "M", date_imputation = "first"), "ex")
  expect_true(grepl("admiral::derive_vars_dtm", dtm, fixed = TRUE))
  dt <- aa_layers()$impute_dtc$render(
    list(target = "EXSTDT", dtc = "EXSTDTC", output_class = "dt",
         highest_imputation = "M", date_imputation = "first"), "ex")
  expect_true(grepl("admiral::derive_vars_dt", dt, fixed = TRUE))
})

test_that("extreme_flag wraps restrict_derivation when restrict_filter set", {
  args <- list(target = "ABLFL", by_vars = "USUBJID", order = "ADT", mode = "last",
               restrict_filter = "ADT <= TRTSDT")
  code <- aa_layers()$extreme_flag$render(args, "adsl")
  expect_true(grepl("admiral::restrict_derivation", code, fixed = TRUE))
  plain <- aa_layers()$extreme_flag$render(
    list(target = "ABLFL", by_vars = "USUBJID", order = "ADT", mode = "last"), "adsl")
  expect_false(grepl("restrict_derivation", plain, fixed = TRUE))
})
