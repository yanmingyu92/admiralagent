# Parse define.xml

Parses an ODM/define v2.0 define.xml with \[xml2::read_xml()\] without
metacore: walks every \`ItemGroupDef\` (dataset) and its ordered
\`ItemRef\` list, joins each \`ItemDef\` (variable name, label, type,
length, origin, codelist reference) and resolves \`MethodOID\` links to
\`MethodDef\` elements carrying the real derivation text. This is the
primary engine behind \[read_define()\]; unlike the metacore fallback it
preserves per-variable derivation text for define versions metacore does
not map (e.g. the CDISC pilot submission defines, where every ItemRef
carries a MethodOID).

Namespace handling is pragmatic: all lookups match by \`local-name()\`
so the ODM default namespace and the \`def:\` prefix version do not
matter.

## Usage

``` r
parse_define(path)
```

## Arguments

- path:

  Path to a define.xml file.

## Value

A spec data frame compatible with \[read_spec_df()\] with columns
\`dataset\`, \`variable\`, \`label\`, \`type\`, \`length\`, \`origin\`,
\`derivation\`, \`order\` plus \`codelist_oid\` (the CodeList OID per
variable, \`NA\` when the variable has no CodeListRef). The data frame
carries a \`dataset_labels\` attribute: a named character vector of
dataset labels from the ItemGroupDef descriptions.

## Details

Parse an ODM define.xml directly into a spec data frame

## Examples

``` r
if (FALSE) { # \dontrun{
spec <- parse_define("define.xml")
nrow(spec[spec$dataset == "ADSL" & !is.na(spec$derivation), ])
} # }
```
