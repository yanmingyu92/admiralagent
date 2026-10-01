# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- RFENDT | step 1/1: impute_dtc ----
# Spec origin: "RFENDTC converted to SAS date"
# Agent rationale: rule: impute DM RFENDTC directly (pilot ADSL convention)
# Confidence: 1.00
# CHECK: *DTF/*TMF flags created by imputation; NA where nothing was imputed
# CHECK: target variable must not be all-missing after the derivation
ADSL <- ADSL |>
  admiral::derive_vars_dt(
    new_vars_prefix = "RFEN",
    dtc = RFENDTC,
    highest_imputation = "M",
    date_imputation = "last",
    flag_imputation = "auto"
  )
