# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEBODSYS | step 1/1: assign ----
# Spec origin: "AE.AEBODSYS"
# Agent rationale: rule: predecessor copy from AE.AEBODSYS
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEBODSYS = AEBODSYS)
