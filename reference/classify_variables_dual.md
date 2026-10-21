# Dual-backend consensus classification

Runs the deterministic rules classifier and the LLM pipeline
independently on the same spec, then compares the two translations per
variable at \`ir_fingerprint(level = "full")\` - complete canonical
semantics, with registry defaults filled and intermediate names
alpha-renamed, so a rule's \`EXST_TRTSDTM\` temp and an LLM's
\`EXSTDTM\` compare equal when the derivation means the same thing.

Agreement adopts the rules IR (deterministic precedence; the semantics
are identical anyway). Any divergence - different canonical semantics,
or exactly one side abstaining - escalates the variable to
\`needs_human\` with a rationale naming both layer chains. No side is
ever silently preferred: a dual run never derives a variable that a
rules-only run would have refused, and never accepts an LLM answer the
rules disagreed with. Agreement is corroboration, not proof of
correctness.

## Usage

``` r
classify_variables_dual(
  spec,
  dataset,
  chat,
  samples = 1,
  prompt_variant = c("full", "neutral", "minimal")
)
```

## Arguments

- spec:

  Spec data frame compatible with \[read_spec_df()\].

- dataset:

  Dataset name to classify (e.g. \`"ADSL"\`).

- chat:

  ellmer chat object (or any object with a \`chat(prompt)\` method) for
  the LLM side.

- samples:

  Number of independent LLM pipeline runs, passed to
  \[classify_variables_llm()\]; \`\> 1\` gives the LLM side its own
  internal majority vote before the cross-backend comparison.

- prompt_variant:

  System prompt variant for the LLM side; see
  \[classify_variables_llm()\].

## Value

List of \`aa_variable_ir\` objects, one per spec variable, with two
attributes: \`dual\`, a data.frame with columns \`variable\`, \`class\`
(\`agree\`, \`disagree\`, \`rules_abstain\`, \`llm_abstain\`),
\`rules_fp\`, \`llm_fp\` (full fingerprints), \`rules_layers\`,
\`llm_layers\` (layer chains), and \`llm_suggestion\` (whether the LLM
side produced a candidate the reviewer can inspect); \`agreement_rate\`,
the fraction of variables where both backends produced the same
canonical semantics; and \`llm_candidates\`, a named list holding the
LLM-side IR for every escalated variable that has one (the reviewer's
starting point; never rendered or executed without a human decision).

## Details

Classify spec variables with two independent backends

## Examples

``` r
if (FALSE) { # \dontrun{
# Not executable without an LLM provider API key (ellmer chat object):
chat <- ellmer::chat_deepseek(model = "deepseek-chat")
ir <- classify_variables_dual(mock_spec_adsl(), "ADSL", chat)
dual_disagreements(ir) # review queue: every variable the backends split on
} # }
```
