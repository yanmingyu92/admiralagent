# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- A1HI | step 1/1: assign ----
# Spec origin: "LB.LBSTNRHI"
# Agent rationale: rule: predecessor copy from LB.LBSTNRHI
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(A1HI = LBSTNRHI)
