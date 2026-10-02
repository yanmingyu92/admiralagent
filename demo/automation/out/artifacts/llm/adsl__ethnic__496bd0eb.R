# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ETHNIC | step 1/1: assign ----
# Spec origin: "DM.ETHNIC"
# Agent rationale: ADSL is seeded from dm, so ETHNIC is already present in the target base; copy directly.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(ETHNIC = ETHNIC)
