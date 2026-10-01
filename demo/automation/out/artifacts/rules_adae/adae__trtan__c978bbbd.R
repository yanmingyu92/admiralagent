# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTAN | step 1/1: assign ----
# Spec origin: "ADSL.TRT01AN"
# Agent rationale: rule: predecessor copy from ADSL.TRT01AN
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(TRTAN = TRT01AN)
