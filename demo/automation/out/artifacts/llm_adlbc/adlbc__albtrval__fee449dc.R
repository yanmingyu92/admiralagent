# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ALBTRVAL | NEEDS HUMAN REVIEW ----
# Spec origin: "Maximum of [LBSTRESN-(1.5*ULN)] and [(.5*LLN) - LBSTRESN]"
# Rationale: The derivation uses max() over two arithmetic expressions of LBSTRESN with ULN/LLN constants; max() is a function call not allowed in the compute_var sublanguage, and ULN/LLN reference columns are ambiguous, so human review is required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
