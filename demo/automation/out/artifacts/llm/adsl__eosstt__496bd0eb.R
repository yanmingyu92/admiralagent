# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- EOSSTT | step 1/1: assign_conditional ----
# Spec origin: "COMPLETED if ADSL.DCDECOD='COMPLETED'. DISCONTINUED if ADSL.DCDECOD not equal to COMPLETED."
# Agent rationale: EOSSTT = COMPLETED where DCDECOD='COMPLETED', else DISCONTINUED; DCDECOD produced by an earlier step.
# Confidence: 0.85
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
# CHECK: derived values must be a subset of the spec codelist (verify vs metacore)
ADSL <- ADSL |>
  dplyr::mutate(EOSSTT = dplyr::case_when(
    DCDECOD == 'COMPLETED' ~ "COMPLETED",
    TRUE ~ "DISCONTINUED"
  ))
# CHECK: human must confirm the condition semantics and the else branch (NA vs "") before use
