# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDTF | NEEDS HUMAN REVIEW ----
# Spec origin: "ASTDTF='D' if the day value within the character date is imputed. Note that only day values needed to be imputed for this study."
# Rationale: ASTDTF must be 'D' only when the day component of AESTDTC was actually imputed, which requires detecting a partial (day-missing) date. This condition depends on the imputation flag produced by derive_vars_dtm, which cannot be expressed in the filter sublanguage here. Needs human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
