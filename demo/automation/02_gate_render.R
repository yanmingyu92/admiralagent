# Stage 02 - gate + render: validate_ir() gate, then artifacts.
#
# Gate policy is documented, not bypassed silently: the package default is
# gate-required (DESIGN.md section 11 item 4). This showcase has no human
# approver in the loop, so programs are written with require_gate = FALSE -
# an explicit, recorded opt-out. Every program written this way carries the
# UNGATED DRAFT banner, and its sidecar records release_grade="ungated-draft"
# and gate_enforced=false. That is exactly what this stage's gate_report.json
# mirrors for the report.
#
# Outputs (demo/automation/out/):
#   - artifacts/<backend>/    program + per-variable artifacts + sidecars
#   - gate_report.json        per-backend gate outcome and validation status

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("02", "gate + render")

backends <- list(
  rules = list(rds = file.path(out_dir, "ir_rules.rds"), label = "rules", model = NULL),
  llm = list(rds = file.path(out_dir, "ir_llm.rds"), label = "llm-deepseek", model = "deepseek-chat")
)
consensus_rds <- file.path(out_dir, "ir_llm_consensus.rds")
if (file.exists(consensus_rds)) {
  backends$consensus <- list(rds = consensus_rds, label = "llm-deepseek-consensus3", model = "deepseek-chat")
}

report <- list(
  stage = "02_gate_render",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  gate_policy = paste(
    "Package default is gate-required. Programs here are written with",
    "require_gate = FALSE (explicit opt-out, no human approver in an",
    "unattended showcase). They are permanently self-labelled UNGATED DRAFT",
    "and never release-grade."
  ),
  backends = list()
)

for (nm in names(backends)) {
  b <- backends[[nm]]
  if (!file.exists(b$rds)) next
  ir <- readRDS(b$rds)
  problems <- validate_ir(ir)
  dir <- file.path(out_dir, "artifacts", nm)
  entry <- list(
    backend = b$label, variables = length(ir),
    needs_human = sum(vapply(ir, function(v) isTRUE(v$needs_human), logical(1))),
    gate = if (length(problems) == 0L) "PASS" else "FAIL",
    gate_problems = if (length(problems) > 0L) head(problems, 10) else NULL,
    require_gate = FALSE,
    artifact_hash = artifact_hash(ir)
  )
  if (length(problems) == 0L) {
    prog <- write_program_artifact(ir, dir = dir, backend_label = b$label, model = b$model,
                                   require_gate = FALSE)
    write_artifact(ir, dir = dir, backend_label = b$label, model = b$model)
    entry$program_artifact <- prog[[1]]
    sc <- jsonlite::read_json(file.path(dir, paste0(prog[[1]], ".json")), simplifyVector = TRUE)
    entry$release_grade <- sc$release_grade
    entry$gate_enforced <- isTRUE(sc$gate_enforced)
  }
  report$backends[[nm]] <- entry
  cat(sprintf("%-10s gate=%s needs_human=%d hash=%s%s\n",
              nm, entry$gate, entry$needs_human, entry$artifact_hash,
              if (!is.null(entry$release_grade)) paste0(" grade=", entry$release_grade) else ""))
}

write_json(report, file.path(out_dir, "gate_report.json"))
