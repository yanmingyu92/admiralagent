# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AOCCPFL | step 1/1: extreme_flag ----
# Spec origin: "Subset to TRTEMFL='Y' and sort by Subject (USUBJID), System Organ Class (AEBODSYS), Preferred Term (AEDECOD), Start Date (ASTDT), and Sequence Number (AESEQ) and flag the first record (set AOCCPFL=?Y?) within each Subject, SOC, and PT"
# Agent rationale: First occurrence within subject, SOC and PT among treatment-emergent records: extreme_flag first ordered by ASTDT, AESEQ with restrict_filter TRTEMFL='Y'.
# Confidence: 0.85
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
ADAE <- ADAE |>
  admiral::restrict_derivation(
    derivation = admiral::derive_var_extreme_flag,
    args = params(new_var = AOCCPFL, by_vars = exprs(USUBJID, AEBODSYS, AEDECOD), order = exprs(ASTDT, AESEQ), mode = "first", true_value = "Y"),
    filter = TRTEMFL == 'Y'
  )
