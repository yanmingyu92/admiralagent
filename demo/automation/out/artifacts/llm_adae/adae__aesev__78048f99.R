# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESEV | step 1/1: assign ----
# Spec origin: "AE.AESEV"
# Agent rationale: AESEV exists in the ADAE base dataset; direct copy.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESEV = AESEV)
