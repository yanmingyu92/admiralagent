# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CHG | step 1/1: compute_var ----
# Spec origin: "AVAL - BASE"
# Agent rationale: rule: column arithmetic change from baseline
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |> dplyr::mutate(CHG = AVAL - BASE)
