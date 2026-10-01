# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- PARAMCD | step 1/1: assign ----
# Spec origin: "Copied directly from LB.TESTCD"
# Agent rationale: ADLBC is seeded from LB, so LB.TESTCD is already present in the target base; direct copy renamed to PARAMCD via assign.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(PARAMCD = TESTCD)
