# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ANL01FL | NEEDS HUMAN REVIEW ----
# Spec origin: "If ALBTRVAL = max(ALBTRVAL) then ANL01FL is 'Y'"
# Rationale: ANL01FL flags the record where ALBTRVAL equals its maximum within subject/analyte; extreme_flag with order on ALBTRVAL and mode 'last' approximates max. However the exact grouping (which PARAMCD/visit scope) and the precise ALBTRVAL producer dependency are ambiguous, warranting human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
