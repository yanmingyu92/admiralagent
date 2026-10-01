# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- USUBJID | step 1/1: assign ----
# Spec origin: "Copied directly from DM.USUBJID"
# Agent rationale: rule: direct copy from source variable
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(USUBJID = USUBJID)
