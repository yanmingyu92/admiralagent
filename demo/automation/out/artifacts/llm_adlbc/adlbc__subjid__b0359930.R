# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SUBJID | step 1/1: merge_var ----
# Spec origin: "Copied directly from ADSL.SUBJID"
# Agent rationale: SUBJID copied from ADSL; cross-domain pull via USUBJID key.
# Confidence: 0.85
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADLBC <- ADLBC |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(USUBJID),
    mode = "first",
    new_vars = exprs(SUBJID = SUBJID)
  )
