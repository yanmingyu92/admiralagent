# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESHOSP | step 1/1: assign ----
# Spec origin: "AE.AESHOSP"
# Agent rationale: rule: predecessor copy from AE.AESHOSP
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESHOSP = AESHOSP)
