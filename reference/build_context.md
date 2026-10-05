# Build LLM context

Converts spec rows into a per-variable list of schema fields (dataset,
variable, label, type, origin, derivation, source pointers). No patient
data ever enters the context. The dataset field lets the model emit the
correct target-dataset token for non-ADSL specs; without it the model
can only guess (and copies the system prompt's ADSL example), so
\[align_batch()\] rejected those batches (finding F-06).

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
