# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AEDECOD | step 1/1: assign ----
# Spec origin: "AE.AEDECOD"
# Agent rationale: AEDECOD exists in the ADAE base dataset; direct copy.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AEDECOD = AEDECOD)
