# Dataset-JSON Cooperation Demo

## What Dataset-JSON is

[Dataset-JSON](https://www.cdisc.org/standards/data-exchange/dataset-json) is
the CDISC Data Exchange open standard for transmitting tabular clinical
submission data (SDTM/ADaM) as JSON instead of SAS v5 XPT. It is the format
used by the R Consortium submission pilots 5-7: pilot 5 delivered a full FDA
submission package written in R with the `{datasetjson}` package, with
`define.xml`-style metadata carried in each file's header
(`datasetJSONVersion`, `columns` with itemOID/label/dataType/length, `records`,
provenance keys `fileOID`/`originator`/`sourceSystem`).

Each file holds one dataset: a `columns` array (declared order, ODM item OIDs,
labels, data types) plus a `rows` array of positional value arrays (`null` =
missing). Local clones of the standard's schema and real pilot data live in
this workspace (see below), so everything here runs offline.

## Where the real pilot 5 files live locally

Shallow clones (this workspace, no network needed afterwards):

| Clone | Contents |
|---|---|
| `cdisc_data/pilot5data` | `github.com/RConsortium/submissions-pilot5-datasetjson` — the actual pilot 5 submission repo |
| `cdisc_data/datasetjson-schema` | `github.com/cdisc-org/DataExchange-DatasetJson` — the Dataset-JSON 1.1 JSON schema + CDISC SDTM/SEND examples |

All files seen so far declare `datasetJSONVersion: 1.1.0`.

- Pilot 5 SDTM input (CDISCPILOT01, 20 datasets):
  `cdisc_data/pilot5data/pilot5-submission/pilot5-input/sdtmdata/datasetjson/`
  — `dm.json` (306 x 25), `ex.json`, `vs.json`, `ae.json`, `lb.json`, `qs.json`,
  `mh.json`, `cm.json`, `ds.json`, `se.json`, `sv.json`, `sc.json`, `ta/te/ti/tv`,
  `relrec`, `suppae/suppdm/suppds/supplb`
- Pilot 5 ADaM output:
  `cdisc_data/pilot5data/pilot5-submission/pilot5-output/pilot5-datasetjson/`
  — `adsl.json` (254 x 49), `adae.json`, `adadas.json`, `adlbc.json`, `adtte.json`
- CDISC reference examples: `cdisc_data/datasetjson-schema/examples/sdtm/` and
  `examples/send/`

## Reading files

```r
library(admiralagent)

dm_json <- file.path(
  "cdisc_data", "pilot5data", "pilot5-submission",
  "pilot5-input", "sdtmdata", "datasetjson", "dm.json"
)

# header only: version, record count, column table, provenance
meta <- dataset_json_meta(dm_json)
meta$datasetJSONVersion   # "1.1.0"
meta$records              # 306
meta$columns[, c("name", "dataType", "label")]

# full data frame, columns in declared order
dm <- read_dataset_json(dm_json)
dim(dm)                       # 306 25
dm$USUBJID[1]                 # "01-701-1015"
attr(dm, "dataset_label")     # NA (this writer ships an empty label)
attr(dm, "labels")$AGE        # "Age"
```

## Using the output as `sources` in `execute_ir()`

`read_dataset_json()` returns a plain data frame, so Dataset-JSON deliveries
plug directly into the `execute_ir()` sources contract (`base` = target
dataset base, other names = the objects step args refer to):

```r
spec <- mock_spec_adsl()
ir <- classify_variables(spec, "ADSL", backend = "rules")

sdtm_dir <- file.path(
  "cdisc_data", "pilot5data", "pilot5-submission",
  "pilot5-input", "sdtmdata", "datasetjson"
)
src <- list(
  base = read_dataset_json(file.path(sdtm_dir, "dm.json")),
  ex   = read_dataset_json(file.path(sdtm_dir, "ex.json")),
  vs   = read_dataset_json(file.path(sdtm_dir, "vs.json"))
)

res <- execute_ir(ir, sources = src)
res$status
res$adsl
```

## Current limitations

- **Dates stay character by default.** `date`/`datetime`/`time` columns are
  returned as the original ISO strings (pilot 5 writers serialize even
  `targetDataType = "integer"` dates as ISO strings). A typed conversion only
  happens when the column declares `targetDataType` `"Date"`/`"Datetime"`, and
  only when every non-missing value parses; SDTM partial dates (`"2010-04"`)
  therefore keep the whole column as character. Parse converted columns with
  `admiral::derive_vars_dt()`/`ymd()` downstream when needed.
- **Numerics are doubles.** `integer` columns come back as R `numeric` to
  avoid 32-bit integer overflow; use `as.integer()` when you know it is safe.
- **Nested multi-dataset files read only the first `itemGroupData`** (all
  pilot/CDISC files found use the flat single-dataset 1.1 layout, so this is
  theoretical).
- Labels live in `attr(df, "labels")` (named list) and the dataset label in
  `attr(df, "dataset_label")`; they are not round-tripped back to JSON by this
  package (writer scope, e.g. `{datasetjson}`).
