# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGEGR1 | step 1/1: merge_var ----
# Spec origin: "ADSL.AGEGR1"
# Agent rationale: AGEGR1 is defined as ADSL.AGEGR1, a value from a different dataset than the ADAE base; merge_var brings AGEGR1 in keyed on USUBJID.
# Confidence: 0.85
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADAE <- ADAE |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(USUBJID),
    mode = "first",
    new_vars = exprs(AGEGR1 = AGEGR1)
  )
