# Changelog

## admiralagent 0.1.0

Initial release.

- Translate P21-style ADaM specifications into layer IR over a closed
  vocabulary, then deterministically compile the IR into
  admiral/metatools programs with `# CHECK:` validation comments and
  provenance sidecars
  ([`classify_variables()`](https://yanmingyu92.github.io/admiralagent/reference/classify_variables.md),
  [`render_program()`](https://yanmingyu92.github.io/admiralagent/reference/render_program.md),
  [`write_artifact()`](https://yanmingyu92.github.io/admiralagent/reference/write_artifact.md)).
- Zero-dependency rules classifier (`backend = "rules"`) as the default
  baseline; optional LLM translation (`backend = "llm"`, via ‘ellmer’)
  emits IR only — the LLM never writes R code and every model response
  is validated against the closed vocabulary before use.
- Sandbox gate for executing generated programs, hash-chained audit log,
  dataset-JSON reader, define.xml (2.0) metadata reader, and
  dependency/impact reporting across ADaM datasets.
- Study-level drivers: `execute_one()`, `execute_study()` with
  derivation ordering, gates, and manifest generation.
