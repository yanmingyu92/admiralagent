# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- EDUCLVL | step 1/1: merge_var ----
# Spec origin: "SC.SCSTRESN where SC.SCTESTCD=EDLEVEL"
# Agent rationale: Pull SCSTRESN from sc where SCTESTCD='EDLEVEL'; merged into ADSL by STUDYID/USUBJID.
# Confidence: 0.75
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  admiral::derive_vars_merged(
    dataset_add = sc,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(SCSTRESN),
    mode = "first",
    new_vars = exprs(EDUCLVL = SCSTRESN),
    filter_add = SCTESTCD == 'EDLEVEL'
  )
