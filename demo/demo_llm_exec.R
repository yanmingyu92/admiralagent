for (f in list.files(file.path("admiralagent", "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}
library(admiral)
library(dplyr)
library(rlang)
library(pharmaversesdtm)
data("dm"); data("ex"); data("vs")

sidecars <- list.files(file.path("admiralagent", "demo", "gen_llm"), pattern = "program.*[.]json$")
paths <- file.path("admiralagent", "demo", "gen_llm", sidecars)
path <- paths[order(file.info(paths)$mtime, decreasing = TRUE)][1]
cat("=== Probe: execute LLM-generated program against real pilot data ===\n")
cat("Artifact:", basename(path), "\n\n")

art <- read_artifact(path)
ir <- art$ir
cat("Backend:", art$backend, "| model:", ifelse(is.null(art$model), "n/a", art$model), "\n")
cat("Gate re-check:", if (length(validate_ir(ir)) == 0) "PASS" else paste("FAIL", validate_ir(ir)), "\n\n")

exec_env <- new.env(parent = globalenv())
exec_env$ADSL <- dm
exec_env$dm <- dm
exec_env$ex <- ex
exec_env$vs <- vs |> dplyr::mutate(AVAL = VSSTRESN, PARAMCD = VSTESTCD)

results <- data.frame(variable = character(), status = character(), note = character(),
                      stringsAsFactors = FALSE)
for (v in ir) {
  if (isTRUE(v$needs_human)) {
    results <- rbind(results, data.frame(variable = v$variable, status = "REVIEW",
                                         note = "needs human decision", stringsAsFactors = FALSE))
    next
  }
  block <- render_variable(v)
  res <- tryCatch({
    eval(parse(text = block), envir = exec_env)
    "EXECUTED"
  }, error = function(e) paste0("ERROR: ", conditionMessage(e)))
  note <- if (startsWith(res, "ERROR")) substr(res, 7, 110) else ""
  results <- rbind(results, data.frame(variable = v$variable, status = res, note = note,
                                       stringsAsFactors = FALSE))
}
print(results, row.names = FALSE)

cat("\n=== Validation gate ===\n")
val <- run_validation(exec_env$ADSL, ir, quiet = TRUE)
print(val, row.names = FALSE)
cat(sprintf("\nSummary: PASS=%d FAIL=%d MANUAL=%d\n",
            sum(val$status == "PASS"), sum(val$status == "FAIL"), sum(val$status == "MANUAL")))

cat("\n=== FINDINGS (expected: BMIBL assign-from-AVAL fails cross-dataset) ===\n")
for (i in seq_len(nrow(results))) {
  if (startsWith(results$status[i], "ERROR")) {
    cat(sprintf("[FINDING] %s: %s\n", results$variable[i], results$note[i]))
  }
}
