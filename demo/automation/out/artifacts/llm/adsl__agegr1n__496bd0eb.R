# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AGEGR1N | NEEDS HUMAN REVIEW ----
# Spec origin: "AGEGR1 = 1 if AGE <65. AGEGR1 = 2 if AGE 65-80. AGEGR1 = 3 if AGE >80."
# Rationale: AGE <65 -> 1, AGE 65-80 -> 2, AGE >80 -> 3. Numeric output with character labels serialized as strings; the exact breakpoint boundaries (whether 65 and 80 are inclusive) and the fact that a codelist mapping is expected rather than cut() make the encoding uncertain. Human review recommended to confirm interval semantics and label type.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
