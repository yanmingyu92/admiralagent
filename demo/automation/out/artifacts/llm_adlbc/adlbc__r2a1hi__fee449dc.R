# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- R2A1HI | step 1/1: compute_var ----
# Spec origin: "AVAL / A1HI"
# Agent rationale: R2A1HI is arithmetic on existing columns AVAL and A1HI, produced by earlier steps.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |> dplyr::mutate(R2A1HI = AVAL / A1HI)
