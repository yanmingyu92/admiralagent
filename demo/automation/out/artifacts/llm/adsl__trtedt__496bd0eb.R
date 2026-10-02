# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTEDT | NEEDS HUMAN REVIEW ----
# Spec origin: "The date of final dose (from the CRF) is EX.EXENDTC on the subject's last EX record. If the date of final dose is missing for the subject and the subject discontinued after visit 3, use the date of discontinuation as the date of last dose. Convert the date to a SAS date."
# Rationale: Rule combines last EX record EXENDTC with a fallback to discontinuation date if missing; conditional fallback logic and source of discontinuation date are not fully specified, requiring human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
