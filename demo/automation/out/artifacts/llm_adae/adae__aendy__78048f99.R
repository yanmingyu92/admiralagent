# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AENDY | NEEDS HUMAN REVIEW ----
# Spec origin: "IF AENDT>=TRTSDT>MISSING then AENDY=AENDT-TRTSDT+1 Else if TRTSDT>AENDT>MISSING then AENDY=AENDT-TRTSDT"
# Rationale: Conditional derivation (sign depends on relative order of AENDT and TRTSDT); cannot be fully represented by a single arithmetic formula, requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
