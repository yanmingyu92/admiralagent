# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RFSTDTC | step 1/1: assign ----
# Spec origin: "DM.RFSTDTC"
# Agent rationale: rule: predecessor copy from DM.RFSTDTC
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RFSTDTC = RFSTDTC)
