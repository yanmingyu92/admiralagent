test_that("rules backend classifies mock ADSL spec into expected layers", {
  spec <- mock_spec_adsl()
  ir <- classify_variables(spec, "ADSL", backend = "rules")
  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))

  expect_identical(
    vapply(by_var$TRTSDTM$steps, function(s) s$layer, character(1)),
    "impute_dtc"
  )
  expect_identical(by_var$TRTSDTM$steps[[1]]$args$dtc, "RFSTDTC")
  expect_identical(
    vapply(by_var$TRTEDTM$steps, function(s) s$layer, character(1)),
    "impute_dtc"
  )
  expect_identical(by_var$TRTEDTM$steps[[1]]$args$dtc, "RFENDTC")
  expect_identical(by_var$AGE$steps[[1]]$layer, "duration")
  expect_identical(by_var$RACEN$steps[[1]]$layer, "codelist_var")
  expect_identical(by_var$STUDYID$steps[[1]]$layer, "assign")
  expect_identical(by_var$BMIBL$steps[[1]]$layer, "compute_param")
  expect_true(by_var$AGEGR1$needs_human)
})

test_that("rules backend output passes the IR gate", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_length(validate_ir(ir), 0)
})

ex_impute_spec <- function(variables = c("TRTSDTM", "TRTEDTM")) {
  derivations <- c(
    TRTSDTM = "Earliest EXSTDTC among EX records with EXDOSE > 0, impute missing date parts to first",
    TRTEDTM = "Latest EXSTDTC among EX records with EXDOSE > 0, impute missing date parts to last"
  )
  read_spec_df(data.frame(
    dataset = rep("ADSL", length(variables)),
    variable = variables,
    label = "x",
    type = "datetime",
    origin = "Derived",
    derivation = unname(derivations[variables]),
    stringsAsFactors = FALSE
  ))
}

test_that("two EX-impute variables get distinct per-variable temp targets", {
  ir <- classify_variables(ex_impute_spec(), "ADSL", backend = "rules")
  expect_length(validate_ir(ir), 0)

  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))
  tmp_first <- by_var$TRTSDTM$steps[[1]]$args$target
  tmp_last <- by_var$TRTEDTM$steps[[1]]$args$target

  expect_identical(tmp_first, temp_target("EXSTDTC", "TRTSDTM"))
  expect_identical(tmp_last, temp_target("EXSTDTC", "TRTEDTM"))
  expect_false(identical(tmp_first, tmp_last))
  expect_false(tmp_first %in% c("EXSTDTM", "EXSTDT"))
  expect_false(tmp_last %in% c("EXSTDTM", "EXSTDT"))
  expect_true(grepl("DTM$", tmp_first))
  expect_true(grepl("DTM$", tmp_last))

  expect_identical(by_var$TRTSDTM$steps[[2]]$args$source, tmp_first)
  expect_identical(by_var$TRTSDTM$steps[[2]]$args$order, tmp_first)
  expect_identical(by_var$TRTEDTM$steps[[2]]$args$source, tmp_last)
  expect_identical(by_var$TRTEDTM$steps[[2]]$args$order, tmp_last)

  prog <- render_program(ir)
  expect_true(grepl(tmp_first, prog, fixed = TRUE))
  expect_true(grepl(tmp_last, prog, fixed = TRUE))
  expect_false(grepl("EXSTDTM = EXSTDTM", prog, fixed = TRUE))
})

test_that("single-use EX temp still gets the suffixed name", {
  ir <- classify_variables(ex_impute_spec("TRTSDTM"), "ADSL", backend = "rules")
  expect_length(validate_ir(ir), 0)
  tmp <- ir[[1]]$steps[[1]]$args$target
  expect_identical(tmp, temp_target("EXSTDTC", "TRTSDTM"))
  expect_identical(ir[[1]]$steps[[2]]$args$source, tmp)
  expect_identical(ir[[1]]$steps[[2]]$args$order, tmp)
})

test_that("mock spec exercises the DM impute branch, not the EX branch", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))
  expect_null(by_var$TRTSDTM$steps[[1]]$args$on)
  expect_identical(by_var$TRTSDTM$steps[[1]]$args$dtc, "RFSTDTC")
  expect_identical(length(by_var$TRTSDTM$steps), 1L)
})

test_that("build_context is schema-only", {
  ctx <- build_context(mock_spec_adsl())
  expect_named(ctx, c(
    "STUDYID", "USUBJID", "SUBJID", "TRT01P", "TRTSDTM",
    "TRTEDTM", "AGE", "AGEGR1", "RACEN", "BMIBL"
  ))
  expect_null(ctx$TRTSDTM$values)
})

test_that("system prompt embeds the closed vocabulary", {
  p <- build_system_prompt()
  for (nm in layer_names()) expect_true(grepl(nm, p, fixed = TRUE))
  expect_true(grepl("never invent", p))
  expect_true(grepl(paste(layer_names(), collapse = ", "), p, fixed = TRUE))
})
