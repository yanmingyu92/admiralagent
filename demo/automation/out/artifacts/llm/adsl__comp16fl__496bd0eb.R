# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- COMP16FL | NEEDS HUMAN REVIEW ----
# Spec origin: "Y if subject has a SV.VISITNUM=10 and ENDDT>=date of visit 10, N otherwise"
# Rationale: Requires existence of a SV record at VISITNUM=10 plus comparison of an ENDDT (not in spec) against the visit 10 date pulled from SV. The ENDDT source and visit-date merge are ambiguous; human review required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
