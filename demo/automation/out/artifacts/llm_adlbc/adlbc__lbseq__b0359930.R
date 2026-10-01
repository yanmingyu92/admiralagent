# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- LBSEQ | step 1/1: assign ----
# Spec origin: "Copied directly from LB.LBSEQ"
# Agent rationale: ADLBC is seeded from LB, so LB.LBSEQ is already present in the target base; direct copy via assign.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(LBSEQ = LBSEQ)
