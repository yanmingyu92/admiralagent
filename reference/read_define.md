# Read define.xml

Primary path: parses the define.xml directly with \[parse_define()\]
(requires the \`xml2\` package), which preserves the per-variable
derivation text from \`MethodDef\` elements - metadata that
\[metacore::define_to_metacore()\] drops for some define versions (e.g.
the CDISC pilot submission defines). Fallback path: when the direct
parser fails (missing \`xml2\`, malformed XML, non-ODM structure), the
file is re-parsed via metacore and flattened through \`spec_as_df()\`,
whose \`derivation\` column may then be empty. When both paths fail an
informative error is raised.

## Usage

``` r
read_define(path)
```

## Arguments

- path:

  Path to the define.xml file.

## Value

A spec data frame as produced by \[read_spec_df()\]; the primary path
additionally returns \`codelist_oid\` and \`order\` columns.

## Details

Read a define.xml metadata file
