# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDTF | NEEDS HUMAN REVIEW ----
# Spec origin: "ASTDTF='D' if the day value within the character date is imputed. Note that only day values needed to be imputed for this study."
# Rationale: ASTDTF is the day-imputation flag ('D') produced by the impute_dtc call that creates ASTDT; it is not independently derivable without that producer and its presence depends on day imputation, so it is flagged for human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
