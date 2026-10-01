# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SEX | step 1/1: assign ----
# Spec origin: "DM.SEX"
# Agent rationale: rule: predecessor copy from DM.SEX
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(SEX = SEX)
