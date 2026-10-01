# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ALBTRVAL | NEEDS HUMAN REVIEW ----
# Spec origin: "Maximum of [LBSTRESN-(1.5*ULN)] and [(.5*LLN) - LBSTRESN]"
# Rationale: ALBTRVAL requires (1) LBSTRESN, ULN and LLN pulled per lab record from lb (record-level linkage undefined), and (2) an element-wise max of two computed expressions, which no supported layer performs (compute_var is single-target arithmetic without max()). Human review required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
