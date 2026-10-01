# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BMIBL | step 1/1: compute_var ----
# Spec origin: "WEIGHTBL / ((HEIGHTBL/100)**2)"
# Agent rationale: Arithmetic over existing columns WEIGHTBL and HEIGHTBL.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |> dplyr::mutate(BMIBL = WEIGHTBL / (HEIGHTBL / 100)^2)
