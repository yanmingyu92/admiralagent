# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- ANRIND | NEEDS HUMAN REVIEW ----
# Spec origin: "if AVAL < [0.5*LBSTNRLO) then ANRIND = 'Y' else if AVAL > [0.5*LBSTRNHI),'H','N'"
# Rationale: LLM batch failed IR validation after max_attempts; recorded as needs_human by the demo fallback (see telemetry).
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
