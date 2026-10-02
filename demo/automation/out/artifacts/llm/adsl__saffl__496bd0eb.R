# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- SAFFL | NEEDS HUMAN REVIEW ----
# Spec origin: "Y if ITTFL='Y' and TRTSDT ne missing. N otherwise"
# Rationale: Condition requires a missingness check (TRTSDT ne missing) and setting 'N' otherwise; the filter sublanguage cannot express is.na()-style missingness checks, so this must be routed to human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
