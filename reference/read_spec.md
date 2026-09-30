# Read spec workbook

Parses a specifications.xlsx-style workbook via
\[metacore::spec_to_metacore()\] and flattens the result into the
package's spec data frame format. Requires the \`metacore\` and
\`readxl\` packages.

## Usage

``` r
read_spec(
  path,
  dataset = NULL,
  where_sep_sheet = "Datasets",
  verbose = "silent"
)
```

## Arguments

- path:

  Path to the specification workbook.

- dataset:

  Optional dataset name to subset to.

- where_sep_sheet:

  Whether the where clauses are on a separate sheet.

- verbose:

  metacore verbosity, one of \`"silent"\`, \`"verbose"\`.

## Value

A spec data frame as produced by \[read_spec_df()\].

## Details

Read a P21-style specification workbook
