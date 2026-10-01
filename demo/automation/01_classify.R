# Stage 01 - classify: rules + DeepSeek LLM backends on the same real spec.
#
# Runs every dataset in showcase_datasets() (default ADSL/ADAE/ADLBC;
# AA_DATASETS env restricts). ADSL keeps its historical artifact names; other
# datasets get a _<ds> suffix (e.g. ir_rules_adae.rds).
#
# Outputs (demo/automation/out/, per dataset):
#   - ir_rules[_<ds>].rds           full-spec rules-backend IR (always recomputed,
#                                   deterministic, zero cost)
#   - ir_llm[_<ds>].rds             full-spec DeepSeek IR (CACHED: reused when
#                                   present; set AA_FORCE_LLM=1 to re-spend)
#   - ir_llm_consensus[_<ds>].rds   3-sample majority-vote IR on a deterministic
#                                   subset (also cached)
#   - consensus[_<ds>].csv          per-variable vote table from the consensus run
#   - rules_vs_llm_layers[_<ds>].csv  layer-chain agreement between backends
#   - llm_telemetry.json            latency + token usage (tokens when ellmer
#                                   exposes them) + estimated cost with the rate
#                                   assumption written down

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("01", "classify (rules + DeepSeek)")

force_llm <- nzchar(Sys.getenv("AA_FORCE_LLM"))

# --- token accounting helper --------------------------------------------------
# This ellmer version has no chat$tokens() method; per-turn usage lives in
# Turn@tokens as c(input, output, cached). Sum across turns, defensively.
chat_tokens <- function(chat) {
  tryCatch({
    turns <- chat$get_turns()
    if (!length(turns)) return(NULL)
    tk <- lapply(turns, function(t) {
      x <- tryCatch(t@tokens, error = function(e) NULL)
      if (is.numeric(x) && length(x) >= 2) x[1:2] else c(NA_real_, NA_real_)
    })
    mat <- do.call(rbind, tk)
    list(input = sum(mat[, 1], na.rm = TRUE), output = sum(mat[, 2], na.rm = TRUE),
         turns = length(turns))
  }, error = function(e) NULL)
}

# DeepSeek deepseek-chat list prices (USD per 1M tokens, cache-miss input),
# https://api-docs.deepseek.com/quick_start/pricing - recorded so the cost
# column in the report is an explicit assumption, not a hidden one.
deepseek_rate <- list(input_per_m = 0.27, output_per_m = 1.10, as_of = "2025 price sheet")

# Estimated USD cost of one run at the recorded rate; NULL when the backend
# exposed no token counts.
est_cost <- function(tokens) {
  if (is.null(tokens)) return(NULL)
  round(tokens$input / 1e6 * deepseek_rate$input_per_m +
          tokens$output / 1e6 * deepseek_rate$output_per_m, 4)
}

# Demo-level resilience (documented, package untouched): the package's
# samples=1 path aborts the whole call when one batch fails validation after
# max_attempts. For a ~50-variable real spec that would lose dozens of good
# translations to 1 bad batch. So the full-spec run classifies recursively:
# on batch failure the spec chunk is split in half; a chunk that still fails
# at size <= batch_size yields needs_human records with the failure recorded
# in the rationale (mirroring consensus_vote()'s all-failed behaviour).
# failed_batches is reported in telemetry - nothing is hidden.
#
# Chat-level failures (e.g. "ellmer chat failed: HTTP 400" after an empty
# assistant turn poisons the request history) are not validation failures:
# retrying the same chunk on the same chat can never succeed, so the chat is
# replaced with a fresh one (system prompt is re-set by the package on the
# next classify call) and the chunk retried once before splitting. Dead chats
# are kept for token accounting; resets are capped and reported.
classify_resilient <- function(vars_spec, chat, new_chat, max_resets = 4L) {
  failed <- list()
  dead_chats <- list()
  resets <- 0L
  rec <- function(chunk) {
    res <- tryCatch(
      classify_variables_llm(chunk, chat = chat),
      error = function(e) e
    )
    chat_level <- inherits(res, "error") &&
      grepl("ellmer chat failed", conditionMessage(res), fixed = TRUE)
    if (chat_level && resets < max_resets) {
      dead_chats[[length(dead_chats) + 1L]] <<- chat
      resets <<- resets + 1L
      chat <<- new_chat()
      res <- tryCatch(
        classify_variables_llm(chunk, chat = chat),
        error = function(e) e
      )
    }
    if (!inherits(res, "error")) return(res)
    if (nrow(chunk) <= 4L) {
      failed[[length(failed) + 1L]] <<- list(
        variables = chunk$variable,
        error = conditionMessage(res)
      )
      return(lapply(seq_len(nrow(chunk)), function(i) {
        new_variable_ir(
          dataset = chunk$dataset[i], variable = chunk$variable[i],
          steps = list(), spec_origin = chunk$derivation[i], confidence = 0,
          needs_human = TRUE,
          rationale = paste0("LLM batch failed IR validation after max_attempts; ",
                             "recorded as needs_human by the demo fallback (see telemetry).")
        )
      }))
    }
    half <- ceiling(nrow(chunk) / 2)
    c(rec(chunk[seq_len(half), , drop = FALSE]),
      rec(chunk[half + seq_len(nrow(chunk) - half), , drop = FALSE]))
  }
  list(ir = rec(vars_spec), failed_batches = failed, dead_chats = dead_chats, resets = resets)
}

run_llm <- function(vars_spec, dataset, samples = 1L, consensus = "majority") {
  chat <- make_chat()
  before <- chat_tokens(chat)
  t0 <- Sys.time()
  failed_batches <- list()
  chat_resets <- 0L
  dead_chats <- list()
  if (samples == 1L) {
    res <- classify_resilient(vars_spec, chat, new_chat = make_chat)
    ir <- res$ir
    failed_batches <- res$failed_batches
    chat_resets <- res$resets
    dead_chats <- res$dead_chats
  } else {
    ir <- classify_variables(vars_spec, dataset, backend = "llm", chat = chat,
                             samples = samples, consensus = consensus)
  }
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  # Tokens: sum turns across the surviving chat and any reset (dead) chats;
  # subtract the pre-run baseline of the original chat once.
  tokens <- NULL
  tot_in <- 0
  tot_out <- 0
  seen <- FALSE
  for (ch in c(dead_chats, list(chat))) {
    tk <- chat_tokens(ch)
    if (!is.null(tk)) {
      tot_in <- tot_in + tk$input
      tot_out <- tot_out + tk$output
      seen <- TRUE
    }
  }
  if (seen) {
    base <- if (!is.null(before)) before else list(input = 0, output = 0)
    tokens <- list(input = tot_in - base$input, output = tot_out - base$output)
  }
  list(ir = ir, secs = secs, tokens = tokens, failed_batches = failed_batches,
       chat_resets = chat_resets)
}

telemetry_path <- file.path(out_dir, "llm_telemetry.json")
prev_tel <- if (file.exists(telemetry_path)) {
  tryCatch(jsonlite::read_json(telemetry_path, simplifyVector = FALSE), error = function(e) NULL)
} else {
  NULL
}

# The telemetry file is rewritten every run, so a cached run would erase the
# measurements (tokens/cost/failed batches) of the run that produced the
# cache. Carry the last measured entry forward under `last_uncached` so the
# report can still show them and findings keep their evidence (one level:
# a carried-forward entry is unwrapped, never nested twice).
prev_run_entry <- function(ds, rn) {
  e <- tryCatch(prev_tel$datasets[[ds]]$runs[[rn]], error = function(x) NULL)
  if (is.null(e)) return(NULL)
  if (isTRUE(e$cached)) e$last_uncached else e
}

telemetry <- list(
  stage = "01_classify",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  model = "deepseek-chat",
  rate_assumption = deepseek_rate,
  datasets = list()
)

for (ds in showcase_datasets()) {
  cat(sprintf("\n--- dataset %s ---\n", ds))
  spec <- readRDS(out_file_ds("spec", ds, ".rds"))
  ds_tel <- list(runs = list())

  # --- rules backend: full spec, always recomputed ----------------------------
  t0 <- Sys.time()
  ir_rules <- classify_variables(spec, ds, backend = "rules")
  rules_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  saveRDS(ir_rules, out_file("ir_rules", ds, ".rds"))
  cat(sprintf("rules backend: %d variables in %.2fs (needs_human=%d)\n",
              length(ir_rules), rules_secs,
              sum(vapply(ir_rules, function(v) isTRUE(v$needs_human), logical(1)))))

  # --- LLM backend: full spec, single sample ----------------------------------
  llm_rds <- out_file("ir_llm", ds, ".rds")
  if (file.exists(llm_rds) && !force_llm) {
    cat(sprintf("LLM full-spec IR cached (%s); set AA_FORCE_LLM=1 to re-run DeepSeek.\n",
                basename(llm_rds)))
    ds_tel$runs$full <- list(cached = TRUE)
    lu <- prev_run_entry(ds, "full")
    if (!is.null(lu)) ds_tel$runs$full$last_uncached <- lu
  } else {
    res <- run_llm(spec, ds)
    saveRDS(res$ir, llm_rds)
    ds_tel$runs$full <- list(
      cached = FALSE, variables = length(res$ir), samples = 1L,
      latency_secs = round(res$secs, 1), tokens = res$tokens,
      failed_batches = res$failed_batches,
      chat_resets = res$chat_resets,
      cost_usd = est_cost(res$tokens)
    )
    cat(sprintf("LLM full spec: %d variables in %.1fs (needs_human=%d)\n",
                length(res$ir), res$secs,
                sum(vapply(res$ir, function(v) isTRUE(v$needs_human), logical(1)))))
  }

  # --- consensus subset: deterministic selection, 3 samples, majority ---------
  # Subset rule (documented, deterministic): spec-order-first 12 variables whose
  # origin is "derived" - i.e. variables where translation actually decides
  # something. Capped at 12 to bound cost: 3 samples x 12 vars / batch_size 4.
  # Cost cap: consensus is only (re)run for ADSL; for the expansion datasets
  # the 3x sampling spend is skipped by default (the full-spec run already
  # carries the per-batch retry cost). Set AA_CONSENSUS_ALL=1 to opt in.
  consensus_rds <- out_file("ir_llm_consensus", ds, ".rds")
  consensus_csv <- out_file("consensus", ds, ".csv")
  derived_vars <- spec$variable[spec$origin == "derived"]
  subset_vars <- head(derived_vars, 12)
  cat("consensus subset (", length(subset_vars), " vars):", paste(subset_vars, collapse = ", "), "\n")

  if (ds != "ADSL" && !file.exists(consensus_rds) && !nzchar(Sys.getenv("AA_CONSENSUS_ALL"))) {
    cat("consensus skipped for ", ds, " (cost cap; set AA_CONSENSUS_ALL=1 to opt in).\n", sep = "")
    ds_tel$runs$consensus <- list(skipped = "cost cap: 3x sampling reserved for ADSL; AA_CONSENSUS_ALL=1 opts in")
  } else if (file.exists(consensus_rds) && !force_llm) {
    cat(sprintf("LLM consensus IR cached (%s); set AA_FORCE_LLM=1 to re-run.\n",
                basename(consensus_rds)))
    ds_tel$runs$consensus <- list(cached = TRUE, subset = subset_vars)
    lu <- prev_run_entry(ds, "consensus")
    if (!is.null(lu)) ds_tel$runs$consensus$last_uncached <- lu
  } else {
    sub_spec <- spec[spec$variable %in% subset_vars, , drop = FALSE]
    res <- run_llm(sub_spec, ds, samples = 3L, consensus = "majority")
    saveRDS(res$ir, consensus_rds)
    cons <- attr(res$ir, "consensus")
    if (!is.null(cons)) utils::write.csv(cons, consensus_csv, row.names = FALSE)
    ds_tel$runs$consensus <- list(
      cached = FALSE, subset = subset_vars, samples = 3L, consensus = "majority",
      latency_secs = round(res$secs, 1), tokens = res$tokens,
      unanimous_rate = if (!is.null(cons)) round(mean(cons$unanimous), 3) else NULL,
      cost_usd = est_cost(res$tokens)
    )
    cat(sprintf("consensus run: %.1fs, unanimous rate %s\n",
                res$secs, if (!is.null(cons)) sprintf("%.0f%%", 100 * mean(cons$unanimous)) else "n/a"))
  }

  ds_tel$rules_latency_secs <- round(rules_secs, 3)
  telemetry$datasets[[ds]] <- ds_tel

  # --- rules vs LLM layer-chain agreement (IR level, not data level) ----------
  ir_llm <- readRDS(llm_rds)
  cmp <- data.frame(
    variable = vapply(ir_rules, function(v) v$variable, character(1)),
    rules = ir_layers_label(ir_rules),
    llm = ir_layers_label(ir_llm),
    stringsAsFactors = FALSE
  )
  cmp$agree <- cmp$rules == cmp$llm
  utils::write.csv(cmp, out_file("rules_vs_llm_layers", ds, ".csv"), row.names = FALSE)
  cat(sprintf("rules-vs-LLM layer-chain agreement: %d/%d (%.0f%%)\n",
              sum(cmp$agree), nrow(cmp), 100 * mean(cmp$agree)))
}

write_json(telemetry, file.path(out_dir, "llm_telemetry.json"))
