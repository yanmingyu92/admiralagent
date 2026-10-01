# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- DTHFL | step 1/1: assign ----
# Spec origin: "DM.DTHFL"
# Agent rationale: DTHFL carried directly from DM base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(DTHFL = DTHFL)
