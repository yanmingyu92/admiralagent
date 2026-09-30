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

layers_of <- function(ir) {
  vapply(ir, function(v) {
    if (v$needs_human) "needs_human" else paste(vapply(v$steps, function(s) s$layer, character(1)), collapse = " -> ")
  }, character(1))
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

cat("=== LLM classification (DeepSeek) vs rules baseline ===\n")
ir_llm <- classify_variables(spec, "ADSL", backend = "llm", chat = chat)
gate <- validate_ir(ir_llm)
cat("IR gate:", if (length(gate) == 0) "PASS" else paste("FAIL:", head(gate, 3)), "\n\n")

if (length(gate) == 0) {
  ir_rules <- classify_variables(spec, "ADSL", backend = "rules")
  tab <- data.frame(
    variable = vapply(ir_llm, function(v) v$variable, character(1)),
    rules = layers_of(ir_rules),
    llm = layers_of(ir_llm),
    stringsAsFactors = FALSE
  )
  tab$agree <- tab$rules == tab$llm
  print(tab, row.names = FALSE)
  cat(sprintf("\nAgreement: %d/%d\n", sum(tab$agree), nrow(tab)))

  files <- write_program_artifact(ir_llm, dir = file.path("admiralagent", "demo", "gen_llm"),
                                  backend_label = "llm-deepseek", model = "deepseek-chat")
  cat("LLM artifacts written:", paste(files, collapse = ", "), "\n")

  cat("\n=== Dependency report (LLM IR vs known ADSL base columns) ===\n")
  rep <- ir_dependency_report(ir_llm, known_columns = c("STUDYID", "USUBJID", "SUBJID", "ARM", "RACE"))
  if (nrow(rep) > 0) print(rep, row.names = FALSE) else cat("no gaps\n")

  cat("\n=== Sample LLM rationale (TRTSDTM) ===\n")
  v <- ir_llm[[which(vapply(ir_llm, function(x) x$variable, character(1)) == "TRTSDTM")]]
  cat("confidence:", v$confidence, "| rationale:", v$rationale, "\n")
}
