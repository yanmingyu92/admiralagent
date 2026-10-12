# Dual-backend consensus evidence capture (one-shot, needs DEEPSEEK_API_KEY).
#
# Runs classify_variables_dual() on the mock ADSL spec: the deterministic
# rules classifier and the LLM translate independently, and any divergence is
# escalated to human review. The result is recorded as a snapshot for the
# website demo (jaimeyan.com/admiralagent.html, case 04) — LLM output is not
# reproducible across runs, so the evidence is captured once with the model
# name and date. Run from the workspace root, like demo_llm.R.

read_env_file <- function(path) {
  kv <- list()
  for (l in readLines(path)) {
    if (grepl("^[A-Za-z_]+=", l)) {
      parts <- strsplit(l, "=", fixed = TRUE)[[1]]
      kv[[parts[1]]] <- paste(parts[-1], collapse = "=")
    }
  }
  kv
}

for (f in list.files(file.path("admiralagent", "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}

env <- read_env_file(".env")
stopifnot(!is.null(env$DEEPSEEK_API_KEY))
Sys.setenv(DEEPSEEK_API_KEY = env$DEEPSEEK_API_KEY)

library(ellmer)
chat <- if (exists("chat_deepseek", where = asNamespace("ellmer"), inherits = FALSE)) {
  ellmer::chat_deepseek(model = "deepseek-chat")
} else {
  ellmer::chat_openai(base_url = "https://api.deepseek.com", model = "deepseek-chat")
}

spec <- mock_spec_adsl()
vars <- spec_variables(spec, "ADSL")

cat("=== Dual-backend consensus (rules vs deepseek-chat) ===\n")
ir <- classify_variables_dual(spec, "ADSL", chat = chat)
dual <- attr(ir, "dual")
candidates <- attr(ir, "llm_candidates")
rules_ir <- rules_engine(vars) # deterministic; identical to the dual run's rules side

print(dual[, c("variable", "class", "rules_layers", "llm_layers")], row.names = FALSE)
cat(sprintf("\nAgreement rate: %.0f%%\n", 100 * attr(ir, "agreement_rate")))

# Plain (class-free) IR for JSON display: provenance kept, code never rendered
# from these — they are evidence of what each side concluded.
plain_ir <- function(v) {
  if (is.null(v)) return(NULL)
  list(
    dataset = v$dataset, variable = v$variable, needs_human = isTRUE(v$needs_human),
    steps = lapply(v$steps, function(s) list(layer = s$layer, args = s$args)),
    confidence = v$confidence, rationale = v$rationale
  )
}

records <- lapply(seq_len(nrow(dual)), function(i) {
  nm <- dual$variable[[i]]
  list(
    variable = nm,
    class = dual$class[[i]],
    rules_layers = dual$rules_layers[[i]],
    llm_layers = dual$llm_layers[[i]],
    confidence = ir[[i]]$confidence,
    # Agree: both sides mean the same, show the adopted rules IR only.
    # Escalated: show both sides so a reviewer can inspect the divergence.
    rules_ir = if (dual$class[[i]] == "agree") NULL else plain_ir(rules_ir[[i]]),
    llm_ir = plain_ir(candidates[[nm]])
  )
})

payload <- list(
  model = "deepseek-chat",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  dataset = "ADSL",
  agreement_rate = attr(ir, "agreement_rate"),
  variables = records
)
outdir <- file.path("admiralagent", "demo", "gen")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(payload, file.path(outdir, "dual_consensus.json"),
                     pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("\nSnapshot written:", file.path(outdir, "dual_consensus.json"), "\n")
