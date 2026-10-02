# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AVGDD | step 1/1: compute_var ----
# Spec origin: "CUMDOSE/TRTDURD"
# Agent rationale: AVGDD = CUMDOSE / TRTDURD; both columns exist from earlier steps. CUMDOSE derivation is complex but this division is unambiguous.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |> dplyr::mutate(AVGDD = CUMDOSE / TRTDURD)
