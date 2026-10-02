# Stage 07 - freeform execute: run the CONTROL ARM code in this sandbox process.
#
# This script IS the separate R process required by the sandbox clause of
# .agents/freeform-comparison-design.md: it is launched as its own Rscript (by
# hand or by 08_compare.R), never source()d into a pipeline process. It applies
# the free-form `derive(adsl, sources)` functions from demo/automation/freeform/
# in spec order, mirroring 03_execute.R's starting point (sources$base = DM,
# sources$mc when available). Every variable call is wrapped in tryCatch +
# withCallingHandlers (warnings are evidence for the silent-error metric) and a
# best-effort setTimeLimit. On error the variable is skipped and adsl is left
# unchanged - downstream variables then face the same missing-input situation
# they would in a real free-form session, which is part of what we measure.
#
# The code under test was already vetted by 06's static gate (no installs, no
# network, no system calls, no library()). This stage adds no trust: each
# derive function runs with the same tryCatch isolation execute_ir gives IRs.
#
# Outputs (demo/automation/out/):
#   - adsl_freeform.rds          the produced ADSL (CONTROL ARM - not package output)
#   - compare_exec_status.csv    per-variable status + warning/error evidence

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("07", "freeform execute (CONTROL ARM sandbox)")

suppressPackageStartupMessages({
  library(dplyr)
  library(admiral)
})

spec <- readRDS(out_file_ds("spec", "ADSL", ".rds"))
sdtm <- load_pilot5_sdtm()
gen_csv <- file.path(out_dir, "compare_freeform_gen.csv")
if (!file.exists(gen_csv)) stop("run 06_freeform_generate.R first; ", gen_csv, " missing")
gen <- utils::read.csv(gen_csv, stringsAsFactors = FALSE)

sources <- c(list(base = sdtm$dm), sdtm)
mc_rds <- out_file_ds("mc", "ADSL", ".rds")
if (file.exists(mc_rds)) sources$mc <- readRDS(mc_rds)

freeform_dir <- file.path(auto_dir, "freeform")
adsl <- sdtm$dm

run_one <- function(file) {
  env <- new.env(parent = globalenv())
  source(file, local = env)
  warns <- character(0)
  setTimeLimit(elapsed = 60, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf, transient = TRUE), add = TRUE)
  res <- withCallingHandlers(
    tryCatch(env$derive(adsl, sources), error = function(e) e),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(result = res, warnings = warns)
}

status_rows <- list()
t0_all <- Sys.time()
for (var in spec$variable) {
  g <- gen[gen$variable == var, ]
  file <- file.path(freeform_dir, sprintf("adsl__%s__freeform.R", tolower(var)))
  if (!nrow(g) || g$status != "ok" || !file.exists(file)) {
    st <- if (!nrow(g)) "NOT_GENERATED" else toupper(g$status)
    status_rows[[length(status_rows) + 1L]] <- data.frame(
      variable = var, status = st, had_warning = FALSE,
      warning_msg = "", error_msg = "", secs = NA_real_, stringsAsFactors = FALSE
    )
    next
  }
  t0 <- Sys.time()
  r <- tryCatch(run_one(file), error = function(e) list(result = e, warnings = character(0)))
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  warn_msg <- paste(r$warnings, collapse = " | ")
  if (inherits(r$result, "error")) {
    status_rows[[length(status_rows) + 1L]] <- data.frame(
      variable = var, status = "ERROR", had_warning = length(r$warnings) > 0,
      warning_msg = warn_msg, error_msg = substr(conditionMessage(r$result), 1, 300),
      secs = round(secs, 2), stringsAsFactors = FALSE
    )
    cat(sprintf("%-10s ERROR %.1fs | %s\n", var, secs, substr(conditionMessage(r$result), 1, 80)))
    next
  }
  if (!is.data.frame(r$result)) {
    status_rows[[length(status_rows) + 1L]] <- data.frame(
      variable = var, status = "ERROR", had_warning = length(r$warnings) > 0,
      warning_msg = warn_msg, error_msg = "derive() did not return a data frame",
      secs = round(secs, 2), stringsAsFactors = FALSE
    )
    next
  }
  adsl <- r$result
  added <- var %in% names(adsl)
  status_rows[[length(status_rows) + 1L]] <- data.frame(
    variable = var, status = "EXECUTED", had_warning = length(r$warnings) > 0,
    warning_msg = warn_msg,
    error_msg = if (added) "" else "derive() returned without adding the target column",
    secs = round(secs, 2), stringsAsFactors = FALSE
  )
  cat(sprintf("%-10s EXECUTED %.1fs%s%s\n", var, secs,
              if (added) "" else " (column NOT added)",
              if (length(r$warnings)) paste0(" | warning: ", substr(warn_msg, 1, 60)) else ""))
}

st <- do.call(rbind, status_rows)
saveRDS(adsl, file.path(out_dir, "adsl_freeform.rds"))
utils::write.csv(st, file.path(out_dir, "compare_exec_status.csv"), row.names = FALSE)
cat(sprintf("\n%.1fs total | EXECUTED=%d ERROR=%d abstained/blocked/not_generated=%d | warnings on %d variables\n",
            as.numeric(difftime(Sys.time(), t0_all, units = "secs")),
            sum(st$status == "EXECUTED"), sum(st$status == "ERROR"),
            sum(!st$status %in% c("EXECUTED", "ERROR")), sum(st$had_warning)))
