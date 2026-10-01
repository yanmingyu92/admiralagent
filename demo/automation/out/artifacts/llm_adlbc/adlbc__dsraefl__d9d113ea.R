# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- DSRAEFL | step 1/1: merge_var ----
# Spec origin: "Copied directly from ADSL.DSR01AEFL"
# Agent rationale: DSRAEFL is copied from ADSL.DSR01AEFL under a new name; the source name differs and is not in the base dataset, so merge_var pulls it from adsl keyed on STUDYID and USUBJID.
# Confidence: 0.80
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADLBC <- ADLBC |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first",
    new_vars = exprs(DSRAEFL = DSR01AEFL)
  )
