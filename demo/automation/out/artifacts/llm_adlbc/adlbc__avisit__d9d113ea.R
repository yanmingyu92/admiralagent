# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- AVISIT | NEEDS HUMAN REVIEW ----
# Spec origin: "Last observed value for this lab parameter during treatment phase: 'Y' if VISITNUM=12, if subject discontinues prior to VISIT 12, then this variable is set to 'Y' if this is the last assessment of this analyte for the subject"
# Rationale: The derivation for AVISIT is internally inconsistent: the label is Analysis Visit (a text visit name) but the rule text describes a flag-style rule producing 'Y' based on VISITNUM=12 or last-observed-analyte logic. Determining the intended AVISIT values, the visit mapping, and the last-assessment logic requires human decision; no supported layer captures this.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
