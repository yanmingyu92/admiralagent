# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESHOSP | step 1/1: assign ----
# Spec origin: "AE.AESHOSP"
# Agent rationale: AESHOSP comes from the AE domain that seeds the ADAE base, so the column already exists in the target dataset; a direct assign copy is correct, not a merge.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESHOSP = AESHOSP)
