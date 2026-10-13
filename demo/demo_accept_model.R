# Model acceptance gate evidence capture (one-shot, needs DEEPSEEK_API_KEY).
#
# Runs accept_model() on the candidate model with prespecified thresholds and
# records the verdict as a snapshot for the website demo
# (jaimeyan.com/admiralagent.html, case 06). The verdict is whatever the gate
# decides — a REJECTED outcome is a working gate, not a failed demo.
# Run from the workspace root, like demo_llm.R.

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

# The evals corpus is located by walking up from the working directory, so
# run the gate from within the package source tree.
setwd("admiralagent")

# Prespecified acceptance criteria for the public demo. The point of the gate
# is that these numbers are chosen BEFORE the run, not fitted to the outcome.
res <- accept_model(
  chat,
  min_eval_accuracy = 0.6,
  min_full_agreement = 0.5,
  model_label = "deepseek-chat"
)
print(res)

payload <- list(
  model = res$model,
  prompt_variant = res$prompt_variant,
  generated_at = res$created_at,
  dataset = res$dataset,
  accepted = res$accepted,
  reasons = as.list(res$reasons),
  metrics = res$metrics,
  thresholds = res$thresholds,
  evals = lapply(seq_len(nrow(res$evals)), function(i) {
    list(id = res$evals$id[[i]], variable = res$evals$variable[[i]], ok = res$evals$ok[[i]])
  })
)
outdir <- file.path("demo", "gen") # cwd is the package root (setwd above)
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(payload, file.path(outdir, "model_acceptance.json"),
                     pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("\nSnapshot written:", file.path(outdir, "model_acceptance.json"), "\n")
