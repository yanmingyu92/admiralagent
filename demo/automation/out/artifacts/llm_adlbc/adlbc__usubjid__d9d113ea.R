# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- USUBJID | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.USUBJID"
# Agent rationale: USUBJID is a predecessor variable present in the ADLBC base dataset, copied directly with assign; no merge key is required or possible.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(USUBJID = USUBJID)
