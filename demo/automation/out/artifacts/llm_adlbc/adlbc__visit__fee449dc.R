# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- VISIT | step 1/1: assign ----
# Spec origin: "Copied directly from LB.VISIT"
# Agent rationale: ADLBC is built from the LB domain, so LB.VISIT is already present in the target base and is copied directly with assign.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(VISIT = VISIT)
