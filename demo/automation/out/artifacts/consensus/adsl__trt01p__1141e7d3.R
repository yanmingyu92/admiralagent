# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRT01P | step 1/1: assign ----
# Spec origin: "DM.ARM"
# Agent rationale: ADSL is seeded from DM, so ARM is already present in the target base; TRT01P copies ARM directly.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(TRT01P = ARM)
