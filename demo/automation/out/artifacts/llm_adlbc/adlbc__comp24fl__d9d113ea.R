# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- COMP24FL | step 1/1: merge_var ----
# Spec origin: "Copied directly from ADSL.COM01P24FL"
# Agent rationale: COMP24FL is copied from ADSL.COM01P24FL under a new name; since the source variable name differs from the target and is not in the base dataset, merge_var pulls it from adsl keyed on STUDYID and USUBJID.
# Confidence: 0.80
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADLBC <- ADLBC |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first",
    new_vars = exprs(COMP24FL = COM01P24FL)
  )
