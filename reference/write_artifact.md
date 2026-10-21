# Write variable artifacts

Writes one \`\<dataset\>\_\_\<variable\>\_\_\<hash8\>.R\` artifact per
variable (rendered code with CHECK comments) plus a JSON sidecar
recording the IR, backend, model, validation result, and disclaimer.
Same IR overwrites the same files; copies never accumulate.

## Usage

``` r
write_artifact(
  ir,
  dir,
  backend_label = "rules",
  model = NULL,
  validation = NULL
)
```

## Arguments

- ir:

  List of \`aa_variable_ir\` objects.

- dir:

  Output directory (created when missing). No default is set: pass an
  explicit path such as \`tempdir()\` so nothing is ever written to the
  user's current working directory by accident.

- backend_label:

  Backend label recorded in sidecars.

- model:

  Model identifier recorded in sidecars (LLM backend).

- validation:

  Optional validation result recorded in sidecars.

## Value

Invisibly, the character vector of files written.

## Details

Write per-variable artifacts and sidecars

## Examples

``` r
spec <- mock_spec_adsl()
ir <- classify_variables(spec, "ADSL", backend = "rules")
out <- file.path(tempdir(), "aa-examples")
write_artifact(ir, dir = out)
list.files(out)
#>  [1] "adsl__age__6aea851a.R"          "adsl__age__6aea851a.R.json"    
#>  [3] "adsl__agegr1__6aea851a.R"       "adsl__agegr1__6aea851a.R.json" 
#>  [5] "adsl__bmibl__6aea851a.R"        "adsl__bmibl__6aea851a.R.json"  
#>  [7] "adsl__racen__6aea851a.R"        "adsl__racen__6aea851a.R.json"  
#>  [9] "adsl__studyid__6aea851a.R"      "adsl__studyid__6aea851a.R.json"
#> [11] "adsl__subjid__6aea851a.R"       "adsl__subjid__6aea851a.R.json" 
#> [13] "adsl__trt01p__6aea851a.R"       "adsl__trt01p__6aea851a.R.json" 
#> [15] "adsl__trtedtm__6aea851a.R"      "adsl__trtedtm__6aea851a.R.json"
#> [17] "adsl__trtsdtm__6aea851a.R"      "adsl__trtsdtm__6aea851a.R.json"
#> [19] "adsl__usubjid__6aea851a.R"      "adsl__usubjid__6aea851a.R.json"
```
