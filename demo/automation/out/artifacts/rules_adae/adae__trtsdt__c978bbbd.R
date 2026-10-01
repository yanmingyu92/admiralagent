# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTSDT | step 1/1: assign ----
# Spec origin: "ADSL.TRTSDT"
# Agent rationale: rule: predecessor copy from ADSL.TRTSDT
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(TRTSDT = TRTSDT)
