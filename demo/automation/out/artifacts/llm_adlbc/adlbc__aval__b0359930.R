# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AVAL | step 1/1: assign ----
# Spec origin: "Copied directly from LB.LBSTRESN"
# Agent rationale: ADLBC is seeded from LB, so LB.LBSTRESN is already present in the target base; direct copy renamed to AVAL via assign.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(AVAL = LBSTRESN)
