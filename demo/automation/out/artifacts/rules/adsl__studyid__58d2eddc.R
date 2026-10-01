# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- STUDYID | step 1/1: assign ----
# Spec origin: "Copied directly from DM.STUDYID"
# Agent rationale: rule: direct copy from source variable
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(STUDYID = STUDYID)
