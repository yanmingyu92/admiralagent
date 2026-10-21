# Layer documentation cards

Renders each registry entry (function, label, args, required args) into
a compact text card. These cards are embedded verbatim in the LLM system
prompt built by \[build_system_prompt()\].

## Usage

``` r
layer_docs()
```

## Value

Named character vector, one documentation block per layer.

## Details

Human-readable documentation of every layer

## Examples

``` r
cards <- layer_docs()
cat(cards[["assign"]])
#> layer: assign
#>   fn: dplyr::mutate
#>   label: Direct assignment: copy a source variable or set a literal constant
#>   args:
#>     - target: character, new variable name
#>     - from: character, source variable name in current dataset (mutually exclusive with literal)
#>     - literal: character, literal constant value (quoted)
#>     - on: character, dataset object name for this step (optional)
#>   required: target
```
