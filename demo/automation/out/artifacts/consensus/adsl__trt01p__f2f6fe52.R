# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRT01P | step 1/1: assign ----
# Spec origin: "DM.ARM"
# Agent rationale: TRT01P is a direct copy of DM.ARM, which is present in the subject-level base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(TRT01P = ARM)
