# Classify spec variables via an LLM chat backend

Runs the batch translate-validate-retry pipeline. With \`samples \> 1\`
the pipeline is repeated and per-variable signatures (step-layer chains)
are voted on to counter LLM output variance.

## Usage

``` r
classify_variables_llm(
  vars,
  chat,
  max_attempts = 2,
  batch_size = 4,
  samples = 1,
  consensus = c("majority", "first"),
  prompt_variant = c("full", "neutral", "minimal")
)
```

## Arguments

- vars:

  spec data frame from \[read_spec_df()\].

- chat:

  ellmer chat object (or any object with a \`chat(prompt)\` method).

- max_attempts:

  validation-repair attempts per batch.

- batch_size:

  variables per LLM batch.

- samples:

  number of independent pipeline runs; \`1\` (default) keeps the classic
  single-run behavior; \`\> 1\` enables consensus mode.

- consensus:

  \`majority\` = per-variable majority vote across samples; ties or
  all-failed samples mark the variable \`needs_human\`. \`first\` = skip
  voting and take the earliest successful sample.

- prompt_variant:

  system-prompt variant: \`full\` (default) carries the complete
  convention block; \`neutral\` and \`minimal\` strip it down for
  agreement measurement, so consensus reflects independent translations
  rather than prompt compliance.

## Value

List of \`aa_variable_ir\` objects. For \`samples \> 1\` the list
carries a \`consensus\` attribute: a data.frame with columns
\`variable\`, \`signature_votes\` (e.g. \`"impute_dtc-\>merge_var:2"\`),
\`chosen\`, \`unanimous\`.
