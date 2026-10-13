#' Accept or reject an LLM backend for spec translation
#'
#' @description Model+harness acceptance gate. A harness does not transfer
#'   across models, so every candidate model must be accepted before it is
#'   allowed to translate specs: the candidate runs the spec-to-IR regression
#'   corpus ([run_evals()] machinery) and is cross-compared against the deterministic
#'   rules baseline at full canonical semantics ([run_agreement()]). Both
#'   thresholds are required arguments with no defaults — acceptance criteria
#'   must be prespecified by the deploying organization, not inherited from
#'   the tool.
#'
#'   The decision is fail-closed: any pipeline error rejects the candidate.
#'   Acceptance certifies translation consistency against a self-scoring
#'   corpus — not correctness, not fitness for a particular study. Accepted
#'   output still passes through `validate_ir()`, the dual-backend consensus,
#'   and human review like any other IR.
#' @title Model acceptance gate
#' @param chat ellmer chat object (or any object with a `chat(prompt)`
#'   method) for the candidate model.
#' @param dataset Dataset tag of the corpus cases to run (default `"ADSL"`).
#' @param min_eval_accuracy Required minimum fraction of corpus cases whose
#'   produced IR matches the expected fingerprint (args-aware).
#' @param min_full_agreement Required minimum agreement rate between the
#'   candidate and the rules baseline at `ir_fingerprint(level = "full")`.
#' @param prompt_variant System prompt variant used for the candidate run.
#' @param model_label Optional label for reports and the audit record; when
#'   `NULL`, the chat object's `get_model()` is tried, else `"unknown"`.
#' @return An `aa_model_acceptance` list: `accepted` (logical), `reasons`
#'   (failed criteria, empty when accepted), `metrics` (`eval_accuracy`,
#'   `full_agreement`, `layer_chain_agreement`, `overstatement`),
#'   `thresholds`, plus the underlying `evals` data.frame and `agreement`
#'   object. Printed via `print.aa_model_acceptance()`.
#' @examples
#' \dontrun{
#' chat <- ellmer::chat_deepseek(model = "deepseek-chat")
#' accept_model(chat, min_eval_accuracy = 0.8, min_full_agreement = 0.5)
#' }
#' @export
accept_model <- function(chat, dataset = "ADSL",
                         min_eval_accuracy, min_full_agreement,
                         prompt_variant = c("full", "neutral", "minimal"),
                         model_label = NULL) {
  if (missing(min_eval_accuracy) || missing(min_full_agreement)) {
    stop("acceptance thresholds must be prespecified: supply both `min_eval_accuracy` and `min_full_agreement`", call. = FALSE)
  }
  for (nm in c("min_eval_accuracy", "min_full_agreement")) {
    value <- get(nm)
    if (!real_numeric(value) || length(value) != 1L || value < 0 || value > 1) {
      stop(nm, " must be a single number in [0, 1]", call. = FALSE)
    }
  }
  prompt_variant <- match.arg(prompt_variant)
  if (is.null(model_label)) {
    model_label <- tryCatch(
      {
        m <- chat$get_model()
        if (is.character(m) && length(m) == 1L && nzchar(m)) m else "unknown"
      },
      error = function(e) "unknown"
    )
  }

  cases <- load_evals()
  cases <- cases[vapply(cases, function(c) identical(as.character(c$dataset), dataset), logical(1))]
  if (length(cases) == 0) {
    stop("no eval cases found for dataset '", dataset, "'", call. = FALSE)
  }

  result <- tryCatch(
    {
      irs <- evals_classify(cases, backend = "llm", chat = chat, prompt_variant = prompt_variant)
      evals <- data.frame(
        id = vapply(cases, function(c) as.character(c$id), character(1)),
        variable = vapply(cases, function(c) as.character(c$spec_row$variable), character(1)),
        ok = vapply(seq_along(cases), function(i) isTRUE(evals_case_ok(cases[[i]], irs[[i]])), logical(1)),
        stringsAsFactors = FALSE
      )
      agreement <- run_agreement(
        voters = list(rules = "rules", candidate = list(backend = "llm", chat = chat, prompt_variant = prompt_variant)),
        dataset = dataset
      )
      list(evals = evals, agreement = agreement, error = NULL)
    },
    error = function(e) list(evals = NULL, agreement = NULL, error = conditionMessage(e))
  )

  metrics <- list(
    eval_accuracy = if (is.null(result$evals)) NA_real_ else mean(result$evals$ok),
    full_agreement = if (is.null(result$agreement)) NA_real_ else unname(result$agreement$rates[["full"]]),
    layer_chain_agreement = if (is.null(result$agreement)) NA_real_ else unname(result$agreement$rates[["layer_chain"]]),
    overstatement = if (is.null(result$agreement)) NA_real_ else agreement_overstatement(result$agreement)$overstatement
  )
  thresholds <- list(min_eval_accuracy = min_eval_accuracy, min_full_agreement = min_full_agreement)

  reasons <- character()
  if (!is.null(result$error)) {
    reasons <- c(reasons, paste0("pipeline error: ", result$error))
  } else {
    if (metrics$eval_accuracy < min_eval_accuracy) {
      reasons <- c(reasons, sprintf("eval accuracy %.3f below prespecified minimum %.3f", metrics$eval_accuracy, min_eval_accuracy))
    }
    if (metrics$full_agreement < min_full_agreement) {
      reasons <- c(reasons, sprintf("full-semantics agreement with rules %.3f below prespecified minimum %.3f", metrics$full_agreement, min_full_agreement))
    }
  }
  accepted <- length(reasons) == 0L

  # The acceptance decision is a record-affecting act: digest-only audit
  # event, corpus pinned by id digest, no spec text.
  if (!is.null(aa_log_file())) {
    log_run("model_acceptance", list(
      dataset = dataset,
      model = model_label,
      prompt_variant = prompt_variant,
      metrics = metrics,
      thresholds = thresholds,
      accepted = accepted,
      corpus = paste0("corpus:", digest::digest(
        paste(vapply(cases, function(c) as.character(c$id), character(1)), collapse = "\n"),
        algo = "xxhash64", serialize = FALSE
      ))
    ))
  }

  structure(
    list(
      dataset = dataset, model = model_label, prompt_variant = prompt_variant,
      accepted = accepted, reasons = reasons, metrics = metrics, thresholds = thresholds,
      evals = result$evals, agreement = result$agreement,
      created_at = format(Sys.time(), tz = "UTC", usetz = TRUE)
    ),
    class = c("aa_model_acceptance", "list")
  )
}

#' Print a model acceptance report
#'
#' @param x An `aa_model_acceptance` object from [accept_model()].
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
print.aa_model_acceptance <- function(x, ...) {
  cat("admiralagent model acceptance\n")
  cat("  model:   ", x$model, " (prompt: ", x$prompt_variant, ")\n", sep = "")
  cat("  dataset: ", x$dataset, "\n", sep = "")
  cat("  verdict: ", if (x$accepted) "ACCEPTED" else "REJECTED", "\n", sep = "")
  fmt <- function(value, threshold) {
    if (is.na(value)) sprintf("%7s (min %.3f)", "n/a", threshold) else sprintf("%7.3f (min %.3f)", value, threshold)
  }
  cat("  eval accuracy:        ", fmt(x$metrics$eval_accuracy, x$thresholds$min_eval_accuracy), "\n", sep = "")
  cat("  full agreement/rules: ", fmt(x$metrics$full_agreement, x$thresholds$min_full_agreement), "\n", sep = "")
  cat("  layer_chain (info):   ", sprintf("%.3f", x$metrics$layer_chain_agreement),
      " · overstatement ", sprintf("%.3f", x$metrics$overstatement), "\n", sep = "")
  for (r in x$reasons) cat("  - ", r, "\n", sep = "")
  cat("  note: acceptance measures translation consistency against a regression\n")
  cat("        corpus - not correctness, not fitness for any particular study.\n")
  invisible(x)
}
