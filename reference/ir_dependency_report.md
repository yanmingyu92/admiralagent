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

## Examples

``` r
spec <- mock_spec_adsl()
ir <- classify_variables(spec, "ADSL", backend = "rules")
ir_dependency_report(ir, known_columns = c("STUDYID", "USUBJID", "SUBJID",
  "TRT01P", "AGE", "RACEN", "RFSTDTC", "RFENDTC", "EXSTDTC"))
#>    variable   input dataset
#> 1     BMIBL  WEIGHT      vs
#> 2     BMIBL  HEIGHT      vs
#> 3     BMIBL   VISIT      vs
#> 4     BMIBL PARAMCD      vs
#> 5     BMIBL    AVAL      vs
#> 8       AGE  BRTHDT    ADSL
#> 9       AGE  TRTSDT    ADSL
#> 10    RACEN    RACE    ADSL
#> 11   TRT01P     ARM    ADSL
#>                                                                                                          issue
#> 1  not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 2  not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 3  not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 4  not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 5  not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 8  not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 9  not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 10 not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
#> 11 not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation
```
