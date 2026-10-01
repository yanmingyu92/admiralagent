# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEDECOD | step 1/1: assign ----
# Spec origin: "AE.AEDECOD"
# Agent rationale: rule: predecessor copy from AE.AEDECOD
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEDECOD = AEDECOD)
