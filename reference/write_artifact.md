# Write variable artifacts

Writes one \`\<dataset\>\_\_\<variable\>\_\_\<hash8\>.R\` artifact per
variable (rendered code with CHECK comments) plus a JSON sidecar
recording the IR, backend, model, validation result, and disclaimer.
Same IR overwrites the same files; copies never accumulate.

## Usage

``` r
write_artifact(
  ir,
  dir = "gen",
  backend_label = "rules",
  model = NULL,
  validation = NULL
)
```

## Arguments

- ir:

  List of \`aa_variable_ir\` objects.

- dir:

  Output directory (created when missing).

- backend_label:

  Backend label recorded in sidecars.

- model:

  Model identifier recorded in sidecars (LLM backend).

- validation:

  Optional validation result recorded in sidecars.

## Value

Invisibly, the character vector of files written.

## Details

Write per-variable artifacts and sidecars
