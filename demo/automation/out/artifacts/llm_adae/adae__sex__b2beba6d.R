# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SEX | step 1/1: merge_var ----
# Spec origin: "ADSL.SEX"
# Agent rationale: SEX is sourced from the separate subject-level ADSL dataset, so a merge_var keyed on USUBJID is used.
# Confidence: 0.80
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADAE <- ADAE |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(USUBJID),
    mode = "first",
    new_vars = exprs(SEX = SEX)
  )
