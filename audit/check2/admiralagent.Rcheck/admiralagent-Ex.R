pkgname <- "admiralagent"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
options(pager = "console")
library('admiralagent')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("dataset_json_meta")
### * dataset_json_meta

flush(stderr()); flush(stdout())

### Name: dataset_json_meta
### Title: Dataset-JSON header metadata
### Aliases: dataset_json_meta

### ** Examples

## Not run: 
##D meta <- dataset_json_meta("sdtm/dm.json")
##D meta$datasetJSONVersion
##D meta$records
##D meta$columns
## End(Not run)



cleanEx()
nameEx("execute_ir")
### * execute_ir

flush(stderr()); flush(stdout())

### Name: execute_ir
### Title: Execute a Layer IR against source datasets
### Aliases: execute_ir

### ** Examples

## Not run: 
##D spec <- mock_spec_adsl()
##D ir <- classify_variables(spec, "ADSL", backend = "rules")
##D res <- execute_ir(ir, sources = list(base = dm, ex = ex, vs = vs_bds))
##D res$status
## End(Not run)



cleanEx()
nameEx("parse_define")
### * parse_define

flush(stderr()); flush(stdout())

### Name: parse_define
### Title: Parse define.xml
### Aliases: parse_define

### ** Examples

## Not run: 
##D spec <- parse_define("define.xml")
##D nrow(spec[spec$dataset == "ADSL" & !is.na(spec$derivation), ])
## End(Not run)



cleanEx()
nameEx("read_dataset_json")
### * read_dataset_json

flush(stderr()); flush(stdout())

### Name: read_dataset_json
### Title: Read a Dataset-JSON file
### Aliases: read_dataset_json

### ** Examples

## Not run: 
##D dm_json <- file.path("cdisc_data", "pilot5data", "pilot5-submission",
##D   "pilot5-input", "sdtmdata", "datasetjson", "dm.json")
##D dm <- read_dataset_json(dm_json)
##D dim(dm)
##D attr(dm, "labels")$STUDYID
## End(Not run)



### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
