# Render a variable

Renders a variable's full step pipeline via \[render_step()\], or a
\`NEEDS HUMAN REVIEW\` header block when the variable abstained.

## Usage

``` r
render_variable(v)
```

## Arguments

- v:

  An \`aa_variable_ir\` object.

## Value

A character string of commented R code.

## Details

Render one variable IR as code

## Examples

``` r
spec <- mock_spec_adsl()
ir <- classify_variables(spec, "ADSL", backend = "rules")
code <- render_variable(ir[[1]])
cat(code)
#> # DISCLAIMER: DRAFT CODE - qualified human review required before use.
#> # ---- STUDYID | step 1/1: assign ----
#> # Spec origin: "Copied directly from DM.STUDYID"
#> # Agent rationale: rule: direct copy from source variable
#> # Confidence: 1.00
#> # CHECK: target variable must not be all-missing after the derivation
#> ADSL <- ADSL |>
#>   dplyr::mutate(STUDYID = STUDYID)
```
