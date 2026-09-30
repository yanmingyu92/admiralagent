# BDS (ADVS) + ADTTE extension -------------------------------------------------
#
# Oracle verification against pharmaverseadam::advs (CDISC pilot).
# Glue (allowed in tests, not in generated code): the minimal ADVS spec does
# not spec ADTM/TRTSDTM, so the test base precomputes them with admiral
# directly (ADTM from VSDTC, TRTSDTM merged from DM RFSTDTC-derived subjects).
# The base contains VS records only: PARAMCD/AVAL etc. are NOT pre-added
# because the spec derives them.

bds_pilot <- function() {
  skip_if_not_installed("admiral")
  skip_if_not_installed("pharmaversesdtm")
  skip_if_not_installed("pharmaverseadam")
  suppressMessages(library(pharmaversesdtm))
  suppressMessages(library(pharmaverseadam))
  e <- new.env(parent = globalenv())
  data("vs", envir = e)
  data("dm", envir = e)
  data("ae", envir = e)
  data("advs", package = "pharmaverseadam", envir = e)
  e
}

build_advs_sources <- function(e) {
  trts <- e$dm |>
    admiral::derive_vars_dtm(
      new_vars_prefix = "TRTS", dtc = RFSTDTC,
      highest_imputation = "M", date_imputation = "first"
    )
  trts <- unique(trts[, c("STUDYID", "USUBJID", "TRTSDTM")])
  base <- e$vs |>
    admiral::derive_vars_dtm(
      new_vars_prefix = "A", dtc = VSDTC,
      highest_imputation = "M", date_imputation = "first"
    ) |>
    admiral::derive_vars_merged(
      dataset_add = trts, by_vars = admiral::exprs(STUDYID, USUBJID),
      new_vars = admiral::exprs(TRTSDTM)
    )
  vslk <- unique(e$vs[, c("VSTESTCD", "VSTEST")])
  vslk$PARAMCD <- as.character(vslk$VSTESTCD)
  vslk$PARAM <- as.character(vslk$VSTEST)
  list(base = base, vslk = vslk)
}

build_adtte_base <- function(e) {
  trts <- e$dm |>
    admiral::derive_vars_dtm(
      new_vars_prefix = "TRTS", dtc = RFSTDTC,
      highest_imputation = "M", date_imputation = "first"
    )
  unique(trts[, c("STUDYID", "USUBJID", "TRTSDTM")])
}

test_that("rules backend classifies mock ADVS spec into expected BDS layers", {
  ir <- classify_variables(mock_spec_advs(), "ADVS", backend = "rules")
  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))

  expect_identical(by_var$USUBJID$steps[[1]]$layer, "assign")
  expect_identical(by_var$USUBJID$steps[[1]]$args$from, "USUBJID")

  expect_identical(by_var$PARAMCD$steps[[1]]$layer, "lookup_join")
  expect_identical(by_var$PARAMCD$steps[[1]]$args$dataset_lookup, "vslk")
  expect_identical(by_var$PARAMCD$steps[[1]]$args$by_vars, "VSTESTCD")
  expect_identical(by_var$PARAM$steps[[1]]$layer, "lookup_join")

  expect_identical(by_var$AVAL$steps[[1]]$layer, "assign")
  expect_identical(by_var$AVAL$steps[[1]]$args$from, "VSSTRESN")
  expect_identical(by_var$AVALU$steps[[1]]$args$from, "VSSTRESU")

  # AVISIT is an abstention case: the VISIT -> AVISIT mapping table is a
  # human decision, so the rules engine must not guess one
  expect_true(by_var$AVISIT$needs_human)

  abl <- by_var$ABLFL$steps[[1]]
  expect_identical(abl$layer, "extreme_flag")
  expect_identical(abl$args$by_vars, c("USUBJID", "PARAMCD"))
  expect_identical(abl$args$order, "ADTM")
  expect_identical(abl$args$mode, "last")
  expect_identical(abl$args$restrict_filter, "ADTM <= TRTSDTM")

  base_s <- by_var$BASE$steps[[1]]
  expect_identical(base_s$layer, "merge_var")
  # dataset_add is the target dataset object itself: execute_ir keeps the
  # evolving dataset under the uppercase target name, so a self-merge must
  # reference ADVS (a lowercase 'advs' binding would be a stale copy)
  expect_identical(base_s$args$dataset_add, "ADVS")
  expect_identical(base_s$args$by_vars, c("USUBJID", "PARAMCD"))
  expect_identical(base_s$args$filter, "ABLFL == 'Y'")
  expect_identical(base_s$args$source, "AVAL")

  expect_identical(by_var$CHG$steps[[1]]$layer, "compute_var")
  expect_identical(by_var$CHG$steps[[1]]$args$formula, "AVAL - BASE")
  expect_identical(by_var$PCHG$steps[[1]]$layer, "compute_var")
  expect_identical(by_var$PCHG$steps[[1]]$args$formula, "100 * AVAL / BASE - 100")

  # ANRIND: the rule parses the numeric breakpoints from the spec text into
  # a categorize cut. Deliberate limitation (documented): the cut applies to
  # the whole AVAL column; the spec text says "for SYSBP" but the categorize
  # layer has no parameter filter, so parameter-specific scoping is left to
  # human refinement. Reference ranges per parameter are study decisions.
  anr <- by_var$ANRIND$steps[[1]]
  expect_identical(anr$layer, "categorize")
  expect_identical(anr$args$from, "AVAL")
  expect_identical(anr$args$breaks, c(0, 90, 140, Inf))
  expect_identical(anr$args$labels, c("LOW", "NORMAL", "HIGH"))

  expect_length(validate_ir(ir), 0)
})

test_that("rules backend classifies mock ADTTE spec into impute + merge + duration chain", {
  ir <- classify_variables(mock_spec_adtte(), "ADTTE", backend = "rules")
  by_var <- stats::setNames(ir, vapply(ir, function(v) v$variable, character(1)))

  expect_true(by_var$CNSR$needs_human)

  tte <- by_var$TTE$steps
  expect_identical(vapply(tte, function(s) s$layer, character(1)),
                   c("impute_dtc", "merge_var", "duration"))
  tmp <- tte[[1]]$args$target
  expect_identical(tmp, temp_target("AESTDTC", "TTE", mode = "first"))
  expect_identical(tte[[1]]$args$on, "ae")
  expect_identical(tte[[1]]$args$dtc, "AESTDTC")
  expect_identical(tte[[2]]$args$dataset_add, "ae")
  expect_identical(tte[[2]]$args$source, tmp)
  expect_identical(tte[[3]]$args$start, "TRTSDTM")
  expect_identical(tte[[3]]$args$end, tmp)
  expect_identical(tte[[3]]$args$out_unit, "days")

  # admiral 1.5.0.9011 finding: derive_vars_duration accepts POSIXct *DTM
  # endpoints directly (verified empirically against the installed admiral),
  # so the chain needs NO dtm_to_dt conversion steps.
  expect_false(any(grepl("dtm_to_dt", vapply(tte, function(s) s$layer, character(1)))))
  expect_true(grepl("derive_vars_duration", render_variable(by_var$TTE), fixed = TRUE))

  expect_length(validate_ir(ir), 0)
})

test_that("compute_var validation rejects parentheses and non-syntactic tokens", {
  paren <- list(new_variable_ir("ADVS", "PCHG", list(new_step("compute_var", list(
    target = "PCHG", formula = "100 * (AVAL - BASE) / BASE"
  )))))
  probs <- validate_ir(paren)
  expect_true(any(grepl("use compute_param for parameter-record math", probs)))

  nonsyn <- list(new_variable_ir("ADVS", "X", list(new_step("compute_var", list(
    target = "X", formula = "1ST - BASE"
  )))))
  expect_true(any(grepl("syntactic", validate_ir(nonsyn))))

  ok <- list(new_variable_ir("ADVS", "PCHG", list(new_step("compute_var", list(
    target = "PCHG", formula = "100 * AVAL / BASE - 100"
  )))))
  expect_length(validate_ir(ok), 0)
})

test_that("ADVS IR executes on pilot VS data: ABLFL/BASE/CHG/PCHG consistent", {
  e <- bds_pilot()
  src <- build_advs_sources(e)
  ir <- classify_variables(mock_spec_advs(), "ADVS", backend = "rules")
  expect_length(validate_ir(ir), 0)

  res <- execute_ir(ir, sources = src)
  st <- stats::setNames(res$status$status, res$status$variable)
  expect_identical(
    unname(st[c("USUBJID", "PARAMCD", "PARAM", "AVAL", "AVALU",
                "ABLFL", "BASE", "CHG", "PCHG", "ANRIND")]),
    rep("EXECUTED", 10)
  )
  expect_identical(unname(st[["AVISIT"]]), "REVIEW")

  out <- res$adsl
  expect_true(any(out$ABLFL == "Y", na.rm = TRUE))
  flagged <- !is.na(out$ABLFL) & out$ABLFL == "Y"
  expect_true(any(!is.na(out$BASE[flagged])))

  nb <- !is.na(out$CHG) & !is.na(out$BASE) & !is.na(out$AVAL)
  expect_true(all(out$CHG[nb] == (out$AVAL - out$BASE)[nb]))

  np <- !is.na(out$PCHG) & !is.na(out$BASE) & out$BASE != 0
  expect_true(all(abs(out$PCHG[np] - (100 * (out$AVAL - out$BASE) / out$BASE)[np]) < 1e-9))

  res2 <- execute_ir(ir, sources = src)
  expect_setequal(names(out), names(res2$adsl))
})

test_that("ORACLE: generated ADVS agrees with pharmaverseadam::advs", {
  e <- bds_pilot()
  src <- build_advs_sources(e)
  ir <- classify_variables(mock_spec_advs(), "ADVS", backend = "rules")
  gen <- execute_ir(ir, sources = src)$adsl

  gk <- paste(gen$USUBJID, gen$PARAMCD, sep = "|")
  g1 <- gen[!duplicated(gk), c("USUBJID", "PARAMCD", "AVAL")]
  orc <- e$advs
  ok <- paste(orc$USUBJID, orc$PARAMCD, sep = "|")
  o1 <- orc[!duplicated(ok), c("USUBJID", "PARAMCD", "AVAL")]

  m <- merge(g1, o1, by = c("USUBJID", "PARAMCD"), suffixes = c(".g", ".o"))
  # generated groups are the 6 SDTM-origin parameters (DIABP HEIGHT PULSE
  # SYSBP TEMP WEIGHT); the oracle adds derived params BMI/BSA/MAP on top,
  # which are out of scope for this minimal spec
  expect_gte(nrow(m), 1000)
  both <- !is.na(m$AVAL.g) & !is.na(m$AVAL.o)
  expect_gte(mean(abs(m$AVAL.g[both] - m$AVAL.o[both]) < 0.01), 0.90)
  expect_true(all(c("WEIGHT", "HEIGHT", "SYSBP", "DIABP") %in% unique(m$PARAMCD)))
})

test_that("ADTTE chain executes on pilot AE data with POSIXct duration endpoints", {
  e <- bds_pilot()
  base <- build_adtte_base(e)
  ir <- classify_variables(mock_spec_adtte(), "ADTTE", backend = "rules")
  expect_length(validate_ir(ir), 0)

  res <- execute_ir(ir, sources = list(base = base, ae = e$ae))
  st <- stats::setNames(res$status$status, res$status$variable)
  expect_identical(unname(st[["TTE"]]), "EXECUTED")
  expect_identical(unname(st[["CNSR"]]), "REVIEW")

  adtte <- res$adsl
  expect_true("TTE" %in% names(adtte))
  expect_true(any(!is.na(adtte$TTE)))
  # subjects without any AE have no merged event date -> TTE NA (the CNSR=1
  # case; the censoring rule itself stays needs_human by design)
  expect_gt(sum(is.na(adtte$TTE)), 0)
})
