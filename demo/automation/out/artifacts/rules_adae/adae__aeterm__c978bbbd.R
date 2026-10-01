# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AETERM | step 1/1: assign ----
# Spec origin: "AE.AETERM"
# Agent rationale: rule: predecessor copy from AE.AETERM
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AETERM = AETERM)
