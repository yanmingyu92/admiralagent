# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADURN | step 1/1: compute_var ----
# Spec origin: "ADURN=AENDT-ASTDT+1"
# Agent rationale: ADURN is a straightforward column-wise arithmetic expression over existing columns AENDT and ASTDT, matching the compute_var layer.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |> dplyr::mutate(ADURN = AENDT - ASTDT + 1)
