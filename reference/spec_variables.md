# Spec rows for a dataset

Subsets a spec data frame to the rows of one dataset.

## Usage

``` r
spec_variables(spec, dataset)
```

## Arguments

- spec:

  Spec data.frame compatible with \[read_spec_df()\].

- dataset:

  Dataset name to subset to (e.g. \`"ADSL"\`).

## Value

The subset spec data frame; errors when no rows match.

## Details

Extract one dataset's spec rows
