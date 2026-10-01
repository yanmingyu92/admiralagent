# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SEX | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.SEX"
# Agent rationale: rule: direct copy from source variable
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(SEX = SEX)
