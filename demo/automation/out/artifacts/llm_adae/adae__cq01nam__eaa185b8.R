# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CQ01NAM | NEEDS HUMAN REVIEW ----
# Spec origin: "If AEDECOD contains any of the character strings of ('APPLICATION', 'DERMATITIS', 'ERYTHEMA', 'BLISTER') OR if AEBODSYS='SKIN AND SUBC UTANEOUS TISSUE DISORDERS' but AEDECOD is not in ('COLD SWEAT', 'HYPERHIDROSIS', 'ALOPECIA') then CQ01NAM='DERMATOLOGIC EVENTS' Otherwise CQ01NAM=NULL"
# Rationale: CQ01NAM requires a multi-condition string-matching rule (contains any of a list of substrings, OR SOC match with an excluded PT list). Substring/contains matching and the compound conditional with NULL default are not expressible with the allowed layers and formula vocabulary. Human review required.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
