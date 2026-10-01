# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- TRTEDT | NEEDS HUMAN REVIEW ----
# Spec origin: "The date of final dose (from the CRF) is EX.EXENDTC on the subject's last EX record. If the date of final dose is missing for the subject and the subject discontinued after visit 3, use the date of discontinuation as the date of last dose. Convert the date to a SAS date."
# Rationale: Derivation contains a conditional fallback (missing final dose -> discontinuation date) requiring conditional selection logic and external CRF/DS references; ambiguous and human-only.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
