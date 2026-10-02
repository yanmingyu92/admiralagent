# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AENDY | NEEDS HUMAN REVIEW ----
# Spec origin: "IF AENDT>=TRTSDT>MISSING then AENDY=AENDT-TRTSDT+1 Else if TRTSDT>AENDT>MISSING then AENDY=AENDT-TRTSDT"
# Rationale: AENDY uses a conditional day-relative formula with two branches (AENDT>=TRTSDT gives +1 inclusive, TRTSDT>AENDT gives exclusive). This mixed inclusive/exclusive conditional arithmetic cannot be expressed by compute_var nor by assign_conditional. Needs human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
