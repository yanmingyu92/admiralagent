# Print an agreement report

Prints the dataset, voters, and per-level agreement rates of a
\[run_agreement()\] result, followed by a one-line reminder that
pre-execution agreement over a self-scoring regression corpus measures
translation consistency, not correctness and not independent double
programming.

## Usage

``` r
# S3 method for class 'aa_agreement'
print(x, ...)
```

## Arguments

- x:

  An \`aa_agreement\` object from \[run_agreement()\].

- ...:

  Ignored.

## Value

\`x\`, invisibly.

## Examples

``` r
res <- run_agreement(list(a = "rules", b = "rules"), dataset = "ADSL")
print(res)
#> admiralagent agreement report
#>   dataset: ADSL
#>   voters:  a, b
#>   agreement @ abstention:   1.000
#>   agreement @ layer_chain:  1.000
#>   agreement @ full:         1.000
#>   note: pre-execution agreement over a self-scoring regression corpus -
#>         translation consistency, not correctness or double programming.
```
