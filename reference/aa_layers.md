# Layer registry

Returns the single source of truth mapping each derivation layer to its
admiral/metatools function, argument schema, required args, render
closure, check ids, and ordering rank. The LLM output space is the
cartesian product of this registry; nothing outside it passes
\[validate_ir()\].

## Usage

``` r
aa_layers()
```

## Value

A named list; one entry per layer with elements \`fn\`, \`label\`,
\`args\`, \`required\`, \`rank\`, \`checks\`, \`inputs\`, \`render\`,
and - where the layer has optional args with an implied value -
\`defaults\`, a named list of literals or functions of the supplied
args. Defaults are applied to \`render\` input and by canonicalization,
so an omitted arg and the same arg stated explicitly are one derivation.

## Details

Layer registry for admiralagent
