# Render a step

Renders a single step with its block header (variable, step index,
layer, spec origin, rationale, confidence) and the \`# CHECK\`
validation comments attached to the layer. Renders only; never executes.

## Usage

``` r
render_step(step, v, i)
```

## Arguments

- step:

  An \`aa_step\` object.

- v:

  The parent \`aa_variable_ir\` object.

- i:

  Step index (1-based) within \`v\$steps\`.

## Value

A character string of commented R code.

## Details

Render one IR step as code
