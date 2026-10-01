# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- A1LO | step 1/1: assign ----
# Spec origin: "LB.LBSTNRLO"
# Agent rationale: ADLBC seeded from LB, so LB.LBSTNRLO is present in the base; direct copy renamed to A1LO via assign.
# Confidence: 0.80
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(A1LO = LBSTNRLO)
