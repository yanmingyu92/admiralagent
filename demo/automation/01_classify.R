# Stage 01 - classify: rules + DeepSeek LLM backends on the same real spec.
#
# Outputs (demo/automation/out/):
#   - ir_rules.rds            full-spec rules-backend IR (always recomputed,
#                             deterministic, zero cost)
#   - ir_llm.rds              full-spec DeepSeek IR (CACHED: reused when
#                             present; set AA_FORCE_LLM=1 to re-spend)
#   - ir_llm_consensus.rds    3-sample majority-vote IR on a deterministic
#                             subset (also cached)
#   - consensus.csv           per-variable vote table from the consensus run
#   - llm_telemetry.json      latency + token usage (tokens when ellmer
#                             exposes them) + estimated cost with the rate
#                             assumption written down

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("01", "classify (rules + DeepSeek)")

spec <- readRDS(file.path(out_dir, "spec_adsl.rds"))
force_llm <- nzchar(Sys.getenv("AA_FORCE_LLM"))

# --- rules backend: full spec, always recomputed ------------------------------
t0 <- Sys.time()
ir_rules <- classify_variables(spec, "ADSL", backend = "rules")
rules_secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
saveRDS(ir_rules, file.path(out_dir, "ir_rules.rds"))
cat(sprintf("rules backend: %d variables in %.2fs (needs_human=%d)\n",
            length(ir_rules), rules_secs,
            sum(vapply(ir_rules, function(v) isTRUE(v$needs_human), logical(1)))))

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
# max_attempts. For a 49-variable real spec that would lose 48 good
# translations to 1 bad batch. So the full-spec run classifies recursively:
# on batch failure the spec chunk is split in half; a chunk that still fails
# at size <= batch_size yields needs_human records with the failure recorded
# in the rationale (mirroring consensus_vote()'s all-failed behaviour).
# failed_batches is reported in telemetry - nothing is hidden.
classify_resilient <- function(vars_spec, chat) {
  failed <- list()
  rec <- function(chunk) {
    res <- tryCatch(
      classify_variables_llm(chunk, chat = chat),
      error = function(e) e
    )
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
  list(ir = rec(vars_spec), failed_batches = failed)
}

run_llm <- function(vars_spec, samples = 1L, consensus = "majority") {
  chat <- make_chat()
  before <- chat_tokens(chat)
  t0 <- Sys.time()
  failed_batches <- list()
  if (samples == 1L) {
    res <- classify_resilient(vars_spec, chat)
    ir <- res$ir
    failed_batches <- res$failed_batches
  } else {
    ir <- classify_variables(vars_spec, "ADSL", backend = "llm", chat = chat,
                             samples = samples, consensus = consensus)
  }
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  after <- chat_tokens(chat)
  tokens <- NULL
  if (!is.null(after)) {
    base <- if (!is.null(before)) before else list(input = 0, output = 0)
    tokens <- list(input = after$input - base$input, output = after$output - base$output)
  }
  list(ir = ir, secs = secs, tokens = tokens, failed_batches = failed_batches)
}

# --- LLM backend: full spec, single sample ------------------------------------
telemetry <- list(
  stage = "01_classify",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  model = "deepseek-chat",
  rate_assumption = deepseek_rate,
  runs = list()
)

llm_rds <- file.path(out_dir, "ir_llm.rds")
if (file.exists(llm_rds) && !force_llm) {
  cat("LLM full-spec IR cached (out/ir_llm.rds); set AA_FORCE_LLM=1 to re-run DeepSeek.\n")
  telemetry$runs$full <- list(cached = TRUE)
} else {
  res <- run_llm(spec)
  saveRDS(res$ir, llm_rds)
  telemetry$runs$full <- list(
    cached = FALSE, variables = length(res$ir), samples = 1L,
    latency_secs = round(res$secs, 1), tokens = res$tokens,
    failed_batches = res$failed_batches,
    cost_usd = est_cost(res$tokens)
  )
  cat(sprintf("LLM full spec: %d variables in %.1fs (needs_human=%d)\n",
              length(res$ir), res$secs,
              sum(vapply(res$ir, function(v) isTRUE(v$needs_human), logical(1)))))
}

# --- consensus subset: deterministic selection, 3 samples, majority -----------
# Subset rule (documented, deterministic): spec-order-first 12 variables whose
# origin is "derived" - i.e. variables where translation actually decides
# something. Capped at 12 to bound cost: 3 samples x 12 vars / batch_size 4.
consensus_rds <- file.path(out_dir, "ir_llm_consensus.rds")
consensus_csv <- file.path(out_dir, "consensus.csv")
derived_vars <- spec$variable[spec$origin == "derived"]
subset_vars <- head(derived_vars, 12)
cat("consensus subset (", length(subset_vars), " vars):", paste(subset_vars, collapse = ", "), "\n")

if (file.exists(consensus_rds) && !force_llm) {
  cat("LLM consensus IR cached (out/ir_llm_consensus.rds); set AA_FORCE_LLM=1 to re-run.\n")
  telemetry$runs$consensus <- list(cached = TRUE, subset = subset_vars)
} else {
  sub_spec <- spec[spec$variable %in% subset_vars, , drop = FALSE]
  res <- run_llm(sub_spec, samples = 3L, consensus = "majority")
  saveRDS(res$ir, consensus_rds)
  cons <- attr(res$ir, "consensus")
  if (!is.null(cons)) utils::write.csv(cons, consensus_csv, row.names = FALSE)
  telemetry$runs$consensus <- list(
    cached = FALSE, subset = subset_vars, samples = 3L, consensus = "majority",
    latency_secs = round(res$secs, 1), tokens = res$tokens,
    unanimous_rate = if (!is.null(cons)) round(mean(cons$unanimous), 3) else NULL,
    cost_usd = est_cost(res$tokens)
  )
  cat(sprintf("consensus run: %.1fs, unanimous rate %s\n",
              res$secs, if (!is.null(cons)) sprintf("%.0f%%", 100 * mean(cons$unanimous)) else "n/a"))
}

telemetry$rules_latency_secs <- round(rules_secs, 3)
write_json(telemetry, file.path(out_dir, "llm_telemetry.json"))

# --- rules vs LLM layer-chain agreement (IR level, not data level) ------------
ir_llm <- readRDS(llm_rds)
cmp <- data.frame(
  variable = vapply(ir_rules, function(v) v$variable, character(1)),
  rules = ir_layers_label(ir_rules),
  llm = ir_layers_label(ir_llm),
  stringsAsFactors = FALSE
)
cmp$agree <- cmp$rules == cmp$llm
utils::write.csv(cmp, file.path(out_dir, "rules_vs_llm_layers.csv"), row.names = FALSE)
cat(sprintf("rules-vs-LLM layer-chain agreement: %d/%d (%.0f%%)\n",
            sum(cmp$agree), nrow(cmp), 100 * mean(cmp$agree)))
