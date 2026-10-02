# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AOCCSFL | step 1/1: extreme_flag ----
# Spec origin: "Subset to TRTEMFL='Y' and sort by Subject (USUBJID), System Organ Class (AEBODSYS), Start Date (ASTDT), and Sequence Number (AESEQ) and flag the first record (set AOCCSFL=?Y?) within each Subject and SOC"
# Agent rationale: First occurrence of SOC per subject-and-SOC, ordered by ASTDT then AESEQ, scoped to treatment-emergent events.
# Confidence: 0.85
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
ADAE <- ADAE |>
  admiral::restrict_derivation(
    derivation = admiral::derive_var_extreme_flag,
    args = params(new_var = AOCCSFL, by_vars = exprs(USUBJID, AEBODSYS), order = exprs(ASTDT, AESEQ), mode = "first", true_value = "Y"),
    filter = TRTEMFL == 'Y'
  )
