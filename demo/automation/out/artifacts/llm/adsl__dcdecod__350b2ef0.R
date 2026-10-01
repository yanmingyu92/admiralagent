# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- DCDECOD | step 1/1: merge_var ----
# Spec origin: "DS.DSDECOD where DSCAT='DISPOSITION EVENT'"
# Agent rationale: Pull DSDECOD from ds where DSCAT='DISPOSITION EVENT'.
# Confidence: 0.85
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADSL <- ADSL |>
  admiral::derive_vars_merged(
    dataset_add = ds,
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first",
    new_vars = exprs(DCDECOD = DSDECOD),
    filter_add = DSCAT == 'DISPOSITION EVENT'
  )
