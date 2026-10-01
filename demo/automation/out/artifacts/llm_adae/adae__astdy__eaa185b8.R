# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDY | NEEDS HUMAN REVIEW ----
# Spec origin: "IF ASTDT>=TRTSDT>MISSING then ASTDY=ASTDT-TRTSDT+1 Else if TRTSDT>ASTDT>MISSING then ASTDY=ASTDT-TRTSDT"
# Rationale: ASTDY is a conditional study-day computation (ASTDT>=TRTSDT then ASTDT-TRTSDT+1 else ASTDT-TRTSDT). The compute_var layer allows arithmetic and grouping parentheses only, so the conditional/missing-value guarded logic cannot be expressed with the allowed vocabulary. Human review required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
