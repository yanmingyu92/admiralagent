# Render a variable

Renders a variable's full step pipeline via \[render_step()\], or a
\`NEEDS HUMAN REVIEW\` header block when the variable abstained.

## Usage

``` r
render_variable(v)
```

## Arguments

- v:

  An \`aa_variable_ir\` object.

## Value

A character string of commented R code.

## Details

Render one variable IR as code
