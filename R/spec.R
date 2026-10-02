SPEC_REQUIRED_COLS <- c("dataset", "variable", "label", "type", "origin", "derivation")

#' Normalize a flat spec data frame
#'
#' @description Validates that a flat (already parsed) spec data frame carries
#'   the required columns, fills optional columns (`length`, `codelist`,
#'   `source_dataset`, `source_variable`, `order`) with `NA` when absent, and
#'   defactors all columns. This is the canonical in-memory spec format all
#'   downstream functions accept.
#' @title Normalize spec data frame
#' @param df data.frame with columns dataset, variable, label, type, origin,
#'   derivation.
#' @return The normalized data frame (error when required columns are missing).
#' @export
read_spec_df <- function(df) {
  if (!is.data.frame(df)) stop("spec must be a data.frame with required columns", call. = FALSE)
  if (anyNA(names(df)) || any(!nzchar(names(df))) || anyDuplicated(names(df))) stop("spec column names must be non-empty and unique", call. = FALSE)
  missing <- setdiff(SPEC_REQUIRED_COLS, names(df))
  if (length(missing) > 0) {
    stop("spec data frame is missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  optional <- c("length", "codelist", "source_dataset", "source_variable", "order")
  for (col in optional) {
    if (!col %in% names(df)) df[[col]] <- rep(NA_character_, nrow(df))
  }
  for (col in c(SPEC_REQUIRED_COLS, optional)) {
    if (!is.atomic(df[[col]]) || !is.null(dim(df[[col]]))) stop("spec column '", col, "' must contain scalar cells, not lists or matrices", call. = FALSE)
  }
  df[] <- lapply(df, function(x) if (is.factor(x)) as.character(x) else x)
  df
}

#' Extract one dataset's spec rows
#'
#' @description Subsets a spec data frame to the rows of one dataset.
#' @title Spec rows for a dataset
#' @param spec Spec data.frame compatible with [read_spec_df()].
#' @param dataset Dataset name to subset to (e.g. `"ADSL"`).
#' @return The subset spec data frame; errors when no rows match.
#' @export
spec_variables <- function(spec, dataset) {
  spec <- read_spec_df(spec)
  if (!scalar_text(dataset) || !nzchar(dataset)) stop("dataset must be one non-empty string", call. = FALSE)
  out <- spec[spec$dataset == dataset & !is.na(spec$dataset), , drop = FALSE]
  if (nrow(out) == 0) {
    stop("no spec rows found for dataset '", dataset, "'", call. = FALSE)
  }
  out
}

#' Read a P21-style specification workbook
#'
#' @description Parses a specifications.xlsx-style workbook via
#'   [metacore::spec_to_metacore()] and flattens the result into the package's
#'   spec data frame format. Requires the `metacore` and `readxl` packages.
#' @title Read spec workbook
#' @param path Path to the specification workbook.
#' @param dataset Optional dataset name to subset to.
#' @param where_sep_sheet Whether the where clauses are on a separate sheet.
#' @param verbose metacore verbosity, one of `"silent"`, `"verbose"`.
#' @return A spec data frame as produced by [read_spec_df()].
#' @export
read_spec <- function(path, dataset = NULL, where_sep_sheet = "Datasets", verbose = "silent") {
  assert_path(path)
  if (!requireNamespace("metacore", quietly = TRUE) || !requireNamespace("readxl", quietly = TRUE)) {
    stop(
      "read_spec() needs packages 'metacore' and 'readxl'. ",
      "Install them, or use read_spec_df() with a flat data frame instead.",
      call. = FALSE
    )
  }
  mc <- tryCatch(
    metacore::spec_to_metacore(path, where_sep_sheet = where_sep_sheet, verbose = verbose),
    error = function(e) stop("metacore::spec_to_metacore() failed: ", conditionMessage(e), call. = FALSE)
  )
  spec_as_df(mc, dataset)
}

#' Read a define.xml metadata file
#'
#' @description Primary path: parses the define.xml directly with
#'   [parse_define()] (requires the `xml2` package), which preserves the
#'   per-variable derivation text from `MethodDef` elements - metadata that
#'   [metacore::define_to_metacore()] drops for some define versions (e.g. the
#'   CDISC pilot submission defines). Fallback path: when the direct parser
#'   fails (missing `xml2`, malformed XML, non-ODM structure), the file is
#'   re-parsed via metacore and flattened through `spec_as_df()`, whose
#'   `derivation` column may then be empty. When both paths fail an informative
#'   error is raised.
#' @title Read define.xml
#' @param path Path to the define.xml file.
#' @return A spec data frame as produced by [read_spec_df()]; the primary path
#'   additionally returns `codelist_oid` and `order` columns.
#' @export
read_define <- function(path) {
  assert_path(path)
  parsed <- tryCatch(
    parse_define(path),
    error = function(e) {
      message(
        "read_define(): direct define parser failed (", conditionMessage(e),
        "); falling back to metacore::define_to_metacore()"
      )
      NULL
    }
  )
  if (!is.null(parsed)) return(parsed)
  if (!requireNamespace("metacore", quietly = TRUE)) {
    stop(
      "read_define() failed: the direct parser did not run and fallback ",
      "package 'metacore' is not installed", call. = FALSE
    )
  }
  mc <- tryCatch(
    metacore::define_to_metacore(path, verbose = "silent"),
    error = function(e) {
      tryCatch(
        metacore::define_to_metacore(path),
        error = function(e2) stop("define_to_metacore() failed: ", conditionMessage(e2), call. = FALSE)
      )
    }
  )
  spec_as_df(mc)
}

spec_as_df <- function(mc, dataset = NULL) {
  ds_vars <- as.data.frame(mc$ds_vars)
  var_spec <- as.data.frame(mc$var_spec)
  merged <- merge(ds_vars, var_spec, by = "variable", all.x = TRUE, sort = FALSE)
  deriv <- as.data.frame(mc$derivations)
  if (nrow(deriv) > 0) {
    deriv <- deriv[!duplicated(deriv$dataset), , drop = FALSE]
  }
  out <- data.frame(
    dataset = merged$dataset,
    variable = merged$variable,
    label = merged$label,
    type = merged$type,
    length = merged$length,
    origin = if ("origin" %in% names(merged)) merged$origin else NA_character_,
    derivation = NA_character_,
    stringsAsFactors = FALSE
  )
  if (nrow(deriv) > 0) {
    idx <- match(out$dataset, deriv$dataset)
    hit <- !is.na(idx)
    out$derivation[hit] <- deriv$derivation[idx[hit]]
  }
  if (!is.null(dataset)) out <- out[out$dataset == dataset, , drop = FALSE]
  read_spec_df(out)
}

#' Mock ADSL specification
#'
#' @description A 10-variable mock ADSL spec (STUDYID, USUBJID, SUBJID,
#'   TRT01P, TRTSDTM, TRTEDTM, AGE, AGEGR1, RACEN, BMIBL) with realistic
#'   free-text derivations, used in demos, tests, and the vignette.
#' @title Mock ADSL spec
#' @return A spec data frame as produced by [read_spec_df()].
#' @export
mock_spec_adsl <- function() {
  read_spec_df(data.frame(
    dataset = rep("ADSL", 10),
    variable = c(
      "STUDYID", "USUBJID", "SUBJID", "TRT01P",
      "TRTSDTM", "TRTEDTM", "AGE", "AGEGR1", "RACEN", "BMIBL"
    ),
    label = c(
      "Study Identifier", "Unique Subject Identifier", "Subject Identifier for the Study",
      "Planned Treatment", "Date of First Study Treatment", "Date of Last Study Treatment",
      "Age", "Age Group", "Race (N)", "Body Mass Index at Baseline"
    ),
    type = c("text", "text", "text", "text", "datetime", "datetime", "integer", "text", "integer", "float"),
    origin = c(
      "CRF", "CRF", "CRF", "Assigned",
      "Derived", "Derived", "Derived", "Assigned", "Derived", "Derived"
    ),
    derivation = c(
      "Copied directly from DM.STUDYID",
      "Copied directly from DM.USUBJID",
      "Copied directly from DM.SUBJID",
      "Planned treatment, copied from ARM in DM",
      "Date of first study treatment, imputed from DM RFSTDTC",
      "Date of last study treatment, imputed from DM RFENDTC",
      "Age in years between BRTHDT and TRTSDT, truncated (do not round up before birthday)",
      "Age group categories from AGE: <18, 18-64, >=65",
      "Numeric race code derived from RACE using the RACE codelist",
      "Body mass index at baseline = WEIGHT / (HEIGHT/100)^2 in kg/m2 from VS PARAMCD HEIGHT and WEIGHT"
    ),
    source_dataset = c("dm", "dm", "dm", "dm", "ex", "ex", NA, NA, NA, "vs"),
    source_variable = c("STUDYID", "USUBJID", "SUBJID", "ARM", "EXSTDTC", "EXSTDTC", NA, NA, NA, NA),
    stringsAsFactors = FALSE
  ))
}

#' Mock ADVS specification
#'
#' @description An 11-variable mock BDS spec (USUBJID, PARAMCD, PARAM, AVAL,
#'   AVALU, AVISIT, ABLFL, BASE, CHG, PCHG, ANRIND) exercising lookup joins,
#'   baseline flags, change-from-baseline arithmetic, and reference-range
#'   categorisation.
#' @title Mock ADVS spec
#' @return A spec data frame as produced by [read_spec_df()].
#' @keywords internal
mock_spec_advs <- function() {
  read_spec_df(data.frame(
    dataset = rep("ADVS", 11),
    variable = c(
      "USUBJID", "PARAMCD", "PARAM", "AVAL", "AVALU", "AVISIT",
      "ABLFL", "BASE", "CHG", "PCHG", "ANRIND"
    ),
    label = c(
      "Unique Subject Identifier", "Parameter Code", "Parameter Description",
      "Analysis Value", "Analysis Value Unit", "Analysis Visit",
      "Baseline Record Flag", "Baseline Value", "Change from Baseline",
      "Percent Change from Baseline", "Reference Range Indicator"
    ),
    type = c(
      "text", "text", "text", "float", "text", "text",
      "text", "float", "float", "float", "text"
    ),
    origin = c(
      "CRF", "Derived", "Derived", "Derived", "Derived", "Derived",
      "Derived", "Derived", "Derived", "Derived", "Derived"
    ),
    derivation = c(
      "Copied directly from VS.USUBJID",
      "Parameter code from VSTESTCD via VS test lookup",
      "Parameter description joined from lookup by VSTESTCD",
      "Analysis value copied from VSSTRESN",
      "Analysis unit copied from VSSTRESU",
      "Analysis visit from VISIT, SCREENING 1 mapped to SCREENING",
      "Baseline flag: last record with ADTM on or before TRTSDTM for each parameter, flagged Y",
      "Baseline value: AVAL of the record with ABLFL = Y for each parameter",
      "Change from baseline: AVAL - BASE",
      "Percent change from baseline: 100 * (AVAL - BASE) / BASE",
      "Reference range indicator: LOW if AVAL < 90, NORMAL 90-140, HIGH > 140 for SYSBP"
    ),
    source_dataset = c("vs", "vs", "vs", "vs", "vs", "vs", "vs", NA, NA, NA, NA),
    source_variable = c(
      "USUBJID", "VSTESTCD", "VSTESTCD", "VSSTRESN", "VSSTRESU",
      "VISIT", "VSDTC", NA, NA, NA, NA
    ),
    stringsAsFactors = FALSE
  ))
}

#' Mock ADTTE specification
#'
#' @description A 2-variable mock time-to-event spec (TTE, CNSR) exercising
#'   cross-dataset imputation (AESTDTC on `ae`), merge, and duration layers.
#' @title Mock ADTTE spec
#' @return A spec data frame as produced by [read_spec_df()].
#' @keywords internal
mock_spec_adtte <- function() {
  read_spec_df(data.frame(
    dataset = rep("ADTTE", 2),
    variable = c("TTE", "CNSR"),
    label = c(
      "Time to First Treatment-Emergent Adverse Event in Days",
      "Censoring Indicator"
    ),
    type = c("float", "integer"),
    origin = c("Derived", "Derived"),
    derivation = c(
      "Time to first treatment-emergent AE in days from TRTSDTM to first AESTDTC, earliest per subject",
      "Censoring indicator: 1 if no event, 0 if event occurred"
    ),
    source_dataset = c("ae", NA),
    source_variable = c("AESTDTC", NA),
    stringsAsFactors = FALSE
  ))
}
