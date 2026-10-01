# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- STUDYID | step 1/1: assign ----
# Spec origin: "Copied directly from ADSL.STUDYID"
# Agent rationale: STUDYID is a predecessor variable present in the ADLBC base dataset (carried from the ADMIRAL skeleton), so it is copied directly with assign rather than a merge, avoiding self-referential merge keys.
# Confidence: 0.85
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  dplyr::mutate(STUDYID = STUDYID)
