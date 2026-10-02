# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ITTFL | step 1/1: assign_conditional ----
# Spec origin: "Y if ARMCD ne ' '. N otherwise"
# Agent rationale: Y where ARMCD is non-blank, N otherwise; ARMCD is present in ADSL from dm base. Condition uses comparison against a blank string literal.
# Confidence: 0.85
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
# CHECK: derived values must be a subset of the spec codelist (verify vs metacore)
ADSL <- ADSL |>
  dplyr::mutate(ITTFL = dplyr::case_when(
    ARMCD != ' ' ~ "Y",
    TRUE ~ "N"
  ))
# CHECK: human must confirm the condition semantics and the else branch (NA vs "") before use
