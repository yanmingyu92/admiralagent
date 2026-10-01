# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SITEID | step 1/1: assign ----
# Spec origin: "DM.SITEID"
# Agent rationale: Direct copy of DM.SITEID, which is already present in the subject-level base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(SITEID = SITEID)
