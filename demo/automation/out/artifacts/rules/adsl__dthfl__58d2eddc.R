# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- DTHFL | step 1/1: assign ----
# Spec origin: "DM.DTHFL"
# Agent rationale: rule: predecessor copy from DM.DTHFL
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(DTHFL = DTHFL)
