# Load the spec-to-IR classification eval corpus

Reads \`inst/evals/spec-to-ir.jsonl\`, one JSON eval case per line, into
a named list. Works both for an installed package (via
\[system.file()\]) and from the package source tree (walking up from the
working directory to find \`inst/evals/\`), so tests run uninstalled.

## Usage

``` r
load_evals(path = NULL)
```

## Arguments

- path:

  Optional full path to a \`.jsonl\` corpus file. Defaults to the
  bundled corpus located automatically.

## Value

A named list of parsed eval cases (names are case ids). Each case has
fields \`id\`, \`dataset\`, \`spec_row\`, \`expected_layers\`,
\`expected_needs_human\`, and \`note\`.
