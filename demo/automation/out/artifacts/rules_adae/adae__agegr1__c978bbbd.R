# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGEGR1 | step 1/1: assign ----
# Spec origin: "ADSL.AGEGR1"
# Agent rationale: rule: predecessor copy from ADSL.AGEGR1
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AGEGR1 = AGEGR1)
