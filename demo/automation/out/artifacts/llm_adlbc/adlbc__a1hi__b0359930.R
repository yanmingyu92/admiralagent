# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- A1HI | step 1/1: assign ----
# Spec origin: "LB.LBSTNRHI"
# Agent rationale: ADLBC seeded from LB, so LB.LBSTNRHI is present in the base; direct copy renamed to A1HI via assign.
# Confidence: 0.80
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(A1HI = LBSTNRHI)
