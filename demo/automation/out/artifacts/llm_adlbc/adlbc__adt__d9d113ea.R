# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ADT | NEEDS HUMAN REVIEW ----
# Spec origin: "LB.LBDTC"
# Rationale: ADT maps to LB.LBDTC, a character --DTC not present in the ADLBC base dataset. LBDTC is a character date-time needing imputation into a numeric ADT; a simple merge_var would not convert the character DTC to a numeric date, and the record-level linkage across multiple lab records needs additional keys. Correct handling (impute LB.LBDTC then merge, or use the LB record carried into ADLBC) requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
