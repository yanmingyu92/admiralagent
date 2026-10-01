# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADY | step 1/1: assign ----
# Spec origin: "LB.LBDY"
# Agent rationale: ADLBC is seeded from LB, so LB.LBDY is already present in the target base; direct copy via assign.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(ADY = LBDY)
