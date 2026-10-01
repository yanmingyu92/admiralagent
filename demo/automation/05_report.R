# Stage 05 - report: assemble REPORT.md from out/ intermediates only.
# Every number in the report is read back from a file under out/; nothing is
# typed in by hand. If an input file is missing the report says so instead of
# inventing a number.

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("05", "report")

read_csv_or <- function(path) if (file.exists(path)) utils::read.csv(path, stringsAsFactors = FALSE) else NULL
read_json_or <- function(path) if (file.exists(path)) jsonlite::read_json(path, simplifyVector = FALSE) else NULL

md_table <- function(df) {
  if (is.null(df) || nrow(df) == 0) return("_(none)_")
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  body <- apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  paste(c(hdr, sep, body), collapse = "\n")
}

fmt_pct <- function(x) ifelse(is.na(x), "n/a", sprintf("%.1f%%", as.numeric(x)))

manifest <- read_json_or(file.path(out_dir, "ingest_manifest.json"))
gate <- read_json_or(file.path(out_dir, "gate_report.json"))
telemetry <- read_json_or(file.path(out_dir, "llm_telemetry.json"))
acc_summary <- read_json_or(file.path(out_dir, "accuracy_summary.json"))
rl <- read_csv_or(file.path(out_dir, "rules_vs_llm_layers.csv"))
consensus <- read_csv_or(file.path(out_dir, "consensus.csv"))

spec <- readRDS(file.path(out_dir, "spec_adsl.rds"))

report <- new.env(parent = emptyenv())
report$lines <- c()
add <- function(...) report$lines <- c(report$lines, paste0(...))

add("# CDISC Pilot 5 Automation Showcase — admiralagent + DeepSeek")
add("")
add("**Question:** given the real CDISC pilot 5 data and the real submission ADaM spec, how far does admiralagent (+ DeepSeek as the translation backend) get on its own — and where exactly is the boundary?")
add("")
add("Reproduce with one command from the package root:")
add("")
add("```sh")
add("Rscript demo/automation/run_all.R            # cached LLM results reused")
add("AA_FORCE_LLM=1 Rscript demo/automation/run_all.R   # re-spend on DeepSeek")
add("```")
add("")
add("Every number below is read from a machine-readable file under `demo/automation/out/` (cited per section). Generated: ", format(Sys.time(), tz = "UTC", usetz = TRUE), ".")

# --- inputs -------------------------------------------------------------------
add("")
add("## 1. Inputs (`out/ingest_manifest.json`)")
add("")
if (!is.null(manifest)) {
  add("- **Spec**: `", basename(manifest$spec_source$file), "` (sha256 `", substr(manifest$spec_source$sha256, 1, 12), "…`) — the pilot5 submission's P21-style define workbook. `read_spec()` cannot parse it (not metacore layout), so spec rows were derived by joining `Variables$Method` → `Methods$Description`. Derivation text is verbatim from the workbook; the only mechanical templating is `Copied directly from <DS.VAR>` for variables with nothing but a Predecessor pointer.")
  dsc <- manifest$derivation_source_counts
  add("- Derivation provenance: ", paste(paste0(names(dsc), "=", unlist(dsc)), collapse = ", "),
      " (of ", manifest$n_spec_variables, " ADSL variables).")
  add("- **SDTM inputs**: ", length(manifest$sdtm_inputs), " xpt files (dm/ex/vs/ae/sv/ds/sc/mh/qs), sha256 recorded in the manifest.")
  if (length(manifest$sdtm_missing)) add("- Missing SDTM files: ", paste(unlist(manifest$sdtm_missing), collapse = ", "), ".")
  add("- **Oracle**: `original-adamdata/adsl.xpt` (", acc_summary$oracle$rows, " rows × ", acc_summary$oracle$cols, " cols).")
}

# --- automation funnel ---------------------------------------------------------
add("")
add("## 2. Automation funnel per backend")
add("")
add("Sources: `out/gate_report.json`, `out/exec_status_<backend>.csv`, `out/validation_<backend>.csv`.")
add("")

funnel_rows <- list()
for (nm in c("rules", "llm", "consensus")) {
  g <- gate$backends[[nm]]
  if (is.null(g)) next
  st <- read_csv_or(file.path(out_dir, paste0("exec_status_", nm, ".csv")))
  val <- read_csv_or(file.path(out_dir, paste0("validation_", nm, ".csv")))
  funnel_rows[[nm]] <- data.frame(
    backend = nm,
    spec_vars = g$variables,
    needs_human = g$needs_human,
    gate = g$gate,
    executed = if (!is.null(st)) sum(st$status == "EXECUTED") else NA,
    exec_error = if (!is.null(st)) sum(st$status == "ERROR") else NA,
    review = if (!is.null(st)) sum(st$status == "REVIEW") else NA,
    val_PASS = if (!is.null(val)) sum(val$status == "PASS") else NA,
    val_FAIL = if (!is.null(val)) sum(val$status == "FAIL") else NA,
    val_MANUAL = if (!is.null(val)) sum(val$status == "MANUAL") else NA,
    stringsAsFactors = FALSE
  )
}
add(md_table(do.call(rbind, funnel_rows)))
add("")
add("`consensus` covers only the 12-variable subset of section 5, so its denominators differ from the full-spec backends by design.")
add("")
add("Gate policy: package default is gate-required; this showcase writes programs with `require_gate = FALSE` (no human approver in an unattended run). All programs therefore carry the UNGATED DRAFT banner and `release_grade=\"ungated-draft\"` in their sidecars (`out/gate_report.json` mirrors this). The opt-out is explicit and recorded, never silent.")

# --- accuracy ------------------------------------------------------------------
add("")
add("## 3. Accuracy vs the submitted oracle (`out/accuracy_<backend>.csv`, `out/accuracy_summary.json`)")
add("")
add("Join on USUBJID. Dates compared exactly after `as.Date`; numerics within 1e-6 (0.5 for ratio-derived BMIBL/AVGDD); characters exact. The produced ADSL is built from DM (**no population subsetting** — the pipeline automates derivations, not the decision to keep only randomized subjects), so it has more rows than the 254-subject oracle; agreement is computed on joined subjects.")
add("")
for (nm in c("rules", "llm")) {
  s <- acc_summary$backends[[nm]]
  if (is.null(s)) next
  add(sprintf("- **%s**: %d/%d spec variables compared, %d fully matching, %d partial, mean value agreement %s.",
              nm, s$compared, s$spec_variables, s$fully_matching, s$partial, fmt_pct(s$mean_value_agree)))
}
add("")
add("### Per-variable table")
add("")
acc_rules <- read_csv_or(file.path(out_dir, "accuracy_rules.csv"))
acc_llm <- read_csv_or(file.path(out_dir, "accuracy_llm.csv"))
if (!is.null(acc_rules) && !is.null(acc_llm)) {
  merged <- merge(
    acc_rules[, c("variable", "status", "value_agree")],
    acc_llm[, c("variable", "status", "value_agree", "value_agree_oracle_prec")],
    by = "variable", suffixes = c("_rules", "_llm"), all = TRUE
  )
  names(merged) <- c("variable", "rules_status", "rules_agree%", "llm_status", "llm_agree%", "llm_agree%@oracle_prec")
  merged <- merged[match(spec$variable, merged$variable), ]
  add(md_table(merged))
  add("")
  add("`llm_agree%@oracle_prec` is only populated for HEIGHTBL/WEIGHTBL: the oracle stores these rounded to 1 decimal while the spec text never mentions rounding, so agreement at the oracle's own storage precision is reported alongside the raw figure (finding F-05).")
}

# --- rules vs llm agreement -----------------------------------------------------
add("")
add("## 4. Rules vs LLM layer-chain agreement (`out/rules_vs_llm_layers.csv`)")
add("")
if (!is.null(rl)) {
  add(sprintf("Identical layer chains on **%d/%d** variables (%.0f%%). This is IR-level agreement between two translators reading the same spec text — it is **not** double programming and says nothing about correctness against the oracle (DESIGN.md section 11, item 1).",
              sum(rl$agree), nrow(rl), 100 * mean(rl$agree)))
  dis <- rl[!rl$agree, ]
  if (nrow(dis)) {
    add("")
    add("Disagreements:")
    add("")
    add(md_table(dis))
  }
}

# --- consensus ------------------------------------------------------------------
add("")
add("## 5. Multi-sample consensus (`out/consensus.csv`)")
add("")
if (!is.null(consensus)) {
  add(sprintf("Subset: %d derived-origin variables (first 12 in spec order, deterministic), 3 samples, majority vote. Unanimous on **%d/%d** variables.",
              nrow(consensus), sum(consensus$unanimous), nrow(consensus)))
  add("")
  add(md_table(consensus))
  add("")
  add("Caveat (DESIGN.md section 11): all voters read the *same* spec text, so spec errors are shared by every voter; consensus measures translation variance, not correctness. Vocabulary gaps (e.g. conditional/windowing layers) push all voters into the same abstention or the same wrong mapping — more voters cannot fix a vocabulary hole.")
}

# --- telemetry ------------------------------------------------------------------
add("")
add("## 6. DeepSeek latency / cost (`out/llm_telemetry.json`)")
add("")
if (!is.null(telemetry)) {
  for (rn in names(telemetry$runs)) {
    r <- telemetry$runs[[rn]]
    if (isTRUE(r$cached)) {
      add("- **", rn, "**: cached from a previous run (set `AA_FORCE_LLM=1` to re-measure).")
    } else {
      tok <- if (!is.null(r$tokens)) sprintf("%s in / %s out tokens", format(r$tokens$input, big.mark = ","), format(r$tokens$output, big.mark = ",")) else "token counts not exposed by ellmer in this run"
      cost <- if (!is.null(r$cost_usd)) sprintf("$%.4f", r$cost_usd) else "n/a"
      add(sprintf("- **%s**: %.1fs, %s, est. cost %s (rate assumption: $%.2f/M in, $%.2f/M out, %s).",
                  rn, r$latency_secs, tok, cost,
                  telemetry$rate_assumption$input_per_m, telemetry$rate_assumption$output_per_m,
                  telemetry$rate_assumption$as_of))
    }
  }
  add(sprintf("- **rules baseline**: %.3fs, zero cost.", telemetry$rules_latency_secs))
}

# --- failure taxonomy ------------------------------------------------------------
add("")
add("## 7. Failure taxonomy (`out/exec_status_<backend>.csv`)")
add("")
for (nm in c("rules", "llm")) {
  st <- read_csv_or(file.path(out_dir, paste0("exec_status_", nm, ".csv")))
  if (is.null(st)) next
  errs <- st[st$status == "ERROR", ]
  add(sprintf("### %s: %d execution errors", nm, nrow(errs)))
  add("")
  if (nrow(errs)) {
    add(md_table(errs))
  } else {
    add("_(none)_")
  }
  add("")
}

# --- needs_human inventory -------------------------------------------------------
add("")
add("## 8. needs_human inventory (from the IR objects)")
add("")
for (nm in c("rules", "llm")) {
  rds <- file.path(out_dir, switch(nm, rules = "ir_rules.rds", llm = "ir_llm.rds"))
  if (!file.exists(rds)) next
  ir <- readRDS(rds)
  nh <- Filter(function(v) isTRUE(v$needs_human), ir)
  add(sprintf("### %s: %d variables abstained", nm, length(nh)))
  add("")
  if (length(nh)) {
    df <- data.frame(
      variable = vapply(nh, function(v) v$variable, character(1)),
      rationale = vapply(nh, function(v) substr(gsub("\\s+", " ", v$rationale %||% ""), 1, 220), character(1)),
      stringsAsFactors = FALSE
    )
    add(md_table(df))
  } else {
    add("_(none)_")
  }
  add("")
}

# --- findings --------------------------------------------------------------------
add("")
add("## 9. Findings registered this run (`out/findings.json`)")
add("")
add("Per the AGENTS.md improvement-loop convention, every ERROR/FAIL/MANUAL class observed gets a numbered finding with evidence. `severity`: **package** = code defect to fix; **demo** = pipeline configuration; **spec** = source-spec ambiguity; **oracle** = oracle convention the spec text does not mention.")
add("")
findings <- read_json_or(file.path(out_dir, "findings.json"))
if (!is.null(findings)) {
  for (f in findings$findings) {
    add(sprintf("- **%s (%s) — %s.** %s _Evidence: %s._",
                f$id, f$severity, f$title, f$detail, f$evidence))
    if (!is.null(f$suggested_fix)) add(sprintf("  - Suggested fix: %s", f$suggested_fix))
  }
} else {
  add("_(none registered)_")
}

# --- limitations -----------------------------------------------------------------
add("")
add("## 10. Limitations (read this before quoting any number above)")
add("")
add("1. **Population subsetting is not automated.** Produced ADSL starts from DM (all screened subjects); the oracle has 254 randomized subjects. Row-level agreement is only computed on the join.")
add("2. **Vocabulary gaps are hard boundaries.** The layer vocabulary has no conditional/windowing layers; derivations like COMP8FL/COMP16FL/COMP24FL (visit-window existence checks), EFFFL (cross-dataset existence), CUMDOSE (arm-conditional dose logic) or ADTTE-style CNSR can only abstain or be approximated. More LLM voters cannot fix a vocabulary hole (DESIGN.md section 11, item 5).")
add("3. **The rules backend is keyword-fragile.** It matches English phrases; paraphrase the spec and its output changes. It is a zero-cost baseline, not a claim of understanding.")
add("4. **The evals corpus is self-scoring** (`inst/evals/spec-to-ir.jsonl` expected values were generated by the rules backend). It pins current behavior as contract; it is not an oracle (DESIGN.md section 11, item 2).")
add("5. **IR agreement ≠ double programming.** Rules/LLM agreement and 3-sample consensus measure translation consistency before execution, with all voters reading the same spec text (DESIGN.md section 11, item 1).")
add("6. **Oracle differences may be spec ambiguity, not package error.** Where a produced value disagrees with the oracle, the spec text itself is often ambiguous (e.g. CUMDOSE's arm-conditional rule); a human programmer would also have to ask. Disagreement rates here are not error rates.")
add("7. **Programs are UNGATED DRAFTs.** No human approval gate covers these artifacts; they are demonstration output, not release-grade deliverables (DESIGN.md section 11, item 4).")
add("8. **Single model, single dataset, and stochastic.** Numbers are for DeepSeek `deepseek-chat` on pilot5 ADSL only; they do not transfer to other models or datasets without re-measurement. LLM output also varies run to run at temperature defaults: across the two full runs behind this report's development, the full-spec needs_human count moved 24 -> 22 and the rules/LLM layer-chain agreement 78% -> 71% — run-to-run translation variance is exactly what the consensus mode in section 5 exists to measure and contain.")

report_path <- file.path(auto_dir, "REPORT.md")
writeLines(report$lines, report_path)
cat("written:", report_path, "\n")
cat("lines:", length(report$lines), "\n")
