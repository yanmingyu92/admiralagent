# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ANL01FL | NEEDS HUMAN REVIEW ----
# Spec origin: "If ALBTRVAL = max(ALBTRVAL) then ANL01FL is 'Y'"
# Rationale: The rule flags the record where ALBTRVAL equals its maximum (max(ALBTRVAL)); extreme_flag with mode=last on AVAL approximates this but max() selection semantics and the exact by_vars grouping are not specified, so human review is required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
