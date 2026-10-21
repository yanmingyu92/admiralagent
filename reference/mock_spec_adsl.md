# Mock ADSL spec

A 10-variable mock ADSL spec (STUDYID, USUBJID, SUBJID, TRT01P, TRTSDTM,
TRTEDTM, AGE, AGEGR1, RACEN, BMIBL) with realistic free-text
derivations, used in demos, tests, and the vignette.

## Usage

``` r
mock_spec_adsl()
```

## Value

A spec data frame as produced by \[read_spec_df()\].

## Details

Mock ADSL specification

## Examples

``` r
spec <- mock_spec_adsl()
spec$variable
#>  [1] "STUDYID" "USUBJID" "SUBJID"  "TRT01P"  "TRTSDTM" "TRTEDTM" "AGE"    
#>  [8] "AGEGR1"  "RACEN"   "BMIBL"  
```
