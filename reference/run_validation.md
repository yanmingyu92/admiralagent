# Run validation

Executes every check attached to each variable's layers against the
resulting dataset and reports PASS/FAIL/MANUAL per check.
\`needs_human\` variables report \`MANUAL\`. This is the deterministic
validation gate paired with generated code.

## Usage

``` r
run_validation(data, ir, quiet = FALSE)
```

## Arguments

- data:

  The analysis dataset produced by executing the rendered code.

- ir:

  List of \`aa_variable_ir\` objects used to derive \`data\`.

- quiet:

  If \`TRUE\` (default) the status table is not printed.

## Value

Invisibly, a data.frame with columns \`variable\`, \`check\`,
\`status\`, \`details\`.

## Details

Run deterministic validation checks on executed data
