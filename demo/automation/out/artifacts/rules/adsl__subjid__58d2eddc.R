# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SUBJID | step 1/1: assign ----
# Spec origin: "DM.SUBJID"
# Agent rationale: rule: predecessor copy from DM.SUBJID
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(SUBJID = SUBJID)
