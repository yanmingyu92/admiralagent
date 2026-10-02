# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RFSTDTC | step 1/1: assign ----
# Spec origin: "DM.RFSTDTC"
# Agent rationale: ADSL is seeded from dm, so RFSTDTC is already present in the target base; copy directly as a character predecessor value.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RFSTDTC = RFSTDTC)
