# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BASE | step 1/1: assign ----
# Spec origin: "LB.LBSTNRHI"
# Agent rationale: ADLBC is built from LB, so LBSTNRHI is present in the target base; direct copy. Note spec maps the normal high range value to BASE, which is unusual but taken verbatim.
# Confidence: 0.80
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(BASE = LBSTNRHI)
