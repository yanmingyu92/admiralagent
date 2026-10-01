# Stage 03 - execute: run each backend's IR against the real pilot5 SDTM.
#
# Per dataset (showcase_datasets()), per backend. The base SDTM domain comes
# from dataset_base_domain() (ADSL<-dm, ADAE<-ae, ADLBC<-lb with the BDS
# PARAMCD/AVAL columns added by load_pilot5_sdtm()). Datasets whose
# derivations reference ADSL.* (ADAE, ADLBC) also get the ADSL produced by
# the same backend as sources$adsl. Every dataset gets the mock_metacore
# object built by 00_ingest as sources$mc so codelist_var steps can run
# (finding F-02); when mc_<ds>.rds is absent codelist_var variables simply
# error and are recorded as such.
#
# Outputs (demo/automation/out/, per dataset; ADSL keeps unsuffixed names):
#   - <ds>_<backend>.rds             the produced dataset per backend
#   - exec_status_<backend>[_<ds>].csv  per-variable EXECUTED / ERROR / REVIEW
#   - validation_<backend>[_<ds>].csv   run_validation() results
#   - execute_<backend>[_<ds>].jsonl    hash-chained audit log for the run

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("03", "execute on pilot5 SDTM")

sdtm <- load_pilot5_sdtm()
cat("SDTM sources:", paste(names(sdtm), collapse = ", "), "\n")

for (ds in showcase_datasets()) {
  base_nm <- dataset_base_domain(ds)
  if (is.null(sdtm[[base_nm]])) {
    cat(sprintf("%-6s SKIPPED: base domain %s.xpt not loaded\n", ds, base_nm))
    next
  }

  backends <- c("rules", "llm")
  if (file.exists(out_file("ir_llm_consensus", ds, ".rds"))) backends <- c(backends, "consensus")

  for (nm in backends) {
    rds <- out_file(switch(nm, rules = "ir_rules", llm = "ir_llm",
                           consensus = "ir_llm_consensus"), ds, ".rds")
    if (!file.exists(rds)) next
    ir <- readRDS(rds)

    # The base domain is supplied twice: as `base` (execute_ir's target seed)
    # and under its own name, because IRs may reference it explicitly
    # (merge_var dataset_add="ae" for ADAE, "lb" for ADLBC - finding F-10).
    # They are independent copies in the execution env, so mutating the
    # target never touches the named source.
    sources <- c(list(base = sdtm[[base_nm]]), sdtm)
    # Derivations referencing ADSL.* (e.g. ADAE.TRTA <- ADSL.TRT01A) resolve
    # against the ADSL produced by the same backend in this pipeline run.
    adsl_rds <- file.path(out_dir, paste0("adsl_", nm, ".rds"))
    if (ds != "ADSL" && file.exists(adsl_rds)) sources$adsl <- readRDS(adsl_rds)
    mc_rds <- out_file_ds("mc", ds, ".rds")
    if (file.exists(mc_rds)) sources$mc <- readRDS(mc_rds)

    log_file <- out_file(paste0("execute_", nm), ds, ".jsonl")
    if (file.exists(log_file)) file.remove(log_file)  # fresh chain per run

    t0 <- Sys.time()
    res <- tryCatch(
      execute_ir(ir, sources = sources, quiet = TRUE, log_file = log_file),
      error = function(e) e
    )
    secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

    if (inherits(res, "error")) {
      cat(sprintf("%-6s %-10s execute_ir FAILED at call level: %s\n", ds, nm, conditionMessage(res)))
      write_json(list(stage = "03_execute", dataset = ds, backend = nm, call_error = conditionMessage(res)),
                 out_file(paste0("exec_error_", nm), ds, ".json"))
      next
    }

    target_nm <- setdiff(names(res), c("status", "env"))[1]
    produced <- res[[target_nm]]
    saveRDS(produced, file.path(out_dir, paste0(tolower(ds), "_", nm, ".rds")))
    utils::write.csv(res$status, out_file(paste0("exec_status_", nm), ds, ".csv"), row.names = FALSE)

    val <- run_validation(produced, ir, quiet = TRUE)
    utils::write.csv(val, out_file(paste0("validation_", nm), ds, ".csv"), row.names = FALSE)

    cat(sprintf("%-6s %-10s %.1fs | EXECUTED=%d ERROR=%d REVIEW=%d | validation PASS=%d FAIL=%d MANUAL=%d\n",
                ds, nm, secs,
                sum(res$status$status == "EXECUTED"), sum(res$status$status == "ERROR"),
                sum(res$status$status == "REVIEW"),
                sum(val$status == "PASS"), sum(val$status == "FAIL"), sum(val$status == "MANUAL")))
  }
}
