# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RACE | step 1/1: assign ----
# Spec origin: "DM.RACE"
# Agent rationale: rule: predecessor copy from DM.RACE
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RACE = RACE)
