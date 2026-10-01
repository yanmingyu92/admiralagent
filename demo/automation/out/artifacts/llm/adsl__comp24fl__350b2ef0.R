# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- COMP24FL | NEEDS HUMAN REVIEW ----
# Spec origin: "Y if subject has a SV.VISITNUM=12 and ENDDT>= date of visit 12 , N otherwise"
# Rationale: Conditional flag requiring SV.VISITNUM=12 record and comparison of ENDDT to visit 12 date; external date lookups and conditional logic not expressible with allowed operations.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
