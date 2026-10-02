# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- A1LO | step 1/1: assign ----
# Spec origin: "LB.LBSTNRLO"
# Agent rationale: ADLBC is built from LB, so LBSTNRLO is present in the target base; direct copy.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(A1LO = LBSTNRLO)
