# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTDURD | step 1/1: compute_var ----
# Spec origin: "TRTEDT-TRTSDT+1"
# Agent rationale: Column-wise arithmetic over existing TRTEDT and TRTSDT columns.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |> dplyr::mutate(TRTDURD = TRTEDT - TRTSDT + 1)
