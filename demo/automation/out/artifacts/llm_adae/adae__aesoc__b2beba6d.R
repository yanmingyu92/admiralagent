# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESOC | step 1/1: assign ----
# Spec origin: "AE.AESOC"
# Agent rationale: AESOC originates in the AE domain that seeds ADAE, so it is a direct copy from the target base rather than a cross-dataset merge.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESOC = AESOC)
