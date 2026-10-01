# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESEQ | step 1/1: assign ----
# Spec origin: "AE.AESEQ"
# Agent rationale: rule: predecessor copy from AE.AESEQ
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESEQ = AESEQ)
