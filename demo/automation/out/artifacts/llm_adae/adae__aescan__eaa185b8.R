# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESCAN | step 1/1: assign ----
# Spec origin: "AE.AESCAN"
# Agent rationale: AESCAN comes from the AE domain that seeds the ADAE base, so the column already exists in the target dataset; a direct assign copy is correct, not a merge.
# Confidence: 0.90
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESCAN = AESCAN)
