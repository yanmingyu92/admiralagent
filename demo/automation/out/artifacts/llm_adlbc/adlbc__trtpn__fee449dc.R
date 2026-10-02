# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTPN | step 1/1: merge_var ----
# Spec origin: "ADSL.TRT01PN"
# Agent rationale: TRTPN pulls ADSL.TRT01PN into ADLBC via a merge keyed on USUBJID.
# Confidence: 0.90
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADLBC <- ADLBC |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(USUBJID),
    mode = "first",
    new_vars = exprs(TRTPN = TRT01PN)
  )
