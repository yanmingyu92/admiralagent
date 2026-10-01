# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RFENDTC | step 1/1: assign ----
# Spec origin: "DM.RFENDTC"
# Agent rationale: RFENDTC carried as character predecessor copy from DM base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(RFENDTC = RFENDTC)
