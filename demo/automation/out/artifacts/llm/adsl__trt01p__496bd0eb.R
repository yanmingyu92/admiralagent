# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRT01P | step 1/1: assign ----
# Spec origin: "DM.ARM"
# Agent rationale: Planned treatment is copied from dm.ARM, already present in the target base; direct assignment.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(TRT01P = ARM)
