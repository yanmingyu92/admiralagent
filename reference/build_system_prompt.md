# Build system prompt

Assembles the translation prompt: role definition, the full layer
vocabulary from \[layer_docs()\], the strict JSON output contract with
an example object, and the hard rules (closed vocabulary, \`on\`
placement, formula whitelists, merge_var for cross-dataset values,
needs_human abstention).

## Usage

``` r
build_system_prompt()
```

## Value

A single character string.

## Details

Build the LLM system prompt
