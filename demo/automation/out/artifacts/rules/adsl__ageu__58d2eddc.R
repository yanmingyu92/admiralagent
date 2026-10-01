# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGEU | step 1/1: assign ----
# Spec origin: "DM.AGEU"
# Agent rationale: rule: predecessor copy from DM.AGEU
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  dplyr::mutate(AGEU = AGEU)
