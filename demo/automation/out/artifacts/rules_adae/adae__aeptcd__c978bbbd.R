# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEPTCD | step 1/1: assign ----
# Spec origin: "AE.AEPTCD"
# Agent rationale: rule: predecessor copy from AE.AEPTCD
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEPTCD = AEPTCD)
