# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADT | step 1/1: assign ----
# Spec origin: "LB.LBDTC"
# Agent rationale: rule: predecessor copy from LB.LBDTC
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(ADT = LBDTC)
