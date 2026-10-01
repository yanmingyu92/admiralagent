# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- VISIT | step 1/1: assign ----
# Spec origin: "Copied directly from LB.VISIT"
# Agent rationale: ADLBC is seeded from LB, so LB.VISIT is already present in the target base; direct copy via assign.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(VISIT = VISIT)
