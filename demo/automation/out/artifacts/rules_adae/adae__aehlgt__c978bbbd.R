# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEHLGT | step 1/1: assign ----
# Spec origin: "AE.AEHLGT"
# Agent rationale: rule: predecessor copy from AE.AEHLGT
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEHLGT = AEHLGT)
