# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTEDT | step 1/1: assign ----
# Spec origin: "ADSL.TRTEDT"
# Agent rationale: rule: predecessor copy from ADSL.TRTEDT
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(TRTEDT = TRTEDT)
