# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CHG | step 1/1: compute_var ----
# Spec origin: "AVAL - BASE"
# Agent rationale: CHG = AVAL - BASE is a column-wise arithmetic operation over existing AVAL and BASE columns in ADLBC; both are produced by earlier steps, so compute_var applies directly.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |> dplyr::mutate(CHG = AVAL - BASE)
