# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTAN | step 1/1: merge_var ----
# Spec origin: "ADSL.TRT01AN"
# Agent rationale: Pull actual treatment number from ADSL into ADLBC.
# Confidence: 0.95
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADLBC <- ADLBC |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first",
    new_vars = exprs(TRTAN = TRT01AN)
  )
