# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BMIBLGR1 | step 1/2: compute_param ----
# Spec origin: "BMIBLGR1="<25" if . < BMIBL <25. BMIBLGR1="25-<30" if 25 <=BMIBL <30. BMIBLGR1=">=30"if BMIBL >=30."
# Agent rationale: rule: BMI formula from WEIGHT/HEIGHT parameters, then merged to ADSL
# Confidence: 1.00
# CHECK: target variable must not be all-missing after the derivation
vs <- vs |>
  admiral::derive_param_computed(
    by_vars = exprs(STUDYID, USUBJID),
    parameters = c("WEIGHT", "HEIGHT"),
    set_values_to = exprs(AVAL = AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2, PARAMCD = "BMI", PARAM = "Body Mass Index (kg/m2)", AVALU = "kg/m2")
  )

# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BMIBLGR1 | step 2/2: merge_var ----
# Spec origin: "BMIBLGR1="<25" if . < BMIBL <25. BMIBLGR1="25-<30" if 25 <=BMIBL <30. BMIBLGR1=">=30"if BMIBL >=30."
# Agent rationale: rule: BMI formula from WEIGHT/HEIGHT parameters, then merged to ADSL
# Confidence: 1.00
# CHECK: merge must not duplicate rows (one record per subject in ADSL)
# CHECK: target variable must not be all-missing after the derivation
# CHECK: no `order` specified; confirm exactly one record per by_vars after the filter (otherwise selection is nondeterministic)
ADSL <- ADSL |>
  admiral::derive_vars_merged(
    dataset_add = vs,
    by_vars = exprs(STUDYID, USUBJID),
    mode = "first",
    new_vars = exprs(BMIBLGR1 = AVAL),
    filter_add = PARAMCD == 'BMI'
  )
