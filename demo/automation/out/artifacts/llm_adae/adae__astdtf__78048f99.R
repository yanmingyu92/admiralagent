# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDTF | NEEDS HUMAN REVIEW ----
# Spec origin: "ASTDTF='D' if the day value within the character date is imputed. Note that only day values needed to be imputed for this study."
# Rationale: ASTDTF is produced by the impute_dtc step as a flag column; it cannot be derived by a plain assignment. A dedicated flag-derivation layer is not available in the vocabulary, so this requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
