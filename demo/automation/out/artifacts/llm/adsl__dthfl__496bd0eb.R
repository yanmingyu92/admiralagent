# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- DTHFL | step 1/1: assign ----
# Spec origin: "DM.DTHFL"
# Agent rationale: ADSL is seeded from dm, so DTHFL is already present in the target base; copy directly.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(DTHFL = DTHFL)
