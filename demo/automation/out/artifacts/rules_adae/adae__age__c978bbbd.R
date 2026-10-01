# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGE | step 1/1: assign ----
# Spec origin: "ADSL.AGE"
# Agent rationale: rule: predecessor copy from ADSL.AGE
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AGE = AGE)
