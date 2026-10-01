# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADY | NEEDS HUMAN REVIEW ----
# Spec origin: "LB.LBDY"
# Rationale: ADY maps to LB.LBDY, which is not present in the ADLBC base dataset; merge_var can pull it from lb keyed on STUDYID and USUBJID. However LBDY is not unique per subject (multiple lab records/analytes), so a by_vars of STUDYID/USUBJID alone loses the record-level linkage. A merged join may need additional keys (PARAMCD, VISITNUM) or ADY should be derived from ADT relative to TRTSDT; the correct record linkage requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
