# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BMIBLGR1 | step 1/1: categorize ----
# Spec origin: "BMIBLGR1="<25" if . < BMIBL <25. BMIBLGR1="25-<30" if 25 <=BMIBL <30. BMIBLGR1=">=30"if BMIBL >=30."
# Agent rationale: BMIBLGR1 groups: <25, 25-<30, >=30; intervals left-closed (right=FALSE) to match 25<=BMIBL<30 and BMIBL>=30 semantics.
# Confidence: 0.70
# CHECK: target variable must not be all-missing after the derivation
# CHECK: derived values must be a subset of the spec codelist (verify vs metacore)
ADSL <- ADSL |>
  dplyr::mutate(
    BMIBLGR1 = cut(
      BMIBL,
      breaks = c(0, 25, 30, Inf),
      labels = c("<25", "25-<30", ">=30"),
      right = FALSE,
      include.lowest = TRUE
    )
  )
# CHECK: human must confirm breakpoints and labels before use
