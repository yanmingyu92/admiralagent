# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGEGR1N | step 1/1: assign ----
# Spec origin: "ADSL.AGEGR1N"
# Agent rationale: rule: predecessor copy from ADSL.AGEGR1N
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AGEGR1N = AGEGR1N)
