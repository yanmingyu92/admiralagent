# admiral compatibility check

Compares the minimum admiral version required by the layers used in the
IR against the installed admiral version. Absence of admiral is not an
error: rendering is static and only execution is blocked.

## Usage

``` r
check_admiral_compat(ir, installed = NA)
```

## Arguments

- ir:

  List of \`aa_variable_ir\` objects.

- installed:

  admiral version to compare against; defaults to the installed
  \`utils::packageVersion("admiral")\` (NA-safe when missing).

## Value

A character vector of problem messages (empty when compatible); the
vector carries a \`note\` attribute when admiral is not installed.

## Details

Check admiral version compatibility of an IR
