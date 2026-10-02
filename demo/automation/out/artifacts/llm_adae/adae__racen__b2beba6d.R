# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RACEN | step 1/1: merge_var ----
# Spec origin: "ADSL.RACEN"
# Agent rationale: Numeric race is pulled from ADSL.RACEN via a subject-level merge keyed on USUBJID.
# Confidence: 0.80
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADAE <- ADAE |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(USUBJID),
    mode = "first",
    new_vars = exprs(RACEN = RACEN)
  )
