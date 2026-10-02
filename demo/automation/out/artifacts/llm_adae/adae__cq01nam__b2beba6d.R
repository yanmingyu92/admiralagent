# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CQ01NAM | NEEDS HUMAN REVIEW ----
# Spec origin: "If AEDECOD contains any of the character strings of ('APPLICATION', 'DERMATITIS', 'ERYTHEMA', 'BLISTER') OR if AEBODSYS='SKIN AND SUBC UTANEOUS TISSUE DISORDERS' but AEDECOD is not in ('COLD SWEAT', 'HYPERHIDROSIS', 'ALOPECIA') then CQ01NAM='DERMATOLOGIC EVENTS' Otherwise CQ01NAM=NULL"
# Rationale: CQ01NAM requires substring matching (contains) of AEDECOD against a list of strings and negation against an exclusion list, neither expressible in the filter sublanguage (no function calls, no %in%). The within-'...' logic also cannot be encoded. Needs human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
