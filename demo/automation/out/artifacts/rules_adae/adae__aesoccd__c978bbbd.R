# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESOCCD | step 1/1: assign ----
# Spec origin: "AE.AESOCCD"
# Agent rationale: rule: predecessor copy from AE.AESOCCD
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESOCCD = AESOCCD)
