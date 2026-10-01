# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEREL | step 1/1: assign ----
# Spec origin: "AE.AEREL"
# Agent rationale: AEREL exists in the ADAE base dataset; direct copy.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEREL = AEREL)
