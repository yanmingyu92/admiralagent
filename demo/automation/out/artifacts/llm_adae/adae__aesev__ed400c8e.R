# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AESEV | step 1/1: merge_var ----
# Spec origin: "AE.AESEV"
# Agent rationale: AESEV is taken from the AE source dataset via merge_var.
# Confidence: 0.85
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADAE <- ADAE |>
  admiral::derive_vars_merged(
    dataset_add = ae,
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first",
    new_vars = exprs(AESEV = AESEV)
  )
