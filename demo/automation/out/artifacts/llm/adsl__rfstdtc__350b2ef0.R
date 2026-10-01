# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RFSTDTC | step 1/1: assign ----
# Spec origin: "DM.RFSTDTC"
# Agent rationale: RFSTDTC carried as character predecessor copy from DM base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RFSTDTC = RFSTDTC)
