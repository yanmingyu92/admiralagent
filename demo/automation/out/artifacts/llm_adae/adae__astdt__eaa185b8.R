# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDT | step 1/1: impute_dtc ----
# Spec origin: "AE.AESTDTC, converted to a numeric SAS date. Some events with partial dates are imputed in a conservative manner. If the day component is missing, a value of '01' is used. If both the month and day are missing no imputation is performed as these dates clearly indicate a start prior to the beginning of treatment. There are no events with completely missing start dates."
# Agent rationale: ASTDT is derived from AE.AESTDTC; AESTDTC is already present in the ADAE base (ae), so impute_dtc on the base imputes the day component with 'first' (day '01'); output is date-only ASTDT with accompanying ASTDTF flag.
# Confidence: 0.80
# CHECK: *DTF/*TMF flags created by imputation; NA where nothing was imputed
# CHECK: target variable must not be all-missing after the derivation
ADAE <- ADAE |>
  admiral::derive_vars_dt(
    new_vars_prefix = "AST",
    dtc = AESTDTC,
    highest_imputation = "D",
    date_imputation = "first",
    flag_imputation = "auto"
  )
