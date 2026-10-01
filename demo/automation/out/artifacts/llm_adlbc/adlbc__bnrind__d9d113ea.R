# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- BNRIND | NEEDS HUMAN REVIEW ----
# Spec origin: "if BASE < [0.5*LBSTNRLO) then ANRIND = 'Y' else if BASE > [0.5*LBSTRNHI),'H','N'"
# Rationale: BNRIND requires an element-wise conditional comparing BASE against 0.5*LBSTNRLO and 0.5*LBSTNRHI with multiple output levels. No supported layer performs conditional/case categorization, and the range-limit source from lb lacks defined record-level keys. Human review required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
