# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AENDY | NEEDS HUMAN REVIEW ----
# Spec origin: "IF AENDT>=TRTSDT>MISSING then AENDY=AENDT-TRTSDT+1 Else if TRTSDT>AENDT>MISSING then AENDY=AENDT-TRTSDT"
# Rationale: AENDY is a conditional study-day computation (AENDT>=TRTSDT then AENDT-TRTSDT+1 else AENDT-TRTSDT). The compute_var layer allows arithmetic and grouping parentheses only, so the conditional/missing-value guarded logic cannot be expressed with the allowed vocabulary. Human review required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
