# Dataset-JSON header metadata

Reads only the header of a CDISC Dataset-JSON file (version 1.1 or the
nested 1.0 layout) and returns the metadata needed to inspect a delivery
without materialising the rows: schema version, record count, dataset
name/label, provenance fields (\`fileOID\`, \`originator\`,
\`sourceSystem\`, \`studyOID\`), and the \`columns\` table (itemOID,
name, label, dataType, targetDataType, length).

## Usage

``` r
dataset_json_meta(path)
```

## Arguments

- path:

  Path to a Dataset-JSON file.

## Value

A list with elements \`path\`, \`datasetJSONVersion\`, \`records\`,
\`name\`, \`label\`, \`itemGroupOID\`, \`fileOID\`, \`originator\`,
\`sourceSystem\`, \`studyOID\`, and \`columns\` (data.frame). Stops with
an informative error when required keys are absent.

## Details

Dataset-JSON header metadata

## Examples

``` r
if (FALSE) { # \dontrun{
meta <- dataset_json_meta("sdtm/dm.json")
meta$datasetJSONVersion
meta$records
meta$columns
} # }
```
