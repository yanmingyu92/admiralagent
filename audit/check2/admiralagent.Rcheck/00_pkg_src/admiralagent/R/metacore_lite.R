#' Build a codelist data.frame from observed data values
#'
#' @description
#' Builds a minimal `code`/`decode` codelist data.frame from the unique
#' values of `data[[var]]`: `decode` is `sort(unique(...))` of the non-missing
#' values and `code` is `seq_along(decode)`. The result is suitable as an
#' entry of the `codelists` argument of [mock_metacore()], e.g.
#' `codelists = list(RACE = codelist_from_data("RACE", dm))`.
#'
#' @param var Character, name of the column in `data` holding the decode
#'   values (e.g. `"RACE"`).
#' @param data A data.frame containing `var`.
#'
#' @return A data.frame with columns `code` (integer) and `decode`
#'   (character), one row per unique non-missing value, sorted by decode.
#'
#' @export
codelist_from_data <- function(var, data) {
  if (!is.character(var) || length(var) != 1L || !nzchar(var)) {
    stop("var must be a single non-empty character string", call. = FALSE)
  }
  if (!is.data.frame(data) || !var %in% names(data)) {
    stop("data must be a data.frame containing column '", var, "'", call. = FALSE)
  }
  vals <- unique(as.character(data[[var]]))
  vals <- sort(vals[!is.na(vals)])
  data.frame(code = seq_along(vals), decode = vals, stringsAsFactors = FALSE)
}

#' Build a minimal executable metacore object from a spec data frame
#'
#' @description
#' Constructs a `Metacore` object via [metacore::metacore()] from a
#' `read_spec_df()`-compatible spec data frame plus user-supplied codelists,
#' so that `codelist_var` layer code (i.e.
#' [metatools::create_var_from_codelist()]) runs in demos/tests without a
#' vendor P21 spec.
#'
#' Codelist linking: a spec variable is linked to codelist `N` when the spec
#' `codelist` column equals `N`, or when the variable's derivation text
#' mentions `N` (word boundary, case-insensitive; e.g. "using the RACE
#' codelist" links to `RACE`). Real decodes cannot be invented from the spec
#' text: supply `codelists` (built by hand or with [codelist_from_data()]);
#' variables whose derivation mentions a codelist but have no matching entry
#' get no `code_id` and emit a warning.
#'
#' When the spec covers exactly one dataset, the returned object is already
#' subsetted with [metacore::select_dataset()] so it can be passed directly
#' as `metacore = mc` to metatools; with multiple datasets the full object is
#' returned and the caller subsets it.
#'
#' @param spec_df Spec data.frame compatible with [read_spec_df()] (columns
#'   dataset, variable, label, type, origin, derivation; optional length,
#'   codelist).
#' @param codelists Named list of codelists, each a data.frame with columns
#'   `code` and `decode` (e.g. `list(RACE = codelist_from_data("RACE", dm))`).
#'   The list name becomes the metacore `code_id`.
#'
#' @return A `Metacore` object (single-dataset specs: subsetted via
#'   `select_dataset()`; multi-dataset specs: full object). NULL with a
#'   warning if `metacore` is not installed.
#'
#' @export
mock_metacore <- function(spec_df, codelists = list()) {
  if (!requireNamespace("metacore", quietly = TRUE)) {
    warning("mock_metacore() needs package 'metacore'; returning NULL", call. = FALSE)
    return(invisible(NULL))
  }
  spec_df <- read_spec_df(spec_df)

  if (!is.list(codelists)) {
    stop("codelists must be a named list of data.frames with columns code/decode", call. = FALSE)
  }
  for (nm in names(codelists)) {
    cl <- codelists[[nm]]
    if (!is.data.frame(cl) || !all(c("code", "decode") %in% names(cl))) {
      stop("codelists$", nm, " must be a data.frame with columns code/decode", call. = FALSE)
    }
  }

  link_code_id <- function(row) {
    if (!is.na(row$codelist) && nzchar(row$codelist)) return(row$codelist)
    text <- tolower(paste(row$derivation))
    hit <- vapply(names(codelists), function(nm) {
      grepl(paste0("\\b", tolower(nm), "\\b"), text)
    }, logical(1))
    if (any(hit)) names(codelists)[which(hit)[1]] else NA_character_
  }
  code_ids <- vapply(seq_len(nrow(spec_df)), function(i) link_code_id(spec_df[i, ]),
                     character(1))
  missing_cl <- spec_df$variable[is.na(code_ids) & grepl("codelist", tolower(spec_df$derivation))]
  if (length(missing_cl) > 0) {
    warning(
      "no codelist supplied for variable(s): ", paste(missing_cl, collapse = ", "),
      "; they get no code_id and codelist_var execution will fail for them",
      call. = FALSE
    )
  }

  type_map <- function(x) {
    x <- tolower(ifelse(is.na(x), "text", x))
    ifelse(x %in% c("integer", "int", "numeric"), "integer",
           ifelse(x %in% c("float", "double"), "float", x))
  }

  tb <- tibble::as_tibble
  tbc <- tibble::tibble
  derivation_id <- as.character(seq_len(nrow(spec_df)))

  # metacore's validator warns about the (deliberately) all-NA optional
  # columns of a minimal mock (key_seq, length, format, ...); suppress that
  # noise - genuine construction errors still propagate
  mc <- suppressWarnings(metacore::metacore(
    ds_spec = tb(data.frame(
      dataset = unique(spec_df$dataset),
      structure = "one record per subject",
      label = paste("Mock", unique(spec_df$dataset), "spec"),
      stringsAsFactors = FALSE
    )),
    ds_vars = tb(data.frame(
      dataset = spec_df$dataset,
      variable = spec_df$variable,
      keep = TRUE,
      mandatory = TRUE,
      key_seq = NA_integer_,
      order = seq_len(nrow(spec_df)),
      core = "Required",
      supp_flag = FALSE,
      stringsAsFactors = FALSE
    )),
    var_spec = tb(data.frame(
      variable = spec_df$variable,
      label = ifelse(is.na(spec_df$label), spec_df$variable, spec_df$label),
      length = suppressWarnings(as.integer(spec_df$length)),
      type = type_map(spec_df$type),
      common = NA,
      format = NA_character_,
      stringsAsFactors = FALSE
    )),
    value_spec = tb(data.frame(
      dataset = spec_df$dataset,
      variable = spec_df$variable,
      where = NA_character_,
      type = type_map(spec_df$type),
      sig_dig = NA_integer_,
      code_id = code_ids,
      origin = ifelse(is.na(spec_df$origin), "derived", tolower(spec_df$origin)),
      derivation_id = derivation_id,
      stringsAsFactors = FALSE
    )),
    derivations = tb(data.frame(
      derivation_id = derivation_id,
      derivation = ifelse(is.na(spec_df$derivation), "", spec_df$derivation),
      stringsAsFactors = FALSE
    )),
    codelist = if (length(codelists) == 0) {
      tbc(code_id = character(), name = character(),
          type = character(), codes = list())
    } else {
      tbc(
        code_id = names(codelists),
        name = names(codelists),
        type = "code_decode",
        codes = unname(lapply(codelists, tb))
      )
    },
    supp = tb(data.frame(dataset = character(), variable = character(),
                         idvar = character(), qeval = character())),
    verbose = "silent"
  ))

  datasets <- unique(spec_df$dataset)
  if (length(datasets) == 1L) {
    suppressWarnings(suppressMessages(metacore::select_dataset(mc, datasets)))
  } else {
    mc
  }
}
