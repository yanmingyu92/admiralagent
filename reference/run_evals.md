# Run the spec-to-IR classification evals

Executes every corpus case for one dataset: builds a one-row spec data
frame per case, classifies it with \[classify_variables()\], and
compares the produced step-layer sequence (\`"needs_human"\` when the
classifier abstains) against the expected sequence. Prints a summary and
returns the per-case results invisibly. This is the package's
production-consistency regression gate: the \`rules\` backend must score
accuracy 1.0 against the corpus.

## Usage

``` r
run_evals(backend = c("rules", "llm"), chat = NULL, dataset = "ADSL")
```

## Arguments

- backend:

  Classifier backend, \`"rules"\` (default, deterministic, offline) or
  \`"llm"\` (requires \`chat\`).

- chat:

  ellmer chat object; required when \`backend = "llm"\`, ignored
  otherwise.

- dataset:

  Dataset tag of the corpus cases to run (default \`"ADSL"\`).

## Value

A data.frame (invisibly) with columns \`id\`, \`variable\`,
\`expected\`, \`got\`, \`ok\`.
