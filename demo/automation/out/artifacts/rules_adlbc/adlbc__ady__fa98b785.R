# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADY | step 1/1: assign ----
# Spec origin: "LB.LBDY"
# Agent rationale: rule: predecessor copy from LB.LBDY
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(ADY = LBDY)
