# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDY | NEEDS HUMAN REVIEW ----
# Spec origin: "IF ASTDT>=TRTSDT>MISSING then ASTDY=ASTDT-TRTSDT+1 Else if TRTSDT>ASTDT>MISSING then ASTDY=ASTDT-TRTSDT"
# Rationale: Derivation is conditional (sign depends on relative order of ASTDT and TRTSDT); cannot be fully represented by a single arithmetic formula, requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
