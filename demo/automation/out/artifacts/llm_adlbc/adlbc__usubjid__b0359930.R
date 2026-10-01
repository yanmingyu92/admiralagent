# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- USUBJID | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.USUBJID"
# Agent rationale: USUBJID is the join key already present in the ADLBC base (seeded from lb), copied directly.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(USUBJID = USUBJID)
