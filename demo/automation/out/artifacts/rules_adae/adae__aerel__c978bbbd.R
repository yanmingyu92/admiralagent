# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEREL | step 1/1: assign ----
# Spec origin: "AE.AEREL"
# Agent rationale: rule: predecessor copy from AE.AEREL
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEREL = AEREL)
