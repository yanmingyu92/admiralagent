# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTEDT | step 1/1: merge_var ----
# Spec origin: "ADSL.TRTEDT"
# Agent rationale: TRTEDT is defined as ADSL.TRTEDT, a value from a different dataset than the ADAE base; merge_var brings TRTEDT in keyed on USUBJID.
# Confidence: 0.85
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADAE <- ADAE |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(USUBJID),
    mode = "first",
    new_vars = exprs(TRTEDT = TRTEDT)
  )
