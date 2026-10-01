# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESOC | step 1/1: assign ----
# Spec origin: "AE.AESOC"
# Agent rationale: rule: predecessor copy from AE.AESOC
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESOC = AESOC)
