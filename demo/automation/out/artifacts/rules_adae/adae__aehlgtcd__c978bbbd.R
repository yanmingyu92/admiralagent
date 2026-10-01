# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEHLGTCD | step 1/1: assign ----
# Spec origin: "AE.AEHLGTCD"
# Agent rationale: rule: predecessor copy from AE.AEHLGTCD
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEHLGTCD = AEHLGTCD)
