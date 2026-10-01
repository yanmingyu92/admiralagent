# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SEX | step 1/1: assign ----
# Spec origin: "ADSL.SEX"
# Agent rationale: rule: predecessor copy from ADSL.SEX
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(SEX = SEX)
