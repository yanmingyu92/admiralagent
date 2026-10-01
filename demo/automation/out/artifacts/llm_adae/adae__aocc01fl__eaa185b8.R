# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AOCC01FL | step 1/1: extreme_flag ----
# Spec origin: "Subset to CQ01NAM='DERMATOLOGIC EVENTS' and TRTEMFL='Y' and sort by Subject (USUBJID), Start Date (ASTDT), and Sequence Number (AESEQ) and flag the first record (set AOCC01FL=?Y?) within each Subject (Flag First Treatment Emergent Dermatological Event for Time to Event Analysis)"
# Agent rationale: Flags the first record within each subject restricted to CQ01NAM='DERMATOLOGIC EVENTS' and TRTEMFL='Y', ordered by ASTDT and AESEQ, matching extreme_flag with mode='first'. Depends on CQ01NAM producer.
# Confidence: 0.80
# CHECK: flag variable should be set for at least some records (not all-NA, not all-set)
ADAE <- ADAE |>
  admiral::restrict_derivation(
    derivation = admiral::derive_var_extreme_flag,
    args = params(new_var = AOCC01FL, by_vars = exprs(USUBJID), order = exprs(ASTDT, AESEQ), mode = "first", true_value = "Y"),
    filter = CQ01NAM == 'DERMATOLOGIC EVENTS' & TRTEMFL == 'Y'
  )
