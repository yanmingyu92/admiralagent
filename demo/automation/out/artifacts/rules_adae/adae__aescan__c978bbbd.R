# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESCAN | step 1/1: assign ----
# Spec origin: "AE.AESCAN"
# Agent rationale: rule: predecessor copy from AE.AESCAN
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESCAN = AESCAN)
