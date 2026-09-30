# Accuracy of an eval run

Extracts the accuracy from a result data.frame returned by
\[run_evals()\].

## Usage

``` r
evals_accuracy(res)
```

## Arguments

- res:

  data.frame with a logical \`ok\` column, as returned by
  \[run_evals()\].

## Value

A single numeric in \`\[0, 1\]\`: the share of cases classified as
expected.
