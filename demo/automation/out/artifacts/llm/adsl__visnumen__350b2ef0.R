# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- VISNUMEN | NEEDS HUMAN REVIEW ----
# Spec origin: "if DS.VISITNUM=13 where DSTERM='PROTCOL COMPLETED' then VISNUMEN=12, otherwise VISNUMEN=DS.VISITNUM where DSTERM='PROTCOL COMPLETED'"
# Rationale: Conditional derivation (VISITNUM=13 remapped to 12, else DS.VISITNUM) with DSTERM filter; branching conditional logic not expressible with allowed operations.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
