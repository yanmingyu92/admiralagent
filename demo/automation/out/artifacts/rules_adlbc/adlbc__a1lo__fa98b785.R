# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- A1LO | step 1/1: assign ----
# Spec origin: "LB.LBSTNRLO"
# Agent rationale: rule: predecessor copy from LB.LBSTNRLO
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(A1LO = LBSTNRLO)
