# Validation comments

Collects the deduplicated \`# CHECK\` comment lines for every layer used
by the variable, drawn from the internal check registry.

## Usage

``` r
validation_comments(v)
```

## Arguments

- v:

  An \`aa_variable_ir\` object.

## Value

Character vector of \`# CHECK:\` lines (empty when no checks apply).

## Details

Validation comments for a variable IR
