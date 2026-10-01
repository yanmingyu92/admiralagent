# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- R2A1HI | step 1/1: compute_var ----
# Spec origin: "AVAL / A1HI"
# Agent rationale: R2A1HI = AVAL / A1HI is a column-wise arithmetic operation over existing AVAL and A1HI columns, both produced by earlier steps, so compute_var applies directly.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |> dplyr::mutate(R2A1HI = AVAL / A1HI)
