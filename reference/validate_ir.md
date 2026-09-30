# IR validation gate

Runs the schema and semantic gate every IR must pass before rendering:
class/shape, layer known, required args present, exclusive-arg groups,
per-layer semantic rules (enum values, formula token whitelists,
label/break length agreement), BDS-artifact assign guards, vector-arg
typing, and foreign-only dataset detection. Dependency cycles are gated
at two levels: variable-level cycles report \`cyclic dependencies:
...\`, and cycles between deliverable datasets report a distinct
\`cyclic deliverable dependencies: ...\` problem naming the datasets
that cannot be built in any order. Problems are reported, never guessed
or repaired. String arguments are limited to 16384 bytes. Expressions
admit uppercase identifiers, finite numbers, comparison and logical
operators, arithmetic, parentheses and quoted filter values. Calls,
assignments, indexing, comments and statement separators are rejected.

## Usage

``` r
validate_ir(ir)
```

## Arguments

- ir:

  List of \`aa_variable_ir\` objects built by \[new_variable_ir()\].

## Value

Character vector of human-readable problems; empty when valid.

## Details

Validate a variable IR
