# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRT01A | step 1/1: assign ----
# Spec origin: "TRT01A=TRT01P, i.e., no difference between actual and randomized treatment in this study."
# Agent rationale: rule: self-referential assignment TRT01A=TRT01P
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(TRT01A = TRT01P)
