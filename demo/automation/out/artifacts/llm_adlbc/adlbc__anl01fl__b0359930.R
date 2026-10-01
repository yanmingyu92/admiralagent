# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ANL01FL | NEEDS HUMAN REVIEW ----
# Spec origin: "If ALBTRVAL = max(ALBTRVAL) then ANL01FL is 'Y'"
# Rationale: ANL01FL is a max-value extreme flag on a non-standard analyte-specific variable (ALBTRVAL) with 'Y' true value; the flag logic could map to extreme_flag but the by_vars and analyte scoping are ambiguous, requiring human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
