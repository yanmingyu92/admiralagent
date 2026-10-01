# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RACE | step 1/1: assign ----
# Spec origin: "ADSL.RACE"
# Agent rationale: rule: predecessor copy from ADSL.RACE
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(RACE = RACE)
