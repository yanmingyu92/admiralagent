synth <- function() data.frame(
  STUDYID = "A",
  USUBJID = c("S1", "S1", "S2"),
  AGE = c(64, NA, 45),
  ABLFL = c("", "", "Y"),
  stringsAsFactors = FALSE
)

test_that("not_all_na distinguishes pass and fail", {
  ck <- aa_checks()$not_all_na
  expect_identical(ck$fn(synth(), "AGE", list()), "PASS")
  expect_identical(ck$fn(synth(), "NOPE", list()), "FAIL: variable not present")
  allna <- synth(); allna$AGE <- NA_real_
  expect_identical(ck$fn(allna, "AGE", list()), "FAIL: all values missing")
})

test_that("key_uniqueness detects duplicated keys and respects by_vars", {
  ck <- aa_checks()$key_uniqueness
  expect_identical(ck$fn(synth(), "AGE", list(by_vars = "USUBJID")),
                   "FAIL: 1 duplicated key rows")
  expect_identical(ck$fn(synth(), "AGE", list(by_vars = c("STUDYID", "USUBJID"))),
                   "FAIL: 1 duplicated key rows")
  uniq <- synth()[!duplicated(synth()$USUBJID), ]
  expect_identical(ck$fn(uniq, "AGE", list(by_vars = "USUBJID")), "PASS")
  expect_identical(ck$fn(synth(), "AGE", list(by_vars = "MISSING")), "MANUAL: keys not found in data")
})

test_that("non_negative flags negative durations", {
  ck <- aa_checks()$non_negative
  neg <- synth(); neg$AGE[1] <- -3
  expect_identical(ck$fn(neg, "AGE", list()), "FAIL: negative values present")
  expect_identical(ck$fn(synth(), "AGE", list()), "PASS")
})

test_that("flag_rate fails when a flag is never set", {
  ck <- aa_checks()$flag_rate
  expect_identical(ck$fn(synth(), "ABLFL", list()), "PASS")
  never <- synth(); never$ABLFL <- ""
  expect_identical(ck$fn(never, "ABLFL", list()), "FAIL: flag never set")
})

test_that("imputation_flag points at the source-dataset prefix", {
  ck <- aa_checks()$imputation_flag
  res <- ck$fn(synth(), "TRTSDTM", list(target = "EXSTDTM"))
  expect_true(grepl("EXSTDTF/EXSTTMF", res))
  expect_true(startsWith(res, "MANUAL"))
  with_flag <- synth(); with_flag$EXSTDTF <- NA_character_
  expect_identical(ck$fn(with_flag, "TRTSDTM", list(target = "EXSTDTM")), "PASS")
})

test_that("values_in_ct is always manual", {
  expect_identical(aa_checks()$values_in_ct$fn(synth(), "RACEN", list()),
                   "MANUAL: compare against spec codelist")
})

test_that("run_validation tolerates a failing check function", {
  ir <- list(new_variable_ir("ADSL", "AGE", list(
    new_step("duration", list(target = "AGE", start = "BRTHDT", end = "TRTSDT",
                              out_unit = "years"))
  )))
  res <- run_validation(data.frame(X = 1), ir, quiet = TRUE)
  expect_identical(nrow(res), 2L)
  expect_true(all(res$status %in% c("FAIL", "MANUAL")))
})
