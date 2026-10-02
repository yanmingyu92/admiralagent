# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AOCC02FL | step 1/1: extreme_flag ----
# Spec origin: "Subset to TRTEMFL='Y' and AESER='Y' and sort by Subject (USUBJID), Start Date (ASTDT), and Sequence Number (AESEQ) and flag the first record (set AOCC02FL=?Y?) within each Subject"
# Agent rationale: First occurrence of serious treatment-emergent event per subject, ordered by ASTDT then AESEQ, scoped to TRTEMFL='Y' and AESER='Y'.
# Confidence: 0.85
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
ADAE <- ADAE |>
  admiral::restrict_derivation(
    derivation = admiral::derive_var_extreme_flag,
    args = params(new_var = AOCC02FL, by_vars = exprs(USUBJID), order = exprs(ASTDT, AESEQ), mode = "first", true_value = "Y"),
    filter = TRTEMFL == 'Y' & AESER == 'Y'
  )
