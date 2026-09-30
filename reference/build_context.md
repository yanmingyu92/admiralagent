# Build LLM context

Converts spec rows into a per-variable list of schema fields (variable,
label, type, origin, derivation, source pointers). No patient data ever
enters the context.

## Usage

``` r
build_context(vars)
```

## Arguments

- vars:

  Spec data frame subset from \[spec_variables()\].

## Value

A named list (by variable name) of schema-only field lists.

## Details

Build schema-only LLM context
