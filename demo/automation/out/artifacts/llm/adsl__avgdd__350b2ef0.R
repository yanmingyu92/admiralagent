# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AVGDD | step 1/1: compute_var ----
# Spec origin: "CUMDOSE/TRTDURD"
# Agent rationale: Arithmetic over existing columns CUMDOSE and TRTDURD.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |> dplyr::mutate(AVGDD = CUMDOSE / TRTDURD)
