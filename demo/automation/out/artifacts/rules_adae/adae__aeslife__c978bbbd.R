# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESLIFE | step 1/1: assign ----
# Spec origin: "AE.AESLIFE"
# Agent rationale: rule: predecessor copy from AE.AESLIFE
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESLIFE = AESLIFE)
