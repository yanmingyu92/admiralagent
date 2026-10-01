# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESER | step 1/1: assign ----
# Spec origin: "AE.AESER"
# Agent rationale: rule: predecessor copy from AE.AESER
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESER = AESER)
