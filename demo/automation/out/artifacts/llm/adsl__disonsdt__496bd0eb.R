# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- DISONSDT | NEEDS HUMAN REVIEW ----
# Spec origin: "MH.MHSTDTC where MHCAT='PRIMARY DIAGNOSIS' converted to SAS date"
# Rationale: Pull MHSTDTC from mh where MHCAT='PRIMARY DIAGNOSIS' as a character DTC requiring imputation; imputation policy (highest_imputation, date_imputation) is not stated in the spec, requiring human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
