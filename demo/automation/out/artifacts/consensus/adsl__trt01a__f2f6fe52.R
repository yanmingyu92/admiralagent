# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRT01A | step 1/1: assign ----
# Spec origin: "TRT01A=TRT01P, i.e., no difference between actual and randomized treatment in this study."
# Agent rationale: Explicit statement that actual and randomized treatment have no difference, so TRT01A is a direct copy of TRT01P.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(TRT01A = TRT01P)
