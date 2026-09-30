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
    case <- tryCatch(
      jsonlite::fromJSON(lines[[i]], simplifyVector = TRUE),
      error = function(e) stop(
        "evals corpus line ", i, " is not valid JSON: ", conditionMessage(e),
        call. = FALSE
      )
    )
    # `expected_args` is an array of heterogeneous objects; simplifyVector
    # would fold it into a data.frame and silently transpose args into
    # columns. Re-read just this field structurally.
    if (!is.null(case$expected_args)) {
      case$expected_args <- jsonlite::fromJSON(
        lines[[i]], simplifyVector = FALSE
      )$expected_args
    }
    case
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

# Structural JSON parsing leaves every array as a list; a classifier produces
# atomic vectors. Collapse uniform scalar lists so the two serialize the same
# way, and leave anything ragged alone.
evals_simplify_args <- function(args) {
  lapply(args, function(x) {
    if (!is.list(x) || !length(x)) return(x)
    if (all(vapply(x, function(e) is.atomic(e) && length(e) == 1L, logical(1)))) {
      return(unlist(x, use.names = FALSE))
    }
    x
  })
}

# The expected IR of a corpus case, as a bare shape rather than a validated
# `aa_variable_ir`. `canonical_variable_ir()` reads only dataset/variable/
# needs_human/steps, so a shape is enough to fingerprint - and building a shape
# avoids minting an IR that would have to pass `validate_ir()` even though it is
# only ever compared, never rendered or executed.
evals_expected_shape <- function(case) {
  layers <- as.character(case$expected_layers)
  args <- case$expected_args
  list(
    dataset = as.character(case$dataset),
    variable = evals_chr(case$spec_row$variable),
    needs_human = isTRUE(case$expected_needs_human),
    steps = lapply(seq_along(layers), function(i) {
      list(
        layer = layers[[i]],
        args = if (length(args) >= i) evals_simplify_args(args[[i]]) else list()
      )
    })
  )
}

# Args-aware verdict for one case. `expected_args` pins every argument, so a
# backend that produces the right layer chain with the wrong arguments now
# FAILS - which is exactly what `evals_layers_label()` alone could never see.
# Cases without `expected_args` fall back to the layer-name comparison so an
# older corpus still loads.
evals_case_ok <- function(case, ir) {
  if (isTRUE(case$expected_needs_human) || isTRUE(ir$needs_human)) {
    return(identical(isTRUE(case$expected_needs_human), isTRUE(ir$needs_human)))
  }
  if (is.null(case$expected_args)) {
    return(identical(evals_layers_label(ir), paste(as.character(case$expected_layers), collapse = ",")))
  }
  identical(
    ir_fingerprint(ir, "full"),
    ir_fingerprint(evals_expected_shape(case), "full")
  )
}

# Minimal grouping of corpus cases into batches with unique dataset::variable
# keys. The corpus deliberately contains the SAME variable derived different
# ways (TRTSDTM appears twice, TRTEDTM twice, BMIBL twice) because those pairs
# are the whole point of an args-aware corpus - but `align_batch()` rejects a
# batch with duplicate keys, so a literal single batch is impossible. Two
# groups is the minimum here, versus 24 one-row calls before.
evals_case_groups <- function(cases) {
  keys <- vapply(cases, function(c) {
    paste(as.character(c$dataset), evals_chr(c$spec_row$variable), sep = "::")
  }, character(1))
  group <- integer(length(cases))
  for (i in seq_along(cases)) {
    taken <- keys[seq_len(i - 1L)][group[seq_len(i - 1L)] > 0L]
    g <- 1L
    repeat {
      used <- keys[seq_len(i - 1L)][group[seq_len(i - 1L)] == g]
      if (!keys[[i]] %in% used) break
      g <- g + 1L
    }
    group[i] <- g
  }
  split(seq_along(cases), group)
}

evals_spec_df <- function(cases) {
  rows <- lapply(cases, function(c) {
    row <- c$spec_row
    data.frame(
      dataset = as.character(c$dataset),
      variable = evals_chr(row$variable),
      label = evals_chr(row$label),
      type = evals_chr(row$type),
      origin = evals_chr(row$origin),
      derivation = evals_chr(row$derivation),
      source_dataset = evals_chr(row$source_dataset),
      source_variable = evals_chr(row$source_variable),
      stringsAsFactors = FALSE
    )
  })
  read_spec_df(do.call(rbind, rows))
}

# Classify a set of corpus cases with one `classify_variables()` call per
# group (see `evals_case_groups()`), preserving corpus order in the result.
evals_classify <- function(cases, backend, chat = NULL, ...) {
  groups <- evals_case_groups(cases)
  extra <- list(...)
  out <- vector("list", length(cases))
  for (g in groups) {
    vars <- evals_spec_df(cases[g])
    ir <- if (identical(backend, "llm") && length(extra)) {
      # `classify_variables()` exposes no samples/consensus/prompt_variant, so
      # multi-sample voting is unreachable through it. Go straight to the LLM
      # classifier when a voter asks for those, keeping one call per group.
      do.call(classify_variables_llm, c(
        list(vars = vars, chat = chat, batch_size = nrow(vars)), extra
      ))
    } else {
      classify_variables(
        vars,
        dataset = as.character(cases[[g[[1]]]]$dataset),
        backend = backend, chat = chat
      )
    }
    out[g] <- ir
  }
  out
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

  irs <- evals_classify(cases, backend = backend, chat = chat)

  results <- lapply(seq_along(cases), function(i) {
    c <- cases[[i]]
    ir <- irs[[i]]
    expected <- if (isTRUE(c$expected_needs_human)) {
      "needs_human"
    } else {
      paste(as.character(c$expected_layers), collapse = ",")
    }
    list(
      id = as.character(c$id),
      variable = evals_chr(c$spec_row$variable),
      expected = expected,
      got = evals_layers_label(ir),
      ok = evals_case_ok(c, ir)
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

AGREEMENT_LEVELS <- c("abstention", "layer_chain", "full")

# Every credential an LLM voter could plausibly need. Named explicitly so a
# failure message tells the operator exactly what to set rather than leaving
# them to guess - an empty agreement table must never be mistaken for a
# measured result of "the backends agree".
AGREEMENT_CREDENTIAL_VARS <- c(
  "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY",
  "AZURE_OPENAI_API_KEY", "OPENROUTER_API_KEY", "GROQ_API_KEY",
  "AWS_ACCESS_KEY_ID", "OLLAMA_HOST"
)

agreement_credentials_available <- function() {
  any(nzchar(Sys.getenv(AGREEMENT_CREDENTIAL_VARS)))
}

# One voter = one backend plus, for LLM voters, a prompt variant. Voters must
# differ in their convention-asserting clauses (see
# `build_system_prompt_variant()`); two voters sharing the `full` prompt
# measure prompt compliance, not independent agreement.
normalize_voter <- function(v, name) {
  if (is.character(v) && length(v) == 1L) v <- list(backend = v)
  if (!is.list(v) || is.null(v$backend)) {
    stop("voter '", name, "' must be a backend name or a list with a `backend` field", call. = FALSE)
  }
  v$backend <- match.arg(as.character(v$backend), c("rules", "llm"))
  if (identical(v$backend, "llm")) {
    if (is.null(v$chat) && !agreement_credentials_available()) {
      stop(
        "voter '", name, "' needs an LLM backend but no credentials are present. ",
        "run_agreement() looked for: ", paste(AGREEMENT_CREDENTIAL_VARS, collapse = ", "),
        ". Supply an ellmer chat object via voters[['", name, "']]$chat, or set one ",
        "of those variables. Refusing to return an agreement table that was not measured.",
        call. = FALSE
      )
    }
    v$prompt_variant <- v$prompt_variant %||% "full"
  }
  v
}

agreement_classify_voter <- function(cases, voter) {
  if (identical(voter$backend, "rules")) {
    return(evals_classify(cases, backend = "rules"))
  }
  evals_classify(
    cases, backend = "llm", chat = voter$chat,
    samples = voter$samples %||% 1L,
    consensus = voter$consensus %||% "majority",
    prompt_variant = voter$prompt_variant %||% "full"
  )
}

#' Cross-tabulate classification backends at every fingerprint level
#'
#' @description Classifies the eval corpus once per voter and cross-tabulates
#'   the resulting IRs at all three [ir_fingerprint()] levels (`abstention`,
#'   `layer_chain`, `full`). Voters are independent classifier configurations;
#'   LLM voters should differ in model family AND in prompt variant, because
#'   two voters sharing one convention-asserting prompt measure prompt
#'   compliance rather than agreement. Fails loudly, naming every credential
#'   environment variable it looked for, when an LLM voter cannot actually be
#'   run - an unmeasured result must never be readable as a measured one.
#' @param voters Named list of voters. Each is either a backend name
#'   (`"rules"`, `"llm"`) or a list with `backend` and optionally `chat`,
#'   `prompt_variant`, `samples`, `consensus`.
#' @param dataset Dataset tag of the corpus cases to run (default `"ADSL"`).
#' @return An `aa_agreement` list with `dataset`, `voters`, `per_case` (one row
#'   per case per level with each voter's fingerprint and an `agree` flag),
#'   `rates` (agreement rate per level) and `crosstab` (per level, a
#'   contingency table of the first two voters' human-readable labels).
#' @noRd
run_agreement <- function(voters, dataset = "ADSL") {
  if (!is.list(voters) || length(voters) < 2L || is.null(names(voters)) || any(!nzchar(names(voters)))) {
    stop("`voters` must be a named list of at least two voters", call. = FALSE)
  }
  voters <- stats::setNames(
    lapply(names(voters), function(n) normalize_voter(voters[[n]], n)),
    names(voters)
  )

  cases <- load_evals()
  cases <- cases[vapply(cases, function(c) identical(as.character(c$dataset), dataset), logical(1))]
  if (length(cases) == 0) {
    stop("no eval cases found for dataset '", dataset, "'", call. = FALSE)
  }

  irs <- lapply(voters, agreement_classify_voter, cases = cases)
  ids <- vapply(cases, function(c) as.character(c$id), character(1))

  per_case <- do.call(rbind, lapply(AGREEMENT_LEVELS, function(lv) {
    fp <- vapply(irs, function(v) {
      vapply(v, function(ir) ir_fingerprint(ir, lv), character(1))
    }, character(length(cases)))
    fp <- matrix(fp, nrow = length(cases), dimnames = list(NULL, names(voters)))
    df <- data.frame(id = ids, level = lv, stringsAsFactors = FALSE)
    for (n in names(voters)) df[[n]] <- fp[, n]
    df$agree <- apply(fp, 1, function(r) length(unique(r)) == 1L)
    df
  }))
  row.names(per_case) <- NULL

  rates <- vapply(AGREEMENT_LEVELS, function(lv) {
    mean(per_case$agree[per_case$level == lv])
  }, numeric(1))

  first_two <- names(voters)[1:2]
  crosstab <- stats::setNames(lapply(AGREEMENT_LEVELS, function(lv) {
    labs <- lapply(first_two, function(n) {
      vapply(irs[[n]], function(ir) agreement_label(ir, lv), character(1))
    })
    table(stats::setNames(labs, first_two))
  }), AGREEMENT_LEVELS)

  structure(
    list(dataset = dataset, voters = names(voters), per_case = per_case,
         rates = rates, crosstab = crosstab),
    class = c("aa_agreement", "list")
  )
}

# Human-readable counterpart of `ir_fingerprint()` for contingency tables.
agreement_label <- function(ir, level) {
  switch(level,
    abstention = if (isTRUE(ir$needs_human) || !length(ir$steps)) "abstain" else "derived",
    layer_chain = if (isTRUE(ir$needs_human)) "needs_human" else evals_layers_label(ir),
    full = substr(ir_fingerprint(ir, "full"), 1, 8)
  )
}

#' How much an args-blind label overstates agreement
#'
#' @description The defect this harness exists to quantify: comparing only the
#'   layer-name sequence counts two voters as agreeing whenever they pick the
#'   same layers, even when every argument differs. This reports the gap
#'   between the `layer_chain` and `full` agreement rates - i.e. the share of
#'   cases the old [evals_layers_label()] comparison would have scored as
#'   agreement but which differ semantically.
#' @param res An `aa_agreement` object from `run_agreement()`.
#' @return A list with `layer_chain`, `full`, `overstatement` (the difference)
#'   and `cases` (the ids counted as agreeing only at `layer_chain`).
#' @noRd
agreement_overstatement <- function(res) {
  lc <- res$per_case[res$per_case$level == "layer_chain", ]
  fl <- res$per_case[res$per_case$level == "full", ]
  inflated <- lc$id[lc$agree & !fl$agree[match(lc$id, fl$id)]]
  list(
    layer_chain = unname(res$rates[["layer_chain"]]),
    full = unname(res$rates[["full"]]),
    overstatement = unname(res$rates[["layer_chain"]] - res$rates[["full"]]),
    cases = inflated
  )
}

#' Resolution lost by the args-blind label, measured on the corpus alone
#'
#' @description Backend-free, credential-free measurement of the same defect.
#'   Counts how many semantically distinct corpus cases collapse onto a shared
#'   layer-name label. Every such collision is a pair of derivations that two
#'   voters could produce and that [evals_layers_label()] would score as
#'   agreement. Needs no LLM: it is a property of the corpus and the label.
#' @param dataset Optional dataset tag; `NULL` (default) uses the whole corpus.
#' @return A list with `n_cases`, `n_layer_labels`, `n_full`,
#'   `colliding_cases` and `collisions` (the label groups that collide).
#' @noRd
evals_label_resolution <- function(dataset = NULL) {
  cases <- load_evals()
  if (!is.null(dataset)) {
    cases <- cases[vapply(cases, function(c) identical(as.character(c$dataset), dataset), logical(1))]
  }
  shapes <- lapply(cases, evals_expected_shape)
  labels <- vapply(cases, function(c) {
    if (isTRUE(c$expected_needs_human)) "needs_human"
    else paste(as.character(c$expected_layers), collapse = ",")
  }, character(1))
  full <- vapply(shapes, ir_fingerprint, character(1), level = "full")
  key <- paste(vapply(cases, function(c) as.character(c$dataset), character(1)), labels, sep = "::")
  groups <- split(seq_along(cases), key)
  colliding <- Filter(function(g) length(unique(full[g])) > 1L, groups)
  list(
    n_cases = length(cases),
    n_layer_labels = length(unique(key)),
    n_full = length(unique(paste(key, full))),
    colliding_cases = sum(vapply(colliding, length, integer(1))),
    collisions = lapply(colliding, function(g) names(cases)[g])
  )
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
