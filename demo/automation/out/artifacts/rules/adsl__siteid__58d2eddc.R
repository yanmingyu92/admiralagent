# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SITEID | step 1/1: assign ----
# Spec origin: "DM.SITEID"
# Agent rationale: rule: predecessor copy from DM.SITEID
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(SITEID = SITEID)
