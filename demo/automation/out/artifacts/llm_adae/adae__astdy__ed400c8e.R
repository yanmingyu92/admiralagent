# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDY | NEEDS HUMAN REVIEW ----
# Spec origin: "IF ASTDT>=TRTSDT>MISSING then ASTDY=ASTDT-TRTSDT+1 Else if TRTSDT>ASTDT>MISSING then ASTDY=ASTDT-TRTSDT"
# Rationale: The derivation is a conditional (IF/ELSE IF) with MISSING checks that maps to a piecewise expression requiring function calls, which compute_var rejects. Cannot be expressed in the IR; requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
