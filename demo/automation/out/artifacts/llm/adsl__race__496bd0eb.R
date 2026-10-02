# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RACE | step 1/1: assign ----
# Spec origin: "DM.RACE"
# Agent rationale: ADSL is seeded from dm, so RACE is already present in the target base; copy directly.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RACE = RACE)
