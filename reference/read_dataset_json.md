# Read a Dataset-JSON file

Parses a file conforming to the CDISC Dataset-JSON open standard (Data
Exchange, version 1.1) and returns the data as a data frame, so
Dataset-JSON deliveries can be dropped straight into \[execute_ir()\]
\`sources\`. Both layouts are supported: the 1.1 single-dataset layout
(top-level \`columns\`/\`rows\`, as written by the R Consortium
submission pilots) and the older nested \`itemGroupData\` layout (the
first item group is read).

Type coercion follows the declared \`dataType\` of each column:

\- \`"string"\`/\`"character"\`/\`"URI"\`: character -
\`"integer"\`/\`"float"\`/\`"double"\`/\`"decimal"\`: numeric (double;
integers are deliberately not narrowed to R integers to avoid 32-bit
overflow on large keys) - \`"boolean"\`: logical -
\`"date"\`/\`"datetime"\`/\`"time"\`: character by default. If the
column declares \`targetDataType\` \`"Date"\` or \`"Datetime"\`, a typed
conversion via \[as.Date()\] / \[as.POSIXct()\] (UTC) is attempted; when
any non-missing value fails to parse (e.g. partial SDTM \`–DTC\` dates
such as \`"2010-04"\`), the whole column safely stays character.
Whenever a typed conversion succeeds, the original JSON strings are
preserved in \`attr(column, "raw")\`.

JSON \`null\` cell values become \`NA\`; numeric columns also accept the
legacy pilot string sentinel \`"NA"\` (with surrounding whitespace).
Other invalid numeric values and non-scalar cells are rejected. A file
with \`records = 0\` may omit \`rows\` entirely; the result is then a
zero-row data frame with the declared columns.

Attached metadata: \`attr(df, "dataset_label")\` (the item group /
dataset label, \`NA\` when absent), \`attr(df, "labels")\` (named list
of variable labels in column order), and \`attr(df,
"dataset_json_version")\`.

## Usage

``` r
read_dataset_json(path)
```

## Arguments

- path:

  Path to a Dataset-JSON file (\`.json\`).

## Value

A data.frame with columns in the declared order, carrying the metadata
attributes described above. Stops with an informative error when the
file is missing, unparsable, or lacks required Dataset-JSON schema keys
(\`datasetJSONVersion\`, \`columns\`, \`rows\` when \`records \> 0\`).

## Details

Read a CDISC Dataset-JSON file

## Examples

``` r
if (FALSE) { # \dontrun{
dm_json <- file.path("cdisc_data", "pilot5data", "pilot5-submission",
  "pilot5-input", "sdtmdata", "datasetjson", "dm.json")
dm <- read_dataset_json(dm_json)
dim(dm)
attr(dm, "labels")$STUDYID
} # }
```
