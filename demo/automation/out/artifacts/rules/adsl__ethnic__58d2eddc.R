# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ETHNIC | step 1/1: assign ----
# Spec origin: "DM.ETHNIC"
# Agent rationale: rule: predecessor copy from DM.ETHNIC
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(ETHNIC = ETHNIC)
