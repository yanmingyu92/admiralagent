#' Build schema-only LLM context
#'
#' @description Converts spec rows into a per-variable list of schema fields
#'   (variable, label, type, origin, derivation, source pointers). No patient
#'   data ever enters the context.
#' @title Build LLM context
#' @param vars Spec data frame subset from [spec_variables()].
#' @return A named list (by variable name) of schema-only field lists.
#' @export
build_context <- function(vars) {
  vars <- read_spec_df(vars)
  rows <- lapply(seq_len(nrow(vars)), function(i) {
    row <- vars[i, ]
    list(
      variable = row$variable,
      label = row$label,
      type = row$type,
      origin = row$origin,
      derivation = row$derivation,
      source_dataset = row$source_dataset,
      source_variable = row$source_variable
    )
  })
  stats::setNames(rows, vars$variable)
}

#' Build the LLM system prompt
#'
#' @description Assembles the translation prompt: role definition, the full
#'   layer vocabulary from [layer_docs()], the strict JSON output contract
#'   with an example object, and the hard rules (closed vocabulary, `on`
#'   placement, formula whitelists, merge_var for cross-dataset values,
#'   needs_human abstention).
#' @title Build system prompt
#' @return A single character string.
#' @export
build_system_prompt <- function() {
  paste0(
    "You are a CDISC ADaM specification translator. Your ONLY job is to map each ",
    "spec variable's free-text derivation onto the layer IR vocabulary below. ",
    "You never invent new operations, fields, or schema.\n\n",
    "## Layer vocabulary (single source of truth)\n\n",
    paste(layer_docs(), collapse = "\n\n"),
    "\n\n## Output format\n\n",
    "Return a STRICT JSON array, one object per input variable, each with fields: ",
    "dataset, variable, steps (array of {layer, args}), confidence (0-1), ",
    "needs_human (bool), rationale, spec_origin (verbatim copy of the input derivation text).\n\n",
    "Example object:\n",
    '{"dataset":"ADSL","variable":"TRTSDTM","steps":[{"layer":"merge_var","args":',
    '{"target":"TRTSDTM","source":"EXSTDTM","dataset_add":"ex","by_vars":["STUDYID","USUBJID"],',
    '"order":["EXSTDTM"],"mode":"first","filter":"EXDOSE > 0"}}],"confidence":0.9,',
    '"needs_human":false,"rationale":"first qualifying exposure","spec_origin":"..."}\n\n',
    "## Hard rules\n\n",
    "Security gate: filter/restrict_filter allow only uppercase variable names, numbers, quoted values, comparison/logical and arithmetic operators and parentheses. No function calls, backticks, comments, assignments, indexing, namespaces or semicolons. Formula allows arithmetic only; compute_var also rejects parentheses.\n",
    "Use uppercase column identifiers; dataset object identifiers may be lowercase. Strings are at most 16384 bytes. Args must match registry types; unknown args and NULL are invalid. Empty steps require needs_human=true.\n",
    "dtm_to_dt target must equal source with DTM replaced by DT. impute_dtc target must end in DT/DTM matching output_class and must differ from dtc. Breakpoints must strictly increase; date_shift days must be finite integers.\n",
    "RFSTDTC/RFENDTC character predecessor copies remain assign steps. Nonstandard date targets require human review. Spec inputs must be data.frames with the documented required columns.\n",
    "Execution uses explicit source datasets only. Partial variables selection runs only named variables; supply prior results and required columns in sources.\n",
    "1. `layer` values MUST be exactly one of: ", paste(layer_names(), collapse = ", "), ".\n",
    "2. Chain derivations in `steps` in execution order; a step that prepares a source ",
    "dataset puts `on` INSIDE `args`, e.g. ",
    '{"layer":"impute_dtc","args":{"target":"EXSTDTM","dtc":"EXSTDTC","on":"ex",...}}',
    " to run on object `ex` instead of the target dataset.\n",
    "3. compute_param `formula` may ONLY reference AVAL.<PARAMCD> tokens where <PARAMCD> ",
    "is listed in `parameters`; compute_param `by_vars` must include STUDYID when a ",
    "later merge joins on STUDYID.\n",
    "4. To bring a value from another dataset into the target dataset, ALWAYS use ",
    "merge_var. `assign` may only reference variables already present in the target ",
    "dataset base (never AVAL/PARAMCD/PARAM or other BDS artifacts).\n",
    "5. compute_param and summary_record operate on BDS-shaped datasets that have ",
    "PARAMCD/AVAL records (e.g. `vs`). Run them on the BDS SOURCE dataset via ",
    "`on` inside args, then merge the result into the target dataset with merge_var. ",
    "Never run compute_param directly on a subject-level dataset like ADSL.\n",
    "5. Omit optional args entirely instead of sending empty arrays ([]).\n",
    "6. duration/compute endpoints must exist in the spec, the base dataset, or be ",
    "created by earlier steps; if an endpoint is missing, set needs_human=true.\n",
    "7. If the derivation needs human-only decisions (categorisation breakpoints, ",
    "external lookups, ambiguous text), return needs_human=true with EMPTY steps.\n",
    "8. confidence below 0.7 requires needs_human=true.\n",
    "9. Output ONLY the JSON array. No prose, no markdown fences, no extra fields.\n"
  )
}

batch_prompt <- function(batch) {
  payload <- jsonlite::toJSON(build_context(batch), auto_unbox = TRUE, pretty = TRUE)
  paste0(
    "Translate EACH spec variable below into layer IR following the system rules. ",
    "Return one JSON object per variable, same order, nothing else.\n\n",
    "## Variables (schema only, no patient data)\n\n", payload
  )
}

#' Classify spec variables via an LLM chat backend
#'
#' @description Runs the batch translate-validate-retry pipeline. With
#'   `samples > 1` the pipeline is repeated and per-variable signatures
#'   (step-layer chains) are voted on to counter LLM output variance.
#' @param vars spec data frame from [read_spec_df()].
#' @param chat ellmer chat object (or any object with a `chat(prompt)` method).
#' @param max_attempts validation-repair attempts per batch.
#' @param batch_size variables per LLM batch.
#' @param samples number of independent pipeline runs; `1` (default) keeps the
#'   classic single-run behavior; `> 1` enables consensus mode.
#' @param consensus `majority` = per-variable majority vote across samples;
#'   ties or all-failed samples mark the variable `needs_human`.
#'   `first` = skip voting and take the earliest successful sample.
#' @return List of `aa_variable_ir` objects. For `samples > 1` the list carries
#'   a `consensus` attribute: a data.frame with columns `variable`,
#'   `signature_votes` (e.g. `"impute_dtc->merge_var:2"`), `chosen`,
#'   `unanimous`.
#' @export
classify_variables_llm <- function(vars, chat, max_attempts = 2, batch_size = 4,
                                   samples = 1, consensus = c("majority", "first")) {
  vars <- read_spec_df(vars)
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("backend = 'llm' requires the 'ellmer' package.", call. = FALSE)
  }
  consensus <- match.arg(consensus)
  if (!is.numeric(samples) || length(samples) != 1L || is.na(samples) ||
    samples < 1 || samples != floor(samples)) {
    stop("`samples` must be a single positive integer.", call. = FALSE)
  }
  samples <- as.integer(samples)
  try(chat$set_system_prompt(build_system_prompt()), silent = TRUE)

  idx <- split(seq_len(nrow(vars)), ceiling(seq_len(nrow(vars)) / batch_size))
  if (samples == 1L) {
    out <- list()
    for (bi in seq_along(idx)) {
      batch <- vars[idx[[bi]], ]
      out <- c(out, classify_batch(batch, chat, max_attempts))
    }
    return(out)
  }

  runs <- lapply(seq_len(samples), function(k) classify_sample(vars, idx, chat, max_attempts))
  if (!any(vapply(runs, function(run) any(!vapply(run, is.null, logical(1))), logical(1)))) {
    stop(
      "LLM consensus failed: all ", samples, " samples failed IR validation. ",
      "Use backend = 'rules' as fallback or review manually.",
      call. = FALSE
    )
  }
  voted <- consensus_vote(vars, runs, consensus = consensus)
  lf <- getOption("admiralagent.log_file")
  if (!is.null(lf)) {
    log_run(
      "llm_consensus",
      list(
        samples = samples,
        variables = nrow(vars),
        agreement_rate = mean(voted$consensus$unanimous)
      ),
      file = lf
    )
  }
  attr(voted$ir, "consensus") <- voted$consensus
  voted$ir
}

ir_signature <- function(v) {
  if (isTRUE(v$needs_human)) {
    "needs_human"
  } else {
    paste(vapply(v$steps, function(s) s$layer, character(1)), collapse = "->")
  }
}

classify_sample <- function(vars, idx, chat, max_attempts) {
  out <- vector("list", nrow(vars))
  for (bi in seq_along(idx)) {
    rows <- idx[[bi]]
    res <- tryCatch(
      classify_batch(vars[rows, ], chat, max_attempts),
      error = function(e) NULL
    )
    if (is.null(res)) res <- vector("list", length(rows))
    out[rows] <- res
  }
  out
}

consensus_vote <- function(vars, runs, consensus) {
  n <- nrow(vars)
  ir <- vector("list", n)
  votes <- character(n)
  chosen <- character(n)
  unanimous <- logical(n)

  for (i in seq_len(n)) {
    cands <- lapply(runs, function(run) run[[i]])
    cands <- cands[!vapply(cands, is.null, logical(1))]

    if (length(cands) == 0L) {
      ir[[i]] <- new_variable_ir(
        dataset = vars$dataset[[i]],
        variable = vars$variable[[i]],
        steps = list(),
        spec_origin = vars$derivation[[i]],
        confidence = 0,
        needs_human = TRUE,
        rationale = sprintf(
          "consensus: no valid IR produced for %s across %d samples (all failed validation)",
          vars$variable[[i]], length(runs)
        )
      )
      votes[i] <- ""
      chosen[i] <- "needs_human"
      unanimous[i] <- FALSE
      next
    }

    sigs <- vapply(cands, ir_signature, character(1))
    tab <- table(sigs)
    votes[i] <- paste0(names(tab), ":", as.integer(tab), collapse = "; ")
    unanimous[i] <- length(tab) == 1L

    if (identical(consensus, "first")) {
      win <- sigs[[1]]
    } else {
      top <- tab[tab == max(tab)]
      win <- if (length(top) == 1L) names(top) else NA_character_
    }

    if (is.na(win)) {
      confs <- vapply(cands, function(v) as.numeric(v$confidence %||% 0), numeric(1))
      ir[[i]] <- new_variable_ir(
        dataset = vars$dataset[[i]],
        variable = vars$variable[[i]],
        steps = list(),
        spec_origin = vars$derivation[[i]],
        confidence = min(confs) * 0.5,
        needs_human = TRUE,
        rationale = sprintf(
          "consensus: disagreement across %d samples (signatures: %s)",
          length(sigs), votes[i]
        )
      )
      chosen[i] <- "needs_human"
    } else {
      ir[[i]] <- cands[[which(sigs == win)[[1]]]]
      chosen[i] <- win
    }
  }

  list(
    ir = ir,
    consensus = data.frame(
      variable = vars$variable,
      signature_votes = votes,
      chosen = chosen,
      unanimous = unanimous,
      stringsAsFactors = FALSE
    )
  )
}

classify_batch <- function(batch, chat, max_attempts) {
  prompt <- batch_prompt(batch)
  problems <- character()

  for (attempt in seq_len(max_attempts)) {
    ir <- try_extract(chat, prompt)
    if (is.null(ir)) {
      prompt <- paste0(
        "Your previous reply was not a parseable JSON array of variable IR records. ",
        "Use ONLY the layer vocabulary from the system prompt. Reply with JSON only.\n\n",
        prompt
      )
      next
    }
    ir <- align_batch(ir, batch)
    problems <- validate_ir(ir)
    if (length(problems) == 0L) return(ir)
    prompt <- paste0(
      "Your previous reply failed IR validation:\n- ",
      paste(problems, collapse = "\n- "),
      "\n\nFix these issues and return the full corrected JSON array only.\n\n", prompt
    )
  }
  stop(
    "LLM output failed IR validation after ", max_attempts, " attempts:\n- ",
    paste(problems, collapse = "\n- "),
    "\nUse backend = 'rules' as fallback or review manually.",
    call. = FALSE
  )
}

try_extract <- function(chat, prompt) {
  typed <- try_extract_typed(chat, prompt)
  if (!is.null(typed)) return(typed)
  raw <- tryCatch(chat$chat(prompt), error = function(e) {
    stop("ellmer chat failed: ", conditionMessage(e), call. = FALSE)
  })
  parse_ir_json(raw)
}

try_extract_typed <- function(chat, prompt) {
  ok <- tryCatch({
    ty <- suppressWarnings(ellmer::type_array(suppressWarnings(ellmer::type_object(
      dataset = ellmer::type_string(),
      variable = ellmer::type_string(),
      steps = ellmer::type_array(suppressWarnings(ellmer::type_object(
        layer = ellmer::type_string(),
        args = suppressWarnings(ellmer::type_object(.additional_properties = TRUE))
      ))),
      spec_origin = ellmer::type_string(),
      confidence = ellmer::type_number(),
      needs_human = ellmer::type_boolean(),
      rationale = ellmer::type_string()
    ))))
    TRUE
  }, error = function(e) FALSE)
  if (!ok) return(NULL)
  res <- tryCatch(chat$extract_data(prompt, type = ty), error = function(e) NULL)
  if (is.null(res)) return(NULL)
  lapply(as.list(res), function(rec) {
    steps <- lapply(as.list(rec$steps %||% list()), function(s) {
      absorb_on(s$layer, as.list(s$args %||% list()), s$on)
    })
    new_variable_ir(
      dataset = as.character(rec$dataset %||% NA_character_),
      variable = as.character(rec$variable %||% NA_character_),
      steps = steps,
      spec_origin = as.character(rec$spec_origin %||% NA_character_),
      confidence = if (is.null(rec$confidence)) 0.5 else as.numeric(rec$confidence),
      needs_human = isTRUE(rec$needs_human),
      rationale = as.character(rec$rationale %||% NA_character_)
    )
  })
}

absorb_on <- function(layer, args, on = NULL) {
  if (is.null(args$on) && !is.null(on) && is.character(on) && nzchar(on)) {
    args$on <- on
  }
  new_step(layer, args)
}

parse_ir_json <- function(raw) {
  txt <- trimws(as.character(raw))
  txt <- gsub("^```(json)?\\s*", "", txt)
  txt <- gsub("\\s*```$", "", txt)
  start <- regexpr("\\[", txt, fixed = TRUE)
  if (start > 0) txt <- substr(txt, start, nchar(txt))
  parsed <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed) || !is.list(parsed)) return(NULL)
  lapply(parsed, function(rec) {
    steps <- lapply(rec$steps %||% list(), function(s) {
      absorb_on(s$layer, s$args %||% list(), s$on)
    })
    new_variable_ir(
      dataset = as.character(rec$dataset %||% NA_character_),
      variable = as.character(rec$variable %||% NA_character_),
      steps = steps,
      spec_origin = as.character(rec$spec_origin %||% NA_character_),
      confidence = if (is.null(rec$confidence)) 0 else as.numeric(rec$confidence),
      needs_human = isTRUE(rec$needs_human),
      rationale = as.character(rec$rationale %||% NA_character_)
    )
  })
}

align_batch <- function(ir, batch) {
  if (length(ir) != nrow(batch)) return(ir)
  vars <- batch$variable
  pos <- vapply(ir, function(v) {
    if (is.null(v$variable) || is.na(v$variable)) 0L else which(vars == v$variable)
  }, integer(1))
  if (all(pos == seq_len(nrow(batch)))) return(ir)
  if (any(duplicated(pos)) || any(pos == 0L)) return(ir)
  ir[order(pos)]
}
