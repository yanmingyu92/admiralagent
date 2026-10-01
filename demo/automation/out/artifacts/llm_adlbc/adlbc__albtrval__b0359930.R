# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ALBTRVAL | NEEDS HUMAN REVIEW ----
# Spec origin: "Maximum of [LBSTRESN-(1.5*ULN)] and [(.5*LLN) - LBSTRESN]"
# Rationale: ALBTRVAL requires max() over two arithmetic expressions involving LBSTRESN, ULN and LLN; function calls are rejected by compute_var and the layer vocabulary cannot express this, requiring human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
