# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RFENDTC | step 1/1: assign ----
# Spec origin: "DM.RFENDTC"
# Agent rationale: ADSL is seeded from dm, so RFENDTC is already present in the target base; copy directly as a character predecessor value.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RFENDTC = RFENDTC)
