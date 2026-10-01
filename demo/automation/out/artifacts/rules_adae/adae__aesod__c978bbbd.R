# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESOD | step 1/1: assign ----
# Spec origin: "AE.AESOD"
# Agent rationale: rule: predecessor copy from AE.AESOD
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(AESOD = AESOD)
