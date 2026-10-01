# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AELLT | step 1/1: assign ----
# Spec origin: "AE.AELLT"
# Agent rationale: rule: predecessor copy from AE.AELLT
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AELLT = AELLT)
