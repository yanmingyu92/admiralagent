# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- USUBJID | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.USUBJID"
# Agent rationale: USUBJID is the AE domain's own identifier (ae seeds ADAE), so it is a direct copy from the target base rather than a cross-dataset merge.
# Confidence: 0.75
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  dplyr::mutate(USUBJID = USUBJID)
