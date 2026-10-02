# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BMIBL | step 1/1: compute_var ----
# Spec origin: "WEIGHTBL / ((HEIGHTBL/100)**2)"
# Agent rationale: BMIBL = WEIGHTBL / (HEIGHTBL/100)^2, column-wise arithmetic over existing columns produced by earlier steps.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |> dplyr::mutate(BMIBL = WEIGHTBL / (HEIGHTBL / 100)^2)
