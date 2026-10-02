# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADT | step 1/1: impute_dtc ----
# Spec origin: "LB.LBDTC"
# Agent rationale: Convert LB.LBDTC character date to numeric ADT date. Imputation defaults applied since spec does not specify; date_imputation 'first' with highest_imputation 'D'.
# Confidence: 0.75
# CHECK: *DTF/*TMF flags created by imputation; NA where nothing was imputed
# CHECK: target variable must not be all-missing after the derivation
ADLBC <- ADLBC |>
  admiral::derive_vars_dt(
    new_vars_prefix = "A",
    dtc = LBDTC,
    highest_imputation = "D",
    date_imputation = "first",
    flag_imputation = "auto"
  )
