# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- WEIGHTBL | step 1/1: merge_var ----
# Spec origin: "VSSTRESN when VS.VSTESTCD='WEIGHT' and VS.VISITNUM=3"
# Agent rationale: Pull VSSTRESN from vs where VSTESTCD='WEIGHT' and VISITNUM=3.
# Confidence: 0.85
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADSL <- ADSL |>
  admiral::derive_vars_merged(
    dataset_add = vs,
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first",
    new_vars = exprs(WEIGHTBL = VSSTRESN),
    filter_add = VSTESTCD == 'WEIGHT' & VISITNUM == 3
  )
