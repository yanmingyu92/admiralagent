# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ANRIND | NEEDS HUMAN REVIEW ----
# Spec origin: "if AVAL < [0.5*LBSTNRLO) then ANRIND = 'Y' else if AVAL > [0.5*LBSTRNHI),'H','N'"
# Rationale: ANRIND requires an element-wise conditional comparing AVAL against 0.5*LBSTNRLO and 0.5*LBSTNRHI with multiple output levels ('Y'/'H'/'N'). No supported layer performs conditional/case categorization (categorize is numeric breakpoints only), the expressions contain scalar multiplications of pulled columns, and the range-limit source from lb lacks defined record-level keys. Human review required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
