# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- STUDYID | step 1/1: merge_var ----
# Spec origin: "Copied directly from ADSL.STUDYID"
# Agent rationale: STUDYID comes from the separate ADSL dataset, not the AE domain that seeds ADAE, so a merge_var is required. Note that in practice ADAE is built from the ae domain which already contains STUDYID; but the spec explicitly names adsl as the source.
# Confidence: 0.80
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADAE <- ADAE |>
  admiral::derive_vars_merged(
    dataset_add = adsl,
    by_vars = exprs(USUBJID),
    mode = "first",
    new_vars = exprs(STUDYID = STUDYID)
  )
