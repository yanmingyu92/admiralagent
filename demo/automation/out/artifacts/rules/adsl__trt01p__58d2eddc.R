# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRT01P | step 1/1: assign ----
# Spec origin: "DM.ARM"
# Agent rationale: rule: predecessor copy from DM.ARM
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(TRT01P = ARM)
