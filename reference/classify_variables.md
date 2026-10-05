# Classify spec variables

Translates each spec variable's free-text derivation into a variable IR
using the selected backend: \`"rules"\` runs the built-in deterministic,
zero-dependency keyword classifier (baseline and fallback); \`"llm"\`
runs the structured-extraction pipeline via \[classify_variables_llm()\]
(requires an ellmer \`chat\`).

## Usage

``` r
classify_variables(
  spec,
  dataset,
  backend = c("rules", "llm"),
  chat = NULL,
  samples = 1,
  consensus = c("majority", "first"),
  prompt_variant = c("full", "neutral", "minimal")
)
```

## Arguments

- spec:

  Spec data frame compatible with \[read_spec_df()\].

- dataset:

  Dataset name to classify (e.g. \`"ADSL"\`).

- backend:

  One of \`"rules"\` or \`"llm"\`.

- chat:

  ellmer chat object; required when \`backend = "llm"\`, ignored
  otherwise.

- samples:

  Number of independent LLM pipeline runs; used when \`backend =
  "llm"\`, ignored otherwise. See \[classify_variables_llm()\].

- consensus:

  Voting strategy across samples; used when \`backend = "llm"\`, ignored
  otherwise. See \[classify_variables_llm()\].

- prompt_variant:

  System prompt variant; used when \`backend = "llm"\`, ignored
  otherwise. See \[classify_variables_llm()\].

## Value

List of \`aa_variable_ir\` objects, one per spec variable.

## Details

Classify spec variables into layer IR
