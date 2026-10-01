# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- USUBJID | step 1/1: assign ----
# Spec origin: "Copied directly from DM.USUBJID"
# Agent rationale: Direct copy of USUBJID from DM base dataset.
# Confidence: 0.95
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(USUBJID = USUBJID)
