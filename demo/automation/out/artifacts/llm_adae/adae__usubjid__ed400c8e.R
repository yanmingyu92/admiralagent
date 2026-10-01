# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- USUBJID | NEEDS HUMAN REVIEW ----
# Spec origin: "Copied directly from ADSL.USUBJID"
# Rationale: USUBJID is the merge key itself; it cannot be brought in by a merge keyed on USUBJID without creating a cyclic dependency. It must already exist in the ADAE base dataset, so a direct copy is not expressible without a source column. Requires human review of how USUBJID enters ADAE.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
