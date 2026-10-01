# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AOCCFL | step 1/1: extreme_flag ----
# Spec origin: "Subset to TRTEMFL='Y' and sort by Subject (USUBJID), Start Date (ASTDT), and Sequence Number (AESEQ) and flag the first record (set AOCCFL=?Y?) within each Subject"
# Agent rationale: AOCCFL flags the first occurrence within each subject, restricted to TRTEMFL='Y', ordered by ASTDT and AESEQ, matching the extreme_flag layer with mode='first'.
# Confidence: 0.85
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
ADAE <- ADAE |>
  admiral::restrict_derivation(
    derivation = admiral::derive_var_extreme_flag,
    args = params(new_var = AOCCFL, by_vars = exprs(USUBJID), order = exprs(ASTDT, AESEQ), mode = "first", true_value = "Y"),
    filter = TRTEMFL == 'Y'
  )
