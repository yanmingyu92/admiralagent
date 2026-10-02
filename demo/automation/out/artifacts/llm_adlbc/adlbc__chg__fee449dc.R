# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CHG | step 1/1: compute_var ----
# Spec origin: "AVAL - BASE"
# Agent rationale: CHG is arithmetic on existing columns AVAL and BASE, produced by earlier steps.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |> dplyr::mutate(CHG = AVAL - BASE)
