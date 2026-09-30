# Build a codelist data.frame from observed data values

Builds a minimal \`code\`/\`decode\` codelist data.frame from the unique
values of \`data\[\[var\]\]\`: \`decode\` is \`sort(unique(...))\` of
the non-missing values and \`code\` is \`seq_along(decode)\`. The result
is suitable as an entry of the \`codelists\` argument of
\[mock_metacore()\], e.g. \`codelists = list(RACE =
codelist_from_data("RACE", dm))\`.

## Usage

``` r
codelist_from_data(var, data)
```

## Arguments

- var:

  Character, name of the column in \`data\` holding the decode values
  (e.g. \`"RACE"\`).

- data:

  A data.frame containing \`var\`.

## Value

A data.frame with columns \`code\` (integer) and \`decode\` (character),
one row per unique non-missing value, sorted by decode.
