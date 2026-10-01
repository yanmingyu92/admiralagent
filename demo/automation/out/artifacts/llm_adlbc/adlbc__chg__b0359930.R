# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CHG | step 1/1: compute_var ----
# Spec origin: "AVAL - BASE"
# Agent rationale: CHG computed as arithmetic over existing AVAL and BASE columns.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |> dplyr::mutate(CHG = AVAL - BASE)
