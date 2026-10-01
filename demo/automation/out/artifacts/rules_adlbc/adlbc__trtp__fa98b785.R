# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTP | step 1/1: assign ----
# Spec origin: "ADSL.TRT01P"
# Agent rationale: rule: predecessor copy from ADSL.TRT01P
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(TRTP = TRT01P)
