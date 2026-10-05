# Normalize spec data frame

Validates that a flat (already parsed) spec data frame carries the
required columns, fills optional columns (\`length\`, \`codelist\`,
\`source_dataset\`, \`source_variable\`, \`order\`) with \`NA\` when
absent, and defactors all columns. This is the canonical in-memory spec
format all downstream functions accept.

## Usage

``` r
read_spec_df(df)
```

## Arguments

- df:

  data.frame with columns dataset, variable, label, type, origin,
  derivation.

## Value

The normalized data frame (error when required columns are missing).

## Details

Normalize a flat spec data frame
