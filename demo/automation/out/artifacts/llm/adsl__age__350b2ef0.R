# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGE | step 1/1: assign ----
# Spec origin: "DM.AGE"
# Agent rationale: AGE carried directly from DM base dataset.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(AGE = AGE)
