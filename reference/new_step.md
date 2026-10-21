# New layer step

Builds one step of a variable's derivation pipeline: a layer name plus
its named args. Nested one-element lists are flattened (JSON round-trip
normalization) and empty args are dropped.

## Usage

``` r
new_step(layer, args = list())
```

## Arguments

- layer:

  Layer name; must be one of \[layer_names()\].

- args:

  Named list of layer arguments.

## Value

A list of class \`aa_step\` with elements \`layer\` and \`args\`.

## Details

Construct a layer step

## Examples

``` r
new_step("assign", list(target = "TRT01P", from = "TRT01P"))
#> $layer
#> [1] "assign"
#> 
#> $args
#> $args$target
#> [1] "TRT01P"
#> 
#> $args$from
#> [1] "TRT01P"
#> 
#> 
#> attr(,"class")
#> [1] "aa_step" "list"   
```
