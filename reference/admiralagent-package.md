# admiralagent: Spec-Driven ADaM Code Generation with LLM-Translated Layers

Translates Pinnacle 21 (P21)-style ADaM (Analysis Data Model)
specifications into executable 'admiral' code with validation comments.
An LLM (large language model, optional, via 'ellmer') maps each spec
variable's free-text derivation onto a closed vocabulary of derivation
layers (a structured JSON intermediate representation (IR)); a
deterministic compiler renders the IR into 'admiral'/'metatools' code
with 'CHECK' validation comments and writes provenance sidecars. Ships
with a zero-dependency rule-based classifier as baseline and fallback;
the LLM never writes R code directly and all model output is validated
against the closed vocabulary before use. The specification structure
follows the CDISC (Clinical Data Interchange Standards Consortium)
Analysis Data Model standard
<https://www.cdisc.org/standards/foundational/adam>.

## See also

Useful links:

- <https://github.com/yanmingyu92/admiralagent>

- Report bugs at <https://github.com/yanmingyu92/admiralagent/issues>

## Author

**Maintainer**: Jaime Yan <yanmingyunmt@gmail.com>

Authors:

- Jaime Yan <yanmingyunmt@gmail.com>
