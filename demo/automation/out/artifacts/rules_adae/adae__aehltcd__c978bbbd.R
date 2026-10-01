# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEHLTCD | step 1/1: assign ----
# Spec origin: "AE.AEHLTCD"
# Agent rationale: rule: predecessor copy from AE.AEHLTCD
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEHLTCD = AEHLTCD)
