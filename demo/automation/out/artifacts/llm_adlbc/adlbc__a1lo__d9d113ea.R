# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- A1LO | NEEDS HUMAN REVIEW ----
# Spec origin: "LB.LBSTNRLO"
# Rationale: A1LO is derived from LB.LBSTNRLO, a source-dataset BDS artifact, so it must be pulled with merge_var from lb. LBSTNRLO varies across a subject's many lab records, so STUDYID/USUBJID alone is ambiguous; correct per-record linkage keys (e.g. PARAMCD, VISITNUM) require human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
