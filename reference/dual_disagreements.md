# Dual-backend disagreements

Returns the rows of the \`dual\` attribute where the two backends did
not agree - the variables a human must decide on. Each row carries both
layer chains and whether the LLM side produced a candidate IR the
reviewer can inspect as a starting point.

## Usage

``` r
dual_disagreements(ir)
```

## Arguments

- ir:

  IR list returned by \[classify_variables_dual()\].

## Value

A data.frame with columns \`variable\`, \`class\`, \`rules_layers\`,
\`llm_layers\`, \`llm_suggestion\`; zero rows when every variable
agreed.

## Details

Extract the dual-backend review queue
