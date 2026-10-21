# Layer names

Convenience accessor over \[aa_layers()\] returning the allowed
\`layer\` vocabulary.

## Usage

``` r
layer_names()
```

## Value

Character vector of layer names.

## Details

Names of all registered derivation layers

## Examples

``` r
layer_names()
#>  [1] "assign"             "merge_var"          "lookup_join"       
#>  [4] "impute_dtc"         "dtm_to_dt"          "duration"          
#>  [7] "date_shift"         "compute_param"      "summary_record"    
#> [10] "extreme_flag"       "codelist_var"       "obs_number"        
#> [13] "categorize"         "compute_var"        "assign_conditional"
```
