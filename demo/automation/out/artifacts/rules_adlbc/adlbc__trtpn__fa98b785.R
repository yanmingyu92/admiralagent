# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTPN | step 1/1: assign ----
# Spec origin: "ADSL.TRT01PN"
# Agent rationale: rule: predecessor copy from ADSL.TRT01PN
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(TRTPN = TRT01PN)
