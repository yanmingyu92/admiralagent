# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEHLT | step 1/1: assign ----
# Spec origin: "AE.AEHLT"
# Agent rationale: rule: predecessor copy from AE.AEHLT
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEHLT = AEHLT)
