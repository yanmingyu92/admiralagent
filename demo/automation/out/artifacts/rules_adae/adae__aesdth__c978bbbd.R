# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESDTH | step 1/1: assign ----
# Spec origin: "AE.AESDTH"
# Agent rationale: rule: predecessor copy from AE.AESDTH
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESDTH = AESDTH)
