# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AENDT | NEEDS HUMAN REVIEW ----
# Spec origin: "AE.AEENDTC, converted to a numeric SAS date"
# Rationale: AENDT is derived from AE.AEENDTC. The spec text does not state an imputation rule for partial end dates, whereas impute_dtc requires an explicit highest_imputation and date_imputation. A conservative 'first' day imputation is assumed but is not confirmed by the spec, so human review is required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
