# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SITEID | step 1/1: assign ----
# Spec origin: "DM.SITEID"
# Agent rationale: ADSL is seeded from dm, so SITEID is already present in the target base; copy directly.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(SITEID = SITEID)
