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
