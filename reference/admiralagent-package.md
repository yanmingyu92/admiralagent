# admiralagent: Spec-Driven ADaM Code Generation with LLM-Translated Layers

Translates P21-style ADaM specifications into executable admiral code
with validation comments. An LLM (optional, via ellmer) maps each spec
variable's free-text derivation onto a closed vocabulary of derivation
layers (structured JSON IR); a deterministic compiler renders the IR
into admiral/metatools code with 'CHECK' validation comments and writes
provenance sidecars. Ships with a zero-dependency rule-based classifier
as baseline and fallback.

## See also

Useful links:

- <https://github.com/yanmingyu92/admiralagent>

- Report bugs at <https://github.com/yanmingyu92/admiralagent/issues>

## Author

**Maintainer**: Jaime Yan <yanmingyu92@users.noreply.github.com>

Authors:

- Jaime Yan <yanmingyu92@users.noreply.github.com>
