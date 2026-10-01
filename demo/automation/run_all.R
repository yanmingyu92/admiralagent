# run_all.R — one-command end-to-end CDISC pilot automation showcase.
#
#   Rscript demo/automation/run_all.R
#   AA_FORCE_LLM=1 Rscript demo/automation/run_all.R   # force DeepSeek re-run
#
# Stages are idempotent: deterministic artifacts overwrite in place
# (same IR -> same <dataset>__<variable>__<hash8>.R file names), and the LLM
# stage reuses cached IRs unless AA_FORCE_LLM=1. Patient data never leaves
# the machine: the LLM only sees schema-level spec text (build_context()).

stages <- c("00_ingest.R", "01_classify.R", "02_gate_render.R",
            "03_execute.R", "04_oracle_compare.R", "05_report.R")

# Resolve this script's directory so run_all works from any cwd.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
here <- if (length(file_arg)) {
  dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
} else {
  normalizePath(file.path(getwd(), "demo", "automation"), winslash = "/")
}

t_total <- Sys.time()
for (s in stages) {
  t0 <- Sys.time()
  source(file.path(here, s), local = new.env(parent = globalenv()))
  cat(sprintf("[run_all] %s done in %.1fs\n", s,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
cat(sprintf("\n[run_all] pipeline complete in %.1fs. Report: %s\n",
            as.numeric(difftime(Sys.time(), t_total, units = "secs")),
            file.path(here, "REPORT.md")))
