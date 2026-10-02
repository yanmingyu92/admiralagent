# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADURN | step 1/1: compute_var ----
# Spec origin: "ADURN=AENDT-ASTDT+1"
# Agent rationale: Analysis duration is a straightforward column-wise arithmetic over the already-derived AENDT and ASTDT columns.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |> dplyr::mutate(ADURN = AENDT - ASTDT + 1)
