# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ASTDY | NEEDS HUMAN REVIEW ----
# Spec origin: "IF ASTDT>=TRTSDT>MISSING then ASTDY=ASTDT-TRTSDT+1 Else if TRTSDT>ASTDT>MISSING then ASTDY=ASTDT-TRTSDT"
# Rationale: ASTDY uses a conditional day-relative formula with two branches (ASTDT>=TRTSDT gives +1 inclusive, TRTSDT>ASTDT gives exclusive). This mixed inclusive/exclusive conditional arithmetic cannot be expressed by compute_var (which requires a single expression with no conditionals) nor by assign_conditional. Needs human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
