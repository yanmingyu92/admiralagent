# Dependency routing plan

Derives the execution routing directly from spec lineage instead of a
hand-registered process DAG: topological waves (a variable enters wave k
only when every variable it references landed in an earlier wave),
per-variable dependencies, and the two fail-closed lanes — variables
blocked by dependency cycles and variables routed to human review. The
ordering is computed, not declared; \[validate_ir()\] refuses cyclic
specs outright, so a plan built from a validated IR always exists.

## Usage

``` r
routing_plan(ir, known_columns = character())
```

## Arguments

- ir:

  List of \`aa_variable_ir\` objects.

- known_columns:

  Character vector of column names assumed to pre-exist in the source
  data (e.g. SDTM base columns).

## Value

A data.frame with columns \`variable\`, \`wave\` (0-based topological
level; \`NA\` for cycle-blocked or human-routed variables),
\`depends_on\` (comma-joined variable names produced earlier in the same
IR), \`layers\` (layer chain or \`"needs_human"\`), and \`needs_human\`.
Attributes: \`blocked\` (cycle-blocked variables) and \`duplicate\`
(columns produced by more than one variable).

## Details

Plan the derivation routing for an IR
