# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTEDT | NEEDS HUMAN REVIEW ----
# Spec origin: "The date of final dose (from the CRF) is EX.EXENDTC on the subject's last EX record. If the date of final dose is missing for the subject and the subject discontinued after visit 3, use the date of discontinuation as the date of last dose. Convert the date to a SAS date."
# Rationale: TRTEDT is the final dose date (EX.EXENDTC on the last EX record), with a conditional fallback to the discontinuation date when the final dose date is missing and the subject discontinued after visit 3. The fallback branch requires a human decision on the discontinuation date source and condition.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
