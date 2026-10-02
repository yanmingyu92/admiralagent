# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- HEIGHTBL | step 1/1: merge_var ----
# Spec origin: "VSSTRESN when VS.VSTESTCD='HEIGHT' and VS.VISITNUM=1"
# Agent rationale: Pull VSSTRESN from vs where VSTESTCD='HEIGHT' and VISITNUM=1; merged into ADSL by STUDYID/USUBJID.
# Confidence: 0.75
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  admiral::derive_vars_merged(
    dataset_add = vs,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(VSSTRESN),
    mode = "first",
    new_vars = exprs(HEIGHTBL = VSSTRESN),
    filter_add = VSTESTCD == 'HEIGHT' & VISITNUM == 1
  )
