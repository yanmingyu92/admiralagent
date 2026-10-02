# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADURU | NEEDS HUMAN REVIEW ----
# Spec origin: "If ADURN is not missing then ADURU='DAYS'"
# Rationale: Condition 'ADURN is not missing' tests missingness of a numeric column, which the filter sublanguage cannot express (no is.na/style checks; ADURN != '' is not a valid missingness test for numerics). Needs human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
