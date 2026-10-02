# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGEU | step 1/1: assign ----
# Spec origin: "DM.AGEU"
# Agent rationale: ADSL is seeded from dm, so AGEU is already present in the target base; copy directly.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(AGEU = AGEU)
