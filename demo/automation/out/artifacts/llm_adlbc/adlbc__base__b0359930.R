# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BASE | step 1/1: assign ----
# Spec origin: "LB.LBSTNRHI"
# Agent rationale: ADLBC seeded from LB, so LB.LBSTNRHI is present in the base; direct copy renamed to BASE via assign.
# Confidence: 0.80
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(BASE = LBSTNRHI)
