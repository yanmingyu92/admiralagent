# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTSDT | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.TRTSDT"
# Agent rationale: TRTSDT is a predecessor variable present in the ADLBC base dataset, copied directly with assign.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(TRTSDT = TRTSDT)
