# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDTF | NEEDS HUMAN REVIEW ----
# Spec origin: "ASTDTF='D' if the day value within the character date is imputed. Note that only day values needed to be imputed for this study."
# Rationale: ASTDTF is the imputation flag produced by admiral::derive_vars_dtm with flag columns during the same imputation that creates ASTDT. The IR impute_dtc layer does not expose a flag target argument, so the exact flag column production cannot be expressed; requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
