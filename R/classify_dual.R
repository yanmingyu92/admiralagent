#' Classify spec variables with two independent backends
#'
#' @description Runs the deterministic rules classifier and the LLM pipeline
#'   independently on the same spec, then compares the two translations per
#'   variable at `ir_fingerprint(level = "full")` - complete canonical
#'   semantics, with registry defaults filled and intermediate names
#'   alpha-renamed, so a rule's `EXST_TRTSDTM` temp and an LLM's `EXSTDTM`
#'   compare equal when the derivation means the same thing.
#'
#'   Agreement adopts the rules IR (deterministic precedence; the semantics
#'   are identical anyway). Any divergence - different canonical semantics, or
#'   exactly one side abstaining - escalates the variable to `needs_human`
#'   with a rationale naming both layer chains. No side is ever silently
#'   preferred: a dual run never derives a variable that a rules-only run
#'   would have refused, and never accepts an LLM answer the rules disagreed
#'   with. Agreement is corroboration, not proof of correctness.
#' @title Dual-backend consensus classification
#' @param spec Spec data frame compatible with [read_spec_df()].
#' @param dataset Dataset name to classify (e.g. `"ADSL"`).
#' @param chat ellmer chat object (or any object with a `chat(prompt)`
#'   method) for the LLM side.
#' @param samples Number of independent LLM pipeline runs, passed to
#'   [classify_variables_llm()]; `> 1` gives the LLM side its own internal
#'   majority vote before the cross-backend comparison.
#' @param prompt_variant System prompt variant for the LLM side; see
#'   [classify_variables_llm()].
#' @return List of `aa_variable_ir` objects, one per spec variable, with two
#'   attributes: `dual`, a data.frame with columns `variable`, `class`
#'   (`agree`, `disagree`, `rules_abstain`, `llm_abstain`), `rules_fp`,
#'   `llm_fp` (full fingerprints), `rules_layers`, `llm_layers` (layer
#'   chains), and `llm_suggestion` (whether the LLM side produced a candidate
#'   the reviewer can inspect); `agreement_rate`, the fraction of variables
#'   where both backends produced the same canonical semantics; and
#'   `llm_candidates`, a named list holding the LLM-side IR for every
#'   escalated variable that has one (the reviewer's starting point; never
#'   rendered or executed without a human decision).
#' @examples
#' \dontrun{
#' # Not executable without an LLM provider API key (ellmer chat object):
#' chat <- ellmer::chat_deepseek(model = "deepseek-chat")
#' ir <- classify_variables_dual(mock_spec_adsl(), "ADSL", chat)
#' dual_disagreements(ir) # review queue: every variable the backends split on
#' }
#' @export
classify_variables_dual <- function(spec, dataset, chat, samples = 1,
                                    prompt_variant = c("full", "neutral", "minimal")) {
  if (is.null(chat)) {
    stop("classify_variables_dual() requires an ellmer chat object for the LLM side", call. = FALSE)
  }
  prompt_variant <- match.arg(prompt_variant)
  vars <- spec_variables(spec, dataset)
  rules_ir <- rules_engine(vars)
  llm_ir <- classify_variables_llm(vars, chat = chat, samples = samples,
                                   prompt_variant = prompt_variant)

  n <- nrow(vars)
  out <- vector("list", n)
  llm_candidates <- list()
  dual <- data.frame(
    variable = as.character(vars$variable),
    class = NA_character_,
    rules_fp = NA_character_,
    llm_fp = NA_character_,
    rules_layers = NA_character_,
    llm_layers = NA_character_,
    llm_suggestion = FALSE,
    stringsAsFactors = FALSE
  )

  for (i in seq_len(n)) {
    r <- rules_ir[[i]]
    l <- llm_ir[[i]]
    fp_r <- ir_fingerprint(r, "full")
    fp_l <- ir_fingerprint(l, "full")
    chain_r <- ir_signature(r)
    chain_l <- ir_signature(l)
    dual$rules_fp[i] <- fp_r
    dual$llm_fp[i] <- fp_l
    dual$rules_layers[i] <- chain_r
    dual$llm_layers[i] <- chain_l
    dual$llm_suggestion[i] <- !isTRUE(l$needs_human) && length(l$steps) > 0

    if (identical(fp_r, fp_l)) {
      # Same canonical semantics (including both-sides-abstain): adopt the
      # deterministic rules IR.
      out[[i]] <- r
      dual$class[i] <- "agree"
      next
    }

    dual$class[i] <- if (isTRUE(r$needs_human) && !isTRUE(l$needs_human)) {
      "rules_abstain"
    } else if (!isTRUE(r$needs_human) && isTRUE(l$needs_human)) {
      "llm_abstain"
    } else {
      "disagree"
    }
    conf <- min(as.numeric(r$confidence %||% 0), as.numeric(l$confidence %||% 0))
    out[[i]] <- new_variable_ir(
      dataset = vars$dataset[[i]],
      variable = vars$variable[[i]],
      steps = list(),
      spec_origin = vars$derivation[[i]],
      confidence = conf * 0.5,
      needs_human = TRUE,
      rationale = sprintf(
        "dual: backends disagree (rules: %s; llm: %s); escalated to human review",
        chain_r, chain_l
      )
    )
    if (dual$llm_suggestion[i]) llm_candidates[[vars$variable[[i]]]] <- l
  }

  agreement_rate <- mean(dual$class == "agree")
  attr(out, "dual") <- dual
  attr(out, "agreement_rate") <- agreement_rate
  attr(out, "llm_candidates") <- llm_candidates

  # A cross-backend consensus decision is a record-affecting act: log it
  # unconditionally (21 CFR Part 11 s11.10(e)), digest-only like the
  # `llm_consensus` precedent - fingerprints and counts, never spec text.
  if (!is.null(aa_log_file())) {
    log_run(
      "dual_consensus",
      list(
        dataset = dataset,
        variables = n,
        samples = samples,
        prompt_variant = prompt_variant,
        agreement_rate = agreement_rate,
        classes = as.list(table(dual$class)),
        fingerprints = stats::setNames(
          paste(substr(dual$rules_fp, 1, 8), substr(dual$llm_fp, 1, 8), sep = "/"),
          dual$variable
        ),
        origin = consensus_origin_digest(vars)
      )
    )
  }
  out
}

#' Extract the dual-backend review queue
#'
#' @description Returns the rows of the `dual` attribute where the two
#'   backends did not agree - the variables a human must decide on. Each row
#'   carries both layer chains and whether the LLM side produced a candidate
#'   IR the reviewer can inspect as a starting point.
#' @title Dual-backend disagreements
#' @param ir IR list returned by [classify_variables_dual()].
#' @return A data.frame with columns `variable`, `class`, `rules_layers`,
#'   `llm_layers`, `llm_suggestion`; zero rows when every variable agreed.
#' @examples
#' \dontrun{
#' # Needs an ellmer chat object (LLM provider API key); see
#' # classify_variables_dual():
#' ir <- classify_variables_dual(mock_spec_adsl(), "ADSL", chat)
#' dual_disagreements(ir)
#' }
#' @export
dual_disagreements <- function(ir) {
  dual <- attr(ir, "dual")
  if (is.null(dual)) {
    stop("no `dual` attribute: pass the result of classify_variables_dual()", call. = FALSE)
  }
  queue <- dual[dual$class != "agree",
                c("variable", "class", "rules_layers", "llm_layers", "llm_suggestion"),
                drop = FALSE]
  rownames(queue) <- NULL
  queue
}
