# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SITEID | step 1/1: assign ----
# Spec origin: "ADSL.SITEID"
# Agent rationale: rule: predecessor copy from ADSL.SITEID
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(SITEID = SITEID)
