# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CQ01NAM | NEEDS HUMAN REVIEW ----
# Spec origin: "If AEDECOD contains any of the character strings of ('APPLICATION', 'DERMATITIS', 'ERYTHEMA', 'BLISTER') OR if AEBODSYS='SKIN AND SUBC UTANEOUS TISSUE DISORDERS' but AEDECOD is not in ('COLD SWEAT', 'HYPERHIDROSIS', 'ALOPECIA') then CQ01NAM='DERMATOLOGIC EVENTS' Otherwise CQ01NAM=NULL"
# Rationale: The derivation is a complex conditional with substring matching (contains any of a list) and negated set membership, plus a NULL otherwise value. This requires function calls (grepl, %in%) and conditional logic that the IR layers cannot express. Requires human review.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
