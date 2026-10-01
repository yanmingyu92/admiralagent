# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ARM | step 1/1: assign ----
# Spec origin: "DM.ARM"
# Agent rationale: ARM carried directly from DM base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(ARM = ARM)
