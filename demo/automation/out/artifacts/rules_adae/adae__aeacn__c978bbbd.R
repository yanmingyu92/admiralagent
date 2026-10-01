# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEACN | step 1/1: assign ----
# Spec origin: "AE.AEACN"
# Agent rationale: rule: predecessor copy from AE.AEACN
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEACN = AEACN)
