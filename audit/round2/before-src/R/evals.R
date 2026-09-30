EVALS_CORPUS_FILE <- "spec-to-ir.jsonl"

evals_corpus_path <- function() {
  installed <- system.file("evals", EVALS_CORPUS_FILE, package = "admiralagent")
  if (nzchar(installed)) return(installed)
  dir <- getwd()
  for (i in seq_len(5)) {
    candidate <- file.path(dir, "inst", "evals", EVALS_CORPUS_FILE)
    if (file.exists(candidate)) return(candidate)
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }
  stop(
    "could not locate the evals corpus (inst/evals/", EVALS_CORPUS_FILE,
    "); install the package or run from within the package source tree",
    call. = FALSE
  )
}

#' Load the spec-to-IR classification eval corpus
#'
#' @description Reads `inst/evals/spec-to-ir.jsonl`, one JSON eval case per
#'   line, into a named list. Works both for an installed package (via
#'   [system.file()]) and from the package source tree (walking up from the
#'   working directory to find `inst/evals/`), so tests run uninstalled.
#' @param path Optional full path to a `.jsonl` corpus file. Defaults to the
#'   bundled corpus located automatically.
#' @return A named list of parsed eval cases (names are case ids). Each case
#'   has fields `id`, `dataset`, `spec_row`, `expected_layers`,
#'   `expected_needs_human`, and `note`.
#' @export
load_evals <- function(path = NULL) {
  if (is.null(path)) path <- evals_corpus_path()
  assert_path(path)
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]
  if (length(lines) == 0) {
    stop("evals corpus is empty: ", path, call. = FALSE)
  }
  cases <- lapply(seq_along(lines), function(i) {
    tryCatch(
      jsonlite::fromJSON(lines[[i]], simplifyVector = TRUE),
      error = function(e) stop(
        "evals corpus line ", i, " is not valid JSON: ", conditionMessage(e),
        call. = FALSE
      )
    )
  })
  ids <- vapply(cases, function(c) as.character(c$id), character(1))
  if (any(!nzchar(ids))) {
    stop("evals corpus contains cases without an id: ", path, call. = FALSE)
  }
  if (anyDuplicated(ids)) {
    stop(
      "duplicate eval case ids in corpus: ",
      paste(unique(ids[duplicated(ids)]), collapse = ", "),
      call. = FALSE
    )
  }
  stats::setNames(cases, ids)
}

evals_chr <- function(x) {
  if (is.null(x) || length(x) == 0) NA_character_ else as.character(x)[[1]]
}

evals_layers_label <- function(ir) {
  if (isTRUE(ir$needs_human)) return("needs_human")
  paste(vapply(ir$steps, function(s) s$layer, character(1)), collapse = ",")
}

#' Run the spec-to-IR classification evals
#'
#' @description Executes every corpus case for one dataset: builds a one-row
#'   spec data frame per case, classifies it with [classify_variables()], and
#'   compares the produced step-layer sequence (`"needs_human"` when the
#'   classifier abstains) against the expected sequence. Prints a summary and
#'   returns the per-case results invisibly. This is the package's
#'   production-consistency regression gate: the `rules` backend must score
#'   accuracy 1.0 against the corpus.
#' @param backend Classifier backend, `"rules"` (default, deterministic,
#'   offline) or `"llm"` (requires `chat`).
#' @param chat ellmer chat object; required when `backend = "llm"`, ignored
#'   otherwise.
#' @param dataset Dataset tag of the corpus cases to run (default `"ADSL"`).
#' @return A data.frame (invisibly) with columns `id`, `variable`,
#'   `expected`, `got`, `ok`.
#' @export
run_evals <- function(backend = c("rules", "llm"), chat = NULL, dataset = "ADSL") {
  backend <- match.arg(backend)
  if (backend == "llm" && is.null(chat)) {
    stop(
      "backend = 'llm' requires an ellmer chat object, ",
      "e.g. chat <- ellmer::chat_anthropic()",
      call. = FALSE
    )
  }
  cases <- load_evals()
  cases <- cases[vapply(cases, function(c) identical(as.character(c$dataset), dataset), logical(1))]
  if (length(cases) == 0) {
    stop("no eval cases found for dataset '", dataset, "'", call. = FALSE)
  }

  results <- lapply(cases, function(c) {
    row <- c$spec_row
    spec_df <- read_spec_df(data.frame(
      dataset = as.character(c$dataset),
      variable = evals_chr(row$variable),
      label = evals_chr(row$label),
      type = evals_chr(row$type),
      origin = evals_chr(row$origin),
      derivation = evals_chr(row$derivation),
      source_dataset = evals_chr(row$source_dataset),
      source_variable = evals_chr(row$source_variable),
      stringsAsFactors = FALSE
    ))
    ir <- classify_variables(spec_df, dataset = as.character(c$dataset), backend = backend, chat = chat)
    got <- evals_layers_label(ir[[1]])
    expected <- if (isTRUE(c$expected_needs_human)) {
      "needs_human"
    } else {
      paste(as.character(c$expected_layers), collapse = ",")
    }
    list(
      id = as.character(c$id),
      variable = evals_chr(row$variable),
      expected = expected,
      got = got,
      ok = identical(got, expected)
    )
  })

  out <- data.frame(
    id = vapply(results, `[[`, character(1), "id"),
    variable = vapply(results, `[[`, character(1), "variable"),
    expected = vapply(results, `[[`, character(1), "expected"),
    got = vapply(results, `[[`, character(1), "got"),
    ok = vapply(results, `[[`, logical(1), "ok"),
    stringsAsFactors = FALSE
  )
  message(sprintf(
    "evals: %d/%d correct (accuracy %.3f) [backend = %s, dataset = %s]",
    sum(out$ok), nrow(out), evals_accuracy(out), backend, dataset
  ))
  invisible(out)
}

#' Accuracy of an eval run
#'
#' @description Extracts the accuracy from a result data.frame returned by
#'   [run_evals()].
#' @param res data.frame with a logical `ok` column, as returned by
#'   [run_evals()].
#' @return A single numeric in `[0, 1]`: the share of cases classified as
#'   expected.
#' @export
evals_accuracy <- function(res) {
  if (!is.data.frame(res) || !"ok" %in% names(res) || !is.logical(res$ok) || anyNA(res$ok) || !nrow(res)) stop("res must be a non-empty data.frame with a logical ok column without NA", call. = FALSE)
  as.numeric(mean(res$ok))
}
