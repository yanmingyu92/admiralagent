# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AOCC03FL | step 1/1: extreme_flag ----
# Spec origin: "Subset to TRTEMFL='Y' and AESER='Y' and sort by Subject (USUBJID), System Organ Class (AEBODSYS), Start Date (ASTDT), and Sequence Number (AESEQ) and flag the first record (set AOCC03FL=?Y?) within each Subject and SOC"
# Agent rationale: First treatment-emergent serious occurrence within subject and SOC, ordered by ASTDT then AESEQ.
# Confidence: 0.85
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
ADAE <- ADAE |>
  admiral::restrict_derivation(
    derivation = admiral::derive_var_extreme_flag,
    args = params(new_var = AOCC03FL, by_vars = exprs(STUDYID, USUBJID, AEBODSYS), order = exprs(ASTDT, AESEQ), mode = "first", true_value = "Y"),
    filter = TRTEMFL == 'Y' & AESER == 'Y'
  )
