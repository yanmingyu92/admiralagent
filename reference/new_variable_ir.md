# New variable IR

Builds the intermediate representation for one spec variable: dataset,
variable name, ordered \[new_step()\] pipeline, plus provenance fields
(verbatim spec text, confidence, review flag, rationale).

## Usage

``` r
new_variable_ir(
  dataset,
  variable,
  steps = list(),
  spec_origin = NA_character_,
  confidence = 1,
  needs_human = FALSE,
  rationale = NA_character_
)
```

## Arguments

- dataset:

  Dataset the variable belongs to (e.g. \`"ADSL"\`).

- variable:

  Variable name (e.g. \`"TRTSDTM"\`).

- steps:

  List of \`aa_step\` objects in execution order.

- spec_origin:

  Verbatim derivation text from the spec.

- confidence:

  Classifier confidence in \`\[0, 1\]\`.

- needs_human:

  Logical; \`TRUE\` routes the variable to human review instead of code
  generation.

- rationale:

  Free-text explanation of the chosen layer chain.

## Value

A list of class \`aa_variable_ir\`.

## Details

Construct a variable IR
