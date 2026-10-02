# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTSDT | step 1/2: merge_var ----
# Spec origin: "SV.SVSTDTC when SV.VISITNUM=3, converted to SAS date"
# Agent rationale: First qualifying SV visit-3 date pulled from sv then imputed to SAS date.
# Confidence: 0.85
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  admiral::derive_vars_merged(
    dataset_add = sv,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(SVSTDTC),
    mode = "first",
    new_vars = exprs(SVSTDTC = SVSTDTC),
    filter_add = VISITNUM == 3
  )

# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTSDT | step 2/2: impute_dtc ----
# Spec origin: "SV.SVSTDTC when SV.VISITNUM=3, converted to SAS date"
# Agent rationale: First qualifying SV visit-3 date pulled from sv then imputed to SAS date.
# Confidence: 0.85
# CHECK: *DTF/*TMF flags created by imputation; NA where nothing was imputed
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  admiral::derive_vars_dt(
    new_vars_prefix = "TRTS",
    dtc = SVSTDTC,
    highest_imputation = "D",
    date_imputation = "first",
    flag_imputation = "auto"
  )
