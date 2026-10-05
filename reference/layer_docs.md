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
