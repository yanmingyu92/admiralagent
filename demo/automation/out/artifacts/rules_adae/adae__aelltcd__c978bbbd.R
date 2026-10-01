# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AELLTCD | step 1/1: assign ----
# Spec origin: "AE.AELLTCD"
# Agent rationale: rule: predecessor copy from AE.AELLTCD
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AELLTCD = AELLTCD)
