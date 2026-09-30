dsj_synthetic_file <- function(columns, rows, records = length(rows), version = "1.1.0") {
  doc <- list(
    fileOID = "www.example.org/synthetic",
    datasetJSONCreationDateTime = "2026-01-01T00:00:00",
    datasetJSONVersion = version,
    itemGroupOID = "IG.DM",
    records = records,
    name = "DM",
    label = "Demographics",
    columns = columns,
    rows = rows
  )
  f <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, null = "null"), f)
  f
}

dsj_write_raw <- function(txt) {
  f <- tempfile(fileext = ".json")
  writeLines(txt, f)
  f
}

syn_cols <- list(
  list(itemOID = "IT.STUDYID", name = "STUDYID", label = "Study Identifier", dataType = "string", length = 12L),
  list(itemOID = "IT.AGE", name = "AGE", label = "Age", dataType = "integer"),
  list(itemOID = "IT.TRTSDT", name = "TRTSDT", label = "Treatment Start Date", dataType = "date")
)

syn_rows <- list(
  list("S01", 63, "2014-01-02"),
  list("S02", NA, "2014-02-03"),
  list("S03", 48, NA)
)

test_that("read_dataset_json returns correct types, dims, NAs and labels", {
  f <- dsj_synthetic_file(syn_cols, syn_rows)
  on.exit(unlink(f), add = TRUE)
  dm <- read_dataset_json(f)

  expect_s3_class(dm, "data.frame")
  expect_identical(dim(dm), c(3L, 3L))
  expect_identical(names(dm), c("STUDYID", "AGE", "TRTSDT"))
  expect_identical(dm$STUDYID, c("S01", "S02", "S03"))
  expect_type(dm$AGE, "double")
  expect_identical(dm$AGE, c(63, NA_real_, 48))
  expect_identical(dm$TRTSDT, c("2014-01-02", "2014-02-03", NA_character_))
  expect_identical(attr(dm, "dataset_label"), "Demographics")
  expect_identical(attr(dm, "dataset_json_version"), "1.1.0")
  labels <- attr(dm, "labels")
  expect_type(labels, "list")
  expect_identical(names(labels), c("STUDYID", "AGE", "TRTSDT"))
  expect_identical(labels$AGE, "Age")
})

test_that("targetDataType Date yields Date column with raw strings attached", {
  cols <- list(
    list(name = "BIRTHDT", label = "Birth Date", dataType = "date", targetDataType = "Date"),
    list(name = "TRTSDTM", label = "Trt Start Datetime", dataType = "datetime", targetDataType = "Datetime")
  )
  rows <- list(
    list("1951-02-14", "2014-01-02T11:45"),
    list("1962-07-01", "2014-07-02T09:00:00Z"),
    list(NA, NA)
  )
  f <- dsj_synthetic_file(cols, rows)
  on.exit(unlink(f), add = TRUE)
  out <- read_dataset_json(f)

  expect_s3_class(out$BIRTHDT, "Date")
  expect_identical(as.character(out$BIRTHDT), c("1951-02-14", "1962-07-01", NA_character_))
  expect_identical(attr(out$BIRTHDT, "raw"), c("1951-02-14", "1962-07-01", NA_character_))
  expect_s3_class(out$TRTSDTM, "POSIXct")
  expect_identical(format(out$TRTSDTM, "%Y-%m-%d %H:%M:%S"), c("2014-01-02 11:45:00", "2014-07-02 09:00:00", NA))
})

test_that("partial dates keep the column character despite targetDataType Date", {
  cols <- list(list(name = "MHSTDTC", label = "Start Date", dataType = "date", targetDataType = "Date"))
  rows <- list(list("2010-04-30"), list("2010-04"), list(NA))
  f <- dsj_synthetic_file(cols, rows)
  on.exit(unlink(f), add = TRUE)
  out <- read_dataset_json(f)

  expect_type(out$MHSTDTC, "character")
  expect_identical(out$MHSTDTC, c("2010-04-30", "2010-04", NA_character_))
  expect_null(attr(out$MHSTDTC, "raw"))
})

test_that("zero-row file (rows omitted, records = 0) returns typed empty data frame", {
  f <- dsj_synthetic_file(syn_cols, rows = list(), records = 0L)
  doc <- jsonlite::fromJSON(f, simplifyVector = FALSE)
  doc$rows <- NULL
  writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, null = "null"), f)
  on.exit(unlink(f), add = TRUE)
  dm <- read_dataset_json(f)

  expect_identical(dim(dm), c(0L, 3L))
  expect_identical(names(dm), c("STUDYID", "AGE", "TRTSDT"))
  expect_type(dm$STUDYID, "character")
  expect_type(dm$AGE, "double")
  expect_identical(attr(dm, "dataset_label"), "Demographics")
})

test_that("missing rows key with records > 0 fails with a schema error", {
  f <- dsj_write_raw(paste0(
    '{"datasetJSONVersion":"1.1.0","itemGroupOID":"IG.DM","records":3,',
    '"name":"DM","label":"Demographics",',
    '"columns":[{"itemOID":"IT.A","name":"A","label":"A","dataType":"string"}]}'
  ))
  on.exit(unlink(f), add = TRUE)
  expect_error(read_dataset_json(f), "Dataset-JSON schema")
  expect_error(read_dataset_json(f), "rows")
})

test_that("missing columns and missing datasetJSONVersion fail with schema errors", {
  f <- dsj_write_raw('{"datasetJSONVersion":"1.1.0","records":1,"name":"DM","label":"DM","rows":[["a"]]}')
  expect_error(read_dataset_json(f), "columns")
  f2 <- dsj_write_raw(paste0(
    '{"itemGroupOID":"IG.DM","records":1,"name":"DM","label":"DM",',
    '"columns":[{"name":"A","label":"A","dataType":"string"}],"rows":[["a"]]}'
  ))
  expect_error(read_dataset_json(f2), "datasetJSONVersion")
  unlink(c(f, f2))
})

test_that("missing file errors informatively", {
  expect_error(read_dataset_json(tempfile(fileext = ".json")), "not found")
})

test_that("dataset_json_meta returns version, records and a columns table", {
  f <- dsj_synthetic_file(syn_cols, syn_rows)
  on.exit(unlink(f), add = TRUE)
  meta <- dataset_json_meta(f)

  expect_identical(meta$datasetJSONVersion, "1.1.0")
  expect_identical(meta$records, 3L)
  expect_identical(meta$name, "DM")
  expect_identical(meta$label, "Demographics")
  expect_identical(meta$originator, NA_character_)
  expect_s3_class(meta$columns, "data.frame")
  expect_identical(meta$columns$name, c("STUDYID", "AGE", "TRTSDT"))
  expect_identical(meta$columns$dataType, c("string", "integer", "date"))
  expect_identical(meta$columns$length, c(12L, NA_integer_, NA_integer_))
})

test_that("round-trip: small data frame serialized as Dataset-JSON reads back consistent", {
  df <- data.frame(
    DOMAIN = c("DM", "DM"),
    AVAL = c(1.5, NA),
    ADTM = c("2020-01-01T10:00", "2020-02-02"),
    stringsAsFactors = FALSE
  )
  doc <- list(
    datasetJSONVersion = "1.1.0",
    records = 2L,
    name = "ADXX",
    label = "Round Trip",
    columns = list(
      list(itemOID = "IT.DOMAIN", name = "DOMAIN", label = "Domain", dataType = "string"),
      list(itemOID = "IT.AVAL", name = "AVAL", label = "Value", dataType = "decimal"),
      list(itemOID = "IT.ADTM", name = "ADTM", label = "Datetime", dataType = "datetime")
    ),
    rows = lapply(seq_len(nrow(df)), function(i) unname(as.list(df[i, ])))
  )
  f <- dsj_write_raw(jsonlite::toJSON(doc, auto_unbox = TRUE, null = "null"))
  on.exit(unlink(f), add = TRUE)
  back <- read_dataset_json(f)

  expect_identical(back$DOMAIN, df$DOMAIN)
  expect_identical(back$AVAL, df$AVAL)
  expect_identical(back$ADTM, df$ADTM)
  expect_identical(dim(back), c(2L, 3L))
})

# ---- integration against real R Consortium pilot 5 Dataset-JSON files ----
# Cloned from github.com/RConsortium/submissions-pilot5-datasetjson (shallow)
# into cdisc_data/pilot5data. Tests are skipped when the clone is absent.

dsj_pilot5 <- function(...) {
  file.path("..", "..", "..", "cdisc_data", "pilot5data",
            "pilot5-submission", ...)
}

test_that("real pilot 5 SDTM dm.json reads with matching record count", {
  f <- dsj_pilot5("pilot5-input", "sdtmdata", "datasetjson", "dm.json")
  skip_if(!file.exists(f), "pilot5 dm.json not cloned")

  meta <- dataset_json_meta(f)
  expect_identical(meta$datasetJSONVersion, "1.1.0")
  expect_identical(meta$name, "dm")

  dm <- read_dataset_json(f)
  expect_gt(nrow(dm), 0)
  expect_identical(nrow(dm), as.integer(meta$records))
  expect_true(all(c("STUDYID", "USUBJID") %in% names(dm)))
  expect_identical(unique(dm$STUDYID), "CDISCPILOT01")
  expect_identical(dm$USUBJID[1], "01-701-1015")
  expect_type(dm$AGE, "double")
})

test_that("real pilot 5 ADaM adsl.json reads with ISO date columns kept as strings", {
  f <- dsj_pilot5("pilot5-output", "pilot5-datasetjson", "adsl.json")
  skip_if(!file.exists(f), "pilot5 adsl.json not cloned")

  meta <- dataset_json_meta(f)
  expect_identical(meta$datasetJSONVersion, "1.1.0")
  expect_identical(meta$label, "Subject-Level Analysis Dataset")
  expect_identical(meta$originator, "R Submission Pilot 5")

  adsl <- read_dataset_json(f)
  expect_identical(nrow(adsl), as.integer(meta$records))
  expect_true(all(c("STUDYID", "USUBJID", "TRT01P") %in% names(adsl)))
  expect_type(adsl$TRTSDT, "character")
  expect_true(all(grepl("^\\d{4}-\\d{2}-\\d{2}", adsl$TRTSDT[!is.na(adsl$TRTSDT)])))
  expect_identical(attr(adsl, "labels")$TRTSDT, "Date of First Exposure to Treatment")
})
