# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SAFFL | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.SAF01FL"
# Agent rationale: rule: direct copy from source variable
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(SAFFL = SAF01FL)
