---
name: spec-to-adam
description: Generate or extend an ADaM dataset (ADSL, ADVS) from a P21-style spec and SDTM data using admiralagent. Use when translating spec derivations into admiral code, generating draft ADaM programs per variable, or validating generated ADaM code. Triggers on "admiralagent", "spec to ADaM", "ADSL program", "ADaM derivation", "derive_vars_merged", "derive_vars_dtm", "spec_to_metacore".
---

# Spec-to-ADaM via admiralagent

Turn a spec into draft admiral code deterministically. Never hand-write admiral
calls for spec derivations when this pipeline can emit them with provenance.

## When to use

Building or extending an ADaM dataset from a spec (xlsx via metacore, or a flat
data frame), one variable at a time, with validation comments and sidecars.

## Workflow

1. Read the spec:
   - flat data frame: `spec <- admiralagent::read_spec_df(df)`
   - P21 xlsx: `spec <- admiralagent::read_spec(path)` (needs metacore + readxl)
2. Classify each variable into layer IR:
   - baseline/fallback: `ir <- admiralagent::classify_variables(spec, "ADSL", backend = "rules")`
   - LLM upgrade: `ir <- admiralagent::classify_variables(spec, "ADSL", backend = "llm", chat = chat)`
3. Gate: `admiralagent::validate_ir(ir)` must return `character(0)`; never
   proceed with invalid IR, never "fix" IR by hand-editing generated code.
4. Render: `cat(admiralagent::render_program(ir))` — draft script with
   `# CHECK` comments and a mandatory review disclaimer.
5. Write artifacts + sidecars: `admiralagent::write_program_artifact(ir, dir = "gen")`
6. After a human executes/adjusts the script, run
   `admiralagent::run_validation(data, ir)` and record results.

## Hard rules

- LLM output is JSON layer IR only; R code comes exclusively from
  `render_*()`. If asked to write admiral code directly, refuse and use the
  pipeline.
- Variables with `needs_human = TRUE` get no code; surface them to the user
  with their rationale instead of inventing a rule.
- Generated code is a starting point: a human must verify assumptions before
  submission readiness.
