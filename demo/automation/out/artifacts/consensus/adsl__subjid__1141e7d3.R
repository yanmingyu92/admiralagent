# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SUBJID | step 1/1: assign ----
# Spec origin: "DM.SUBJID"
# Agent rationale: ADSL is seeded from DM, so SUBJID is already present in the target base; direct copy.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(SUBJID = SUBJID)
