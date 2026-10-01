# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- LBSTRESN | step 1/1: assign ----
# Spec origin: "Copied directly from LB.LBSTRESN"
# Agent rationale: ADLBC is seeded from LB, so LB.LBSTRESN is already present in the target base; direct copy via assign.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(LBSTRESN = LBSTRESN)
