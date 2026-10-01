# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESDISAB | step 1/1: assign ----
# Spec origin: "AE.AESDISAB"
# Agent rationale: rule: predecessor copy from AE.AESDISAB
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESDISAB = AESDISAB)
