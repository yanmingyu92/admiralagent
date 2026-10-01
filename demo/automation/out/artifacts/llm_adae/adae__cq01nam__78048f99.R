# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CQ01NAM | NEEDS HUMAN REVIEW ----
# Spec origin: "If AEDECOD contains any of the character strings of ('APPLICATION', 'DERMATITIS', 'ERYTHEMA', 'BLISTER') OR if AEBODSYS='SKIN AND SUBC UTANEOUS TISSUE DISORDERS' but AEDECOD is not in ('COLD SWEAT', 'HYPERHIDROSIS', 'ALOPECIA') then CQ01NAM='DERMATOLOGIC EVENTS' Otherwise CQ01NAM=NULL"
# Rationale: Derivation uses character-string containment matching (contains) with OR/NOT logic and NULL default; the vocabulary lacks a conditional string-matching layer, so it requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
