# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RFENDTC | step 1/1: assign ----
# Spec origin: "DM.RFENDTC"
# Agent rationale: rule: predecessor copy from DM.RFENDTC
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RFENDTC = RFENDTC)
