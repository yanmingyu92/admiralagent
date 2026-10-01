# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SUBJID | step 1/1: assign ----
# Spec origin: "DM.SUBJID"
# Agent rationale: Direct copy of DM.SUBJID, which is already present in the subject-level base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(SUBJID = SUBJID)
