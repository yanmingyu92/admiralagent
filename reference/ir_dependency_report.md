# IR dependency report

Audits every step's consumed references (duration endpoints, assign
sources, compute_param/summary_record PARAMCD/AVAL expectations) against
columns produced by earlier executable steps or whitelisted via
\`known_columns\`, and lists everything unresolved.

## Usage

``` r
ir_dependency_report(ir, known_columns = character())
```

## Arguments

- ir:

  List of \`aa_variable_ir\` objects.

- known_columns:

  Character vector of column names assumed to pre-exist in the source
  data.

## Value

A data.frame with columns \`variable\`, \`input\`, \`dataset\`,
\`issue\` (zero rows when every input resolves).

## Details

Report undefined step inputs in an IR
