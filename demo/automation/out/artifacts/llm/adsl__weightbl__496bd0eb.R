# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- WEIGHTBL | step 1/1: merge_var ----
# Spec origin: "VSSTRESN when VS.VSTESTCD='WEIGHT' and VS.VISITNUM=3"
# Agent rationale: Pull VSSTRESN from vs where VSTESTCD='WEIGHT' and VISITNUM=3; merged into ADSL by STUDYID/USUBJID.
# Confidence: 0.75
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  admiral::derive_vars_merged(
    dataset_add = vs,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(VSSTRESN),
    mode = "first",
    new_vars = exprs(WEIGHTBL = VSSTRESN),
    filter_add = VSTESTCD == 'WEIGHT' & VISITNUM == 3
  )
