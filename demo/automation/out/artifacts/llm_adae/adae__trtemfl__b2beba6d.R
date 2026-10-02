# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTEMFL | step 1/1: assign_conditional ----
# Spec origin: "If ASTDT >= TRTSDT > . then TRTEMFL='Y'. Otherwise TRTEMFL='N'"
# Agent rationale: Treatment emergent flag is a row-level conditional: 'Y' where ASTDT >= TRTSDT, otherwise 'N'. The '>.' missingness guard is implied (comparisons with missing yield FALSE -> 'N').
# Confidence: 0.75
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
# CHECK: derived values must be a subset of the spec codelist (verify vs metacore)
ADAE <- ADAE |>
  dplyr::mutate(TRTEMFL = dplyr::case_when(
    ASTDT >= TRTSDT ~ "Y",
    TRUE ~ "N"
  ))
# CHECK: human must confirm the condition semantics and the else branch (NA vs "") before use
