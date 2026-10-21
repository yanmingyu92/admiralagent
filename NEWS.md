# admiralagent 0.1.1

CRAN resubmission: addresses the first-review comments and folds in the
post-0.1.0 development features.

- Description now expands all acronyms (ADaM, LLM, IR, P21, CDISC) and
  references the CDISC Analysis Data Model standard.
- Removed the example from the unexported `parse_define()`; every exported
  function now carries a small executable example (LLM- and MCP-server-only
  functions keep `\dontrun{}` with the reason stated: provider API key or
  blocking stdio server).
- `write_artifact()` / `write_program_artifact()` no longer default `dir`:
  an explicit output directory is required, so no function writes into the
  user's working directory by default; examples and tests write to
  `tempdir()`.
- Removed the remaining `<<-` assignments (closure accumulators rewritten
  over explicit local environments; no behaviour change, full test suite
  green).
- New `accept_model()`: model+harness acceptance gate. A candidate LLM runs
  the spec-to-IR regression corpus and is cross-compared against the rules
  baseline at full canonical semantics; both thresholds are required
  arguments (acceptance criteria must be prespecified), any pipeline error
  rejects the candidate, and the decision is logged as a digest-only
  `model_acceptance` audit event.
- New `routing_plan()`: derives the execution routing directly from spec
  lineage — topological waves, per-variable dependencies, and the two
  fail-closed lanes (cycle-blocked and human-routed variables stay waveless).
  The ordering is computed, not declared, replacing a hand-registered
  process DAG.
- New `classify_variables_dual()`: runs the rules classifier and the LLM
  pipeline independently on the same spec, compares the two translations
  per variable at full canonical semantics (`ir_fingerprint(level = "full")`),
  adopts the rules IR on agreement, and escalates any divergence
  (`disagree` / `rules_abstain` / `llm_abstain`) to `needs_human` — no
  side is ever silently preferred. The decision is recorded as a
  digest-only `dual_consensus` audit event; `dual_disagreements()`
  extracts the human review queue.

# admiralagent 0.1.0

Initial release.

- Translate P21-style ADaM specifications into layer IR over a closed
  vocabulary, then deterministically compile the IR into
  admiral/metatools programs with `# CHECK:` validation comments and
  provenance sidecars (`classify_variables()`, `render_program()`,
  `write_artifact()`).
- Zero-dependency rules classifier (`backend = "rules"`) as the default
  baseline; optional LLM translation (`backend = "llm"`, via 'ellmer')
  emits IR only — the LLM never writes R code and every model response
  is validated against the closed vocabulary before use.
- Sandbox gate for executing generated programs, hash-chained audit
  log, dataset-JSON reader, define.xml (2.0) metadata reader, and
  dependency/impact reporting across ADaM datasets.
- Study-level drivers: `execute_one()`, `execute_study()` with
  derivation ordering, gates, and manifest generation.
