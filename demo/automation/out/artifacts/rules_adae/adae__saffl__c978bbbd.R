# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SAFFL | step 1/1: assign ----
# Spec origin: "ADSL.SAFFL"
# Agent rationale: rule: predecessor copy from ADSL.SAFFL
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(SAFFL = SAFFL)
