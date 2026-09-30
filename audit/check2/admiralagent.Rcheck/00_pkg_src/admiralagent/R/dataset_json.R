#' Read a CDISC Dataset-JSON file
#'
#' @description
#' Parses a file conforming to the CDISC Dataset-JSON open standard
#' (Data Exchange, version 1.1) and returns the data as a data frame, so
#' Dataset-JSON deliveries can be dropped straight into [execute_ir()]
#' `sources`. Both layouts are supported: the 1.1 single-dataset layout
#' (top-level `columns`/`rows`, as written by the R Consortium submission
#' pilots) and the older nested `itemGroupData` layout (the first item group
#' is read).
#'
#' Type coercion follows the declared `dataType` of each column:
#'
#' - `"string"`/`"character"`/`"URI"`: character
#' - `"integer"`/`"float"`/`"double"`/`"decimal"`: numeric (double; integers
#'   are deliberately not narrowed to R integers to avoid 32-bit overflow on
#'   large keys)
#' - `"boolean"`: logical
#' - `"date"`/`"datetime"`/`"time"`: character by default. If the column
#'   declares `targetDataType` `"Date"` or `"Datetime"`, a typed conversion
#'   via [as.Date()] / [as.POSIXct()] (UTC) is attempted; when any non-missing
#'   value fails to parse (e.g. partial SDTM `--DTC` dates such as
#'   `"2010-04"`), the whole column safely stays character. Whenever a typed
#'   conversion succeeds, the original JSON strings are preserved in
#'   `attr(column, "raw")`.
#'
#' JSON `null` cell values become `NA`. A file with `records = 0` may omit
#' `rows` entirely; the result is then a zero-row data frame with the
#' declared columns.
#'
#' Attached metadata: `attr(df, "dataset_label")` (the item group / dataset
#' label, `NA` when absent), `attr(df, "labels")` (named list of variable
#' labels in column order), and `attr(df, "dataset_json_version")`.
#'
#' @title Read a Dataset-JSON file
#' @param path Path to a Dataset-JSON file (`.json`).
#' @return A data.frame with columns in the declared order, carrying the
#'   metadata attributes described above. Stops with an informative error
#'   when the file is missing, unparsable, or lacks required Dataset-JSON
#'   schema keys (`datasetJSONVersion`, `columns`, `rows` when `records > 0`).
#' @examples
#' \dontrun{
#' dm_json <- file.path("cdisc_data", "pilot5data", "pilot5-submission",
#'   "pilot5-input", "sdtmdata", "datasetjson", "dm.json")
#' dm <- read_dataset_json(dm_json)
#' dim(dm)
#' attr(dm, "labels")$STUDYID
#' }
#' @export
read_dataset_json <- function(path) {
  path <- dsj_path(path)
  doc <- dsj_read_doc(path)
  node <- dsj_dataset_node(doc)
  if (is.null(node) || !is.list(node$columns) || length(node$columns) == 0) {
    dsj_schema_stop(path, "missing required key 'columns'")
  }
  version <- dsj_scalar_chr(doc$datasetJSONVersion)
  if (is.na(version)) dsj_schema_stop(path, "missing required key 'datasetJSONVersion'")

  col_names <- vapply(node$columns, function(c) dsj_scalar_chr(c$name), "")
  if (any(is.na(col_names) | !nzchar(col_names))) {
    dsj_schema_stop(path, "a column definition is missing 'name'")
  }
  col_types <- tolower(vapply(node$columns, function(c) dsj_scalar_chr(c$dataType), ""))
  if (any(is.na(col_types) | !nzchar(col_types))) {
    bad <- col_names[is.na(col_types) | !nzchar(col_types)][1]
    dsj_schema_stop(path, "column '", bad, "' is missing 'dataType'")
  }

  records <- dsj_scalar_num(node$records)
  rows <- node$rows
  if (is.null(rows)) {
    if (!is.na(records) && records > 0) {
      dsj_schema_stop(path, "missing required key 'rows' (header declares records = ", records, ")")
    }
    rows <- list()
  }
  n_col <- length(node$columns)
  bad_row <- which(vapply(rows, length, integer(1)) != n_col)
  if (length(bad_row) > 0) {
    dsj_schema_stop(
      path, "row ", bad_row[1], " has ", length(rows[[bad_row[1]]]),
      " values but ", n_col, " columns are declared"
    )
  }

  out <- as.data.frame(
    setNames(
      lapply(seq_len(n_col), function(i) {
        dsj_coerce_values(lapply(rows, dsj_cell, i), node$columns[[i]])
      }),
      col_names
    ),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  if (!is.na(records) && records != nrow(out)) {
    warning(
      sprintf("Dataset-JSON header declares records = %d but %d rows were read", records, nrow(out)),
      call. = FALSE
    )
  }
  attr(out, "dataset_label") <- node$label
  attr(out, "labels") <- setNames(
    lapply(node$columns, function(c) dsj_scalar_chr(c$label)),
    col_names
  )
  attr(out, "dataset_json_version") <- version
  out
}

#' Dataset-JSON header metadata
#'
#' @description
#' Reads only the header of a CDISC Dataset-JSON file (version 1.1 or the
#' nested 1.0 layout) and returns the metadata needed to inspect a delivery
#' without materialising the rows: schema version, record count, dataset
#' name/label, provenance fields (`fileOID`, `originator`, `sourceSystem`,
#' `studyOID`), and the `columns` table (itemOID, name, label, dataType,
#' targetDataType, length).
#'
#' @title Dataset-JSON header metadata
#' @param path Path to a Dataset-JSON file.
#' @return A list with elements `path`, `datasetJSONVersion`, `records`,
#'   `name`, `label`, `itemGroupOID`, `fileOID`, `originator`,
#'   `sourceSystem`, `studyOID`, and `columns` (data.frame). Stops with an
#'   informative error when required keys are absent.
#' @examples
#' \dontrun{
#' meta <- dataset_json_meta("sdtm/dm.json")
#' meta$datasetJSONVersion
#' meta$records
#' meta$columns
#' }
#' @export
dataset_json_meta <- function(path) {
  path <- dsj_path(path)
  doc <- dsj_read_doc(path)
  node <- dsj_dataset_node(doc)
  if (is.null(node) || !is.list(node$columns) || length(node$columns) == 0) {
    dsj_schema_stop(path, "missing required key 'columns'")
  }
  version <- dsj_scalar_chr(doc$datasetJSONVersion)
  if (is.na(version)) dsj_schema_stop(path, "missing required key 'datasetJSONVersion'")
  records <- dsj_scalar_num(node$records)
  if (is.na(records)) records <- if (is.null(node$rows)) 0L else length(node$rows)
  cols <- node$columns
  list(
    path = path,
    datasetJSONVersion = version,
    records = records,
    name = node$name,
    label = node$label,
    itemGroupOID = dsj_scalar_chr(doc$itemGroupOID),
    fileOID = dsj_scalar_chr(doc$fileOID),
    originator = dsj_scalar_chr(doc$originator),
    sourceSystem = if (is.null(doc$sourceSystem)) NA else doc$sourceSystem,
    studyOID = dsj_scalar_chr(doc$studyOID),
    columns = data.frame(
      itemOID = vapply(cols, function(c) dsj_scalar_chr(c$itemOID), ""),
      name = vapply(cols, function(c) dsj_scalar_chr(c$name), ""),
      label = vapply(cols, function(c) dsj_scalar_chr(c$label), ""),
      dataType = vapply(cols, function(c) dsj_scalar_chr(c$dataType), ""),
      targetDataType = vapply(cols, function(c) dsj_scalar_chr(c$targetDataType), ""),
      length = vapply(cols, function(c) dsj_scalar_num(c$length), integer(1)),
      stringsAsFactors = FALSE
    )
  )
}

dsj_path <- function(path) {
  assert_path(path)
  if (length(path) != 1 || is.na(path) || !nzchar(path) || !file.exists(path)) {
    stop("Dataset-JSON file not found: ", path, call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

dsj_read_doc <- function(path) {
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) {
      stop("failed to parse '", path, "' as JSON: ", conditionMessage(e), call. = FALSE)
    }
  )
}

dsj_dataset_node <- function(doc) {
  if (is.list(doc$columns) && length(doc$columns) > 0) {
    list(
      columns = doc$columns, rows = doc$rows, records = doc$records,
      name = dsj_scalar_chr(doc$name), label = dsj_scalar_chr(doc$label)
    )
  } else if (is.list(doc$itemGroupData) && length(doc$itemGroupData) > 0) {
    ig <- doc$itemGroupData[[1]]
    nm <- dsj_scalar_chr(ig$name)
    list(
      columns = ig$columns, rows = ig$rows, records = ig$records,
      name = if (!is.na(nm) && nzchar(nm)) nm else names(doc$itemGroupData)[1],
      label = dsj_scalar_chr(ig$label)
    )
  } else {
    NULL
  }
}

dsj_schema_stop <- function(path, ...) {
  stop("'", path, "' does not conform to the Dataset-JSON schema: ", ..., call. = FALSE)
}

dsj_scalar_chr <- function(x) {
  if (is.null(x) || length(x) == 0) NA_character_ else as.character(x)[1]
}

dsj_scalar_num <- function(x) {
  if (is.null(x) || length(x) == 0) NA_integer_ else suppressWarnings(as.integer(x)[1])
}

dsj_cell <- function(row, i) if (length(row) >= i) row[[i]] else NULL

dsj_coerce_values <- function(values, col) {
  dt <- tolower(dsj_scalar_chr(col$dataType))
  tdt <- dsj_scalar_chr(col$targetDataType)
  if (dt %in% c("integer", "float", "double", "decimal")) {
    return(vapply(values, dsj_num_or_na, numeric(1)))
  }
  if (identical(dt, "boolean")) {
    return(vapply(values, dsj_lgl_or_na, logical(1)))
  }
  chars <- vapply(values, dsj_chr_or_na, character(1))
  if (dt %in% c("date", "datetime", "time")) dsj_parse_temporal(chars, tdt) else chars
}

dsj_num_or_na <- function(v) {
  if (is.null(v) || length(v) == 0) NA_real_ else suppressWarnings(as.numeric(v)[1])
}

dsj_lgl_or_na <- function(v) {
  if (is.null(v) || length(v) == 0) NA else suppressWarnings(as.logical(v)[1])
}

dsj_chr_or_na <- function(v) {
  if (is.null(v) || length(v) == 0) NA_character_ else as.character(v)[1]
}

# Typed conversion for date/datetime/time columns. All-or-nothing per column:
# any unparseable non-missing value (e.g. partial SDTM dates) keeps the whole
# column as character. On success the original strings are kept in the
# 'raw' attribute.
dsj_parse_temporal <- function(chars, target_data_type) {
  non_missing <- !is.na(chars) & nzchar(chars)
  if (identical(target_data_type, "Date")) {
    parsed <- rep(as.Date(NA_character_), length(chars))
    parsed[non_missing] <- suppressWarnings(as.Date(chars[non_missing]))
  } else if (identical(target_data_type, "Datetime")) {
    parsed <- rep(as.POSIXct(NA_character_, tz = "UTC"), length(chars))
    # ISO 8601 "T" separator and trailing "Z" are not handled by as.POSIXct()
    # format guessing (the time part would be silently dropped)
    norm <- sub("T", " ", sub("Z$", "", chars), fixed = TRUE)
    parsed[non_missing] <- suppressWarnings(as.POSIXct(norm[non_missing], tz = "UTC"))
  } else {
    return(chars)
  }
  if (any(is.na(parsed[non_missing]))) return(chars)
  attr(parsed, "raw") <- chars
  parsed
}
