# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTA | step 1/1: assign ----
# Spec origin: "ADSL.TRT01A"
# Agent rationale: rule: predecessor copy from ADSL.TRT01A
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(TRTA = TRT01A)
