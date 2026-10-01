# Stage 03 - execute: run each backend's IR against the real pilot5 SDTM.
#
# Outputs (demo/automation/out/):
#   - adsl_<backend>.rds       the produced ADSL per backend
#   - exec_status_<backend>.csv  per-variable EXECUTED / ERROR / REVIEW table
#   - validation_<backend>.csv   run_validation() results
#   - execute_<backend>.jsonl    hash-chained audit log for the execution run

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("03", "execute on pilot5 SDTM")

sdtm <- load_pilot5_sdtm()
cat("SDTM sources:", paste(names(sdtm), collapse = ", "), "\n")

backends <- c("rules", "llm")
if (file.exists(file.path(OUT_DIR, "ir_llm_consensus.rds"))) backends <- c(backends, "consensus")

for (nm in backends) {
  rds <- file.path(OUT_DIR, switch(nm, rules = "ir_rules.rds", llm = "ir_llm.rds",
                                   consensus = "ir_llm_consensus.rds"))
  if (!file.exists(rds)) next
  ir <- readRDS(rds)

  sources <- c(list(base = sdtm$dm), sdtm[setdiff(names(sdtm), "dm")])
  log_file <- file.path(OUT_DIR, paste0("execute_", nm, ".jsonl"))
  if (file.exists(log_file)) file.remove(log_file)  # fresh chain per run

  t0 <- Sys.time()
  res <- tryCatch(
    execute_ir(ir, sources = sources, quiet = TRUE, log_file = log_file),
    error = function(e) e
  )
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (inherits(res, "error")) {
    cat(sprintf("%-10s execute_ir FAILED at call level: %s\n", nm, conditionMessage(res)))
    write_json(list(stage = "03_execute", backend = nm, call_error = conditionMessage(res)),
               file.path(OUT_DIR, paste0("exec_error_", nm, ".json")))
    next
  }

  target_nm <- setdiff(names(res), c("status", "env"))[1]
  produced <- res[[target_nm]]
  saveRDS(produced, file.path(OUT_DIR, paste0("adsl_", nm, ".rds")))
  utils::write.csv(res$status, file.path(OUT_DIR, paste0("exec_status_", nm, ".csv")), row.names = FALSE)

  val <- run_validation(produced, ir, quiet = TRUE)
  utils::write.csv(val, file.path(OUT_DIR, paste0("validation_", nm, ".csv")), row.names = FALSE)

  cat(sprintf("%-10s %.1fs | EXECUTED=%d ERROR=%d REVIEW=%d | validation PASS=%d FAIL=%d MANUAL=%d\n",
              nm, secs,
              sum(res$status$status == "EXECUTED"), sum(res$status$status == "ERROR"),
              sum(res$status$status == "REVIEW"),
              sum(val$status == "PASS"), sum(val$status == "FAIL"), sum(val$status == "MANUAL")))
}
