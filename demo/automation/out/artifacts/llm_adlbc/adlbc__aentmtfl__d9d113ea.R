# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AENTMTFL | NEEDS HUMAN REVIEW ----
# Spec origin: "Last observed value for this lab parameter during treatment phase: 'Y' if VISITNUM=12, if subject discontinues prior to VISIT 12, then this variable is set to 'Y' if this is the last assessment of this analyte for the subject"
# Rationale: AENTMTFL derivation mixes VISITNUM=12 logic with a last-observed-analyte rule; the conflict and the undefined last-assessment logic across analytes require human decision, and no single supported layer captures it.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
