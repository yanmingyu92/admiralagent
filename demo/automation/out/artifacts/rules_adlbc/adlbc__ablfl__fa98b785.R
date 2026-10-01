# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ABLFL | step 1/1: assign ----
# Spec origin: "Copied directly from LB.LBBLFL"
# Agent rationale: rule: direct copy from source variable
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(ABLFL = LBBLFL)
