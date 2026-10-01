# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SEX | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.SEX"
# Agent rationale: SEX is a predecessor variable present in the ADLBC base dataset, copied directly with assign.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(SEX = SEX)
