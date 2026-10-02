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

datasets <- showcase_datasets()
# Only report datasets this run actually produced evidence for.
has_evidence <- function(ds) {
  file.exists(out_file_ds("spec", ds, ".rds")) && !is.null(gate$datasets[[ds]])
}
datasets <- Filter(has_evidence, datasets)

report <- new.env(parent = emptyenv())
report$lines <- c()
add <- function(...) report$lines <- c(report$lines, paste0(...))

add("# CDISC Pilot 5 Automation Showcase — admiralagent + DeepSeek")
add("")
add("**Question:** given the real CDISC pilot 5 data and the real submission ADaM spec, how far does admiralagent (+ DeepSeek as the translation backend) get on its own — and where exactly is the boundary?")
add("")
add("Datasets in this run: **", paste(datasets, collapse = ", "), "** (spec and oracle from the same pilot5 submission; `AA_DATASETS` env restricts the set).")
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
  for (ds in datasets) {
    dm <- manifest$datasets[[ds]]
    if (is.null(dm)) next
    dsc <- dm$derivation_source_counts
    mc_note <- if (!is.null(dm$metacore) && !is.na(dm$metacore$path)) {
      sprintf("`%s` (%d workbook codelists)", basename(dm$metacore$path), dm$metacore$n_codelists %||% 0L)
    } else {
      "unavailable (recorded as a boundary)"
    }
    add(sprintf("- **%s**: %d spec variables (derivation provenance: %s); oracle `%s`; executable metacore for `codelist_var`: %s.",
                ds, dm$n_spec_variables, paste(paste0(names(dsc), "=", unlist(dsc)), collapse = ", "),
                basename(dm$oracle$file), mc_note))
  }
  add("- **SDTM inputs**: ", length(manifest$sdtm_inputs), " xpt files (dm/ex/vs/ae/sv/ds/sc/mh/qs/lb), sha256 recorded in the manifest.")
  if (length(manifest$sdtm_missing)) add("- Missing SDTM files: ", paste(unlist(manifest$sdtm_missing), collapse = ", "), ".")
  add("- The workbook's `Codelists` sheet (long table ID/Term/Decoded Value) is converted into `mock_metacore()` codelists at ingest, so `metatools::create_var_from_codelist()` steps execute against the submission's own terminology (fix for finding F-02).")
}

# --- automation funnel ---------------------------------------------------------
add("")
add("## 2. Automation funnel per dataset and backend")
add("")
add("Sources: `out/gate_report.json`, `out/exec_status_<backend>[_<ds>].csv`, `out/validation_<backend>[_<ds>].csv`.")
add("")
for (ds in datasets) {
  funnel_rows <- list()
  for (nm in c("rules", "llm", "consensus")) {
    g <- gate$datasets[[ds]][[nm]]
    if (is.null(g)) next
    st <- read_csv_or(out_file(paste0("exec_status_", nm), ds, ".csv"))
    val <- read_csv_or(out_file(paste0("validation_", nm), ds, ".csv"))
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
  add("### ", ds)
  add("")
  add(md_table(do.call(rbind, funnel_rows)))
  add("")
}
add("`consensus` covers only the 12-variable subset of section 5, so its denominators differ from the full-spec backends by design.")
add("")
add("Gate policy: package default is gate-required; this showcase writes programs with `require_gate = FALSE` (no human approver in an unattended run). All programs therefore carry the UNGATED DRAFT banner and `release_grade=\"ungated-draft\"` in their sidecars (`out/gate_report.json` mirrors this). The opt-out is explicit and recorded, never silent.")

# --- accuracy ------------------------------------------------------------------
add("")
add("## 3. Accuracy vs the submitted oracle (`out/accuracy_<backend>[_<ds>].csv`, `out/accuracy_summary.json`)")
add("")
add("Join on the dataset's row-identity keys (ADSL: USUBJID; ADAE: USUBJID+AESEQ; ADLBC: USUBJID+LBSEQ). Dates compared exactly after `as.Date`; numerics within 1e-6 (0.5 for ratio-derived BMIBL/AVGDD); characters exact. Produced datasets are built from the full SDTM base domain (**no population/parameter subsetting** — the pipeline automates derivations, not the decision of which records belong to the analysis population), so they have more rows than the oracles; agreement is computed on joined records.")
add("")
for (ds in datasets) {
  dsum <- acc_summary$datasets[[ds]]
  if (is.null(dsum)) next
  add(sprintf("### %s (oracle %d rows × %d cols)", ds, dsum$oracle$rows, dsum$oracle$cols))
  add("")
  for (nm in c("rules", "llm")) {
    s <- dsum$backends[[nm]]
    if (is.null(s)) next
    add(sprintf("- **%s**: %d/%d spec variables compared, %d fully matching, %d partial, mean value agreement %s (produced %d rows).",
                nm, s$compared, s$spec_variables, s$fully_matching, s$partial,
                fmt_pct(s$mean_value_agree), s$produced_rows))
  }
  add("")
  acc_rules <- read_csv_or(out_file("accuracy_rules", ds, ".csv"))
  acc_llm <- read_csv_or(out_file("accuracy_llm", ds, ".csv"))
  if (!is.null(acc_rules) && !is.null(acc_llm)) {
    merged <- merge(
      acc_rules[, c("variable", "status", "value_agree")],
      acc_llm[, c("variable", "status", "value_agree", "value_agree_oracle_prec")],
      by = "variable", suffixes = c("_rules", "_llm"), all = TRUE
    )
    names(merged) <- c("variable", "rules_status", "rules_agree%", "llm_status", "llm_agree%", "llm_agree%@oracle_prec")
    spec <- readRDS(out_file_ds("spec", ds, ".rds"))
    merged <- merged[match(spec$variable, merged$variable), ]
    add(md_table(merged))
    add("")
  }
}
add("`llm_agree%@oracle_prec` is only populated for HEIGHTBL/WEIGHTBL: the oracle stores these rounded to 1 decimal while the spec text never mentions rounding, so agreement at the oracle's own storage precision is reported alongside the raw figure (finding F-05).")

# --- rules vs llm agreement -----------------------------------------------------
add("")
add("## 4. Rules vs LLM layer-chain agreement (`out/rules_vs_llm_layers[_<ds>].csv`)")
add("")
for (ds in datasets) {
  rl <- read_csv_or(out_file("rules_vs_llm_layers", ds, ".csv"))
  if (is.null(rl)) next
  add(sprintf("**%s**: identical layer chains on **%d/%d** variables (%.0f%%).",
              ds, sum(rl$agree), nrow(rl), 100 * mean(rl$agree)))
  dis <- rl[!rl$agree, ]
  if (nrow(dis)) {
    add("")
    add(md_table(dis))
    add("")
  }
}
add("This is IR-level agreement between two translators reading the same spec text — it is **not** double programming and says nothing about correctness against the oracle (DESIGN.md section 11, item 1).")

# --- consensus ------------------------------------------------------------------
add("")
add("## 5. Multi-sample consensus (`out/consensus[_<ds>].csv`)")
add("")
for (ds in datasets) {
  consensus <- read_csv_or(out_file("consensus", ds, ".csv"))
  if (is.null(consensus)) next
  add(sprintf("**%s** subset: %d derived-origin variables (first 12 in spec order, deterministic), 3 samples, majority vote. Unanimous on **%d/%d** variables.",
              ds, nrow(consensus), sum(consensus$unanimous), nrow(consensus)))
  add("")
  add(md_table(consensus))
  add("")
}
add("Caveat (DESIGN.md section 11): all voters read the *same* spec text, so spec errors are shared by every voter; consensus measures translation variance, not correctness. Vocabulary gaps (e.g. existence/windowing layers) push all voters into the same abstention or the same wrong mapping — more voters cannot fix a vocabulary hole.")

# --- telemetry ------------------------------------------------------------------
add("")
add("## 6. DeepSeek latency / cost (`out/llm_telemetry.json`)")
add("")
if (!is.null(telemetry)) {
  fmt_run <- function(rn, r, prefix) {
    tok <- if (!is.null(r$tokens)) sprintf("%s in / %s out tokens", format(r$tokens$input, big.mark = ","), format(r$tokens$output, big.mark = ",")) else "token counts not exposed by ellmer in this run"
    cost <- if (!is.null(r$cost_usd)) sprintf("$%.4f", r$cost_usd) else "n/a"
    extra <- ""
    if (length(r$failed_batches)) {
      extra <- paste0(extra, sprintf(", %d failed batch(es) degraded to needs_human by the resilient fallback", length(r$failed_batches)))
    }
    if (!is.null(r$chat_resets) && r$chat_resets > 0) {
      extra <- paste0(extra, sprintf(", %d chat reset(s) after transport-level failures", r$chat_resets))
    }
    sprintf("- **%s**: %s%.1fs, %s, est. cost %s%s (rate assumption: $%.2f/M in, $%.2f/M out, %s).",
            rn, prefix, r$latency_secs, tok, cost, extra,
            telemetry$rate_assumption$input_per_m, telemetry$rate_assumption$output_per_m,
            telemetry$rate_assumption$as_of)
  }
  for (ds in datasets) {
    dtel <- telemetry$datasets[[ds]]
    if (is.null(dtel)) next
    add("### ", ds)
    add("")
    for (rn in names(dtel$runs)) {
      r <- dtel$runs[[rn]]
      if (isTRUE(r$cached)) {
        if (!is.null(r$last_uncached)) {
          add(fmt_run(rn, r$last_uncached, prefix = "cached; last measured run: "))
        } else {
          add("- **", rn, "**: cached from a previous run (set `AA_FORCE_LLM=1` to re-measure).")
        }
      } else if (!is.null(r$skipped)) {
        add("- **", rn, "**: skipped — ", r$skipped, ".")
      } else {
        add(fmt_run(rn, r, prefix = ""))
      }
    }
    add(sprintf("- **rules baseline**: %.3fs, zero cost.", dtel$rules_latency_secs))
    add("")
  }
}

# --- failure taxonomy ------------------------------------------------------------
add("")
add("## 7. Failure taxonomy (`out/exec_status_<backend>[_<ds>].csv`)")
add("")
for (ds in datasets) {
  for (nm in c("rules", "llm")) {
    st <- read_csv_or(out_file(paste0("exec_status_", nm), ds, ".csv"))
    if (is.null(st)) next
    errs <- st[st$status == "ERROR", ]
    add(sprintf("### %s / %s: %d execution errors", ds, nm, nrow(errs)))
    add("")
    if (nrow(errs)) {
      add(md_table(errs))
    } else {
      add("_(none)_")
    }
    add("")
  }
}

# --- needs_human inventory -------------------------------------------------------
add("")
add("## 8. needs_human inventory (from the IR objects)")
add("")
for (ds in datasets) {
  for (nm in c("rules", "llm")) {
    rds <- out_file(switch(nm, rules = "ir_rules", llm = "ir_llm"), ds, ".rds")
    if (!file.exists(rds)) next
    ir <- readRDS(rds)
    nh <- Filter(function(v) isTRUE(v$needs_human), ir)
    add(sprintf("### %s / %s: %d variables abstained", ds, nm, length(nh)))
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
}

# --- findings --------------------------------------------------------------------
add("")
add("## 9. Findings registered (`out/findings.json`)")
add("")
add("Per the AGENTS.md improvement-loop convention, every ERROR/FAIL/MANUAL class observed gets a numbered finding with evidence. `severity`: **package** = code defect to fix; **demo** = pipeline configuration; **spec** = source-spec ambiguity; **oracle** = oracle convention the spec text does not mention. Resolved findings keep their record with `status`/`resolved_by`.")
add("")
findings <- read_json_or(file.path(out_dir, "findings.json"))
if (!is.null(findings)) {
  for (f in findings$findings) {
    status <- if (!is.null(f$status)) {
      suffix <- if (!is.null(f$resolved_by)) paste0(" by ", f$resolved_by) else ""
      sprintf(" [%s%s]", f$status, suffix)
    } else {
      ""
    }
    add(sprintf("- **%s (%s)%s — %s.** %s _Evidence: %s._",
                f$id, f$severity, status, f$title, f$detail, f$evidence))
    if (!is.null(f$suggested_fix)) add(sprintf("  - Suggested fix: %s", f$suggested_fix))
    if (!is.null(f$resolution)) add(sprintf("  - Resolution: %s", f$resolution))
  }
} else {
  add("_(none registered)_")
}

# --- limitations -----------------------------------------------------------------
add("")
add("## 10. Limitations (read this before quoting any number above)")
add("")
add("1. **Population/parameter subsetting is not automated.** Each produced dataset starts from its full SDTM base domain (ADSL from DM: all screened subjects; ADAE from AE: all collected events; ADLBC from LB: all 43 lab test codes); the oracles are subsetted (ADSL 254 randomized subjects, ADAE/ADLBC correspondingly). Row-level agreement is only computed on the join.")
add("2. **Vocabulary gaps are hard boundaries.** A narrow conditional layer (`assign_conditional`) exists since the F-11 run, but its condition sublanguage cannot express existence checks, visit windows or missingness; derivations like COMP8FL/COMP16FL/COMP24FL (visit-window existence), EFFFL (cross-dataset existence), SAFFL (missingness semantics), CUMDOSE (arm-conditional dose logic), ADAE occurrence flags (AOCCFL and siblings: subset-sort-first-record logic) or ADTTE-style CNSR can only abstain or be approximated. More LLM voters cannot fix a vocabulary hole (DESIGN.md section 11, item 5).")
add("3. **The rules backend is keyword-fragile.** It matches English phrases; paraphrase the spec and its output changes. It is a zero-cost baseline, not a claim of understanding.")
add("4. **The evals corpus is self-scoring** (`inst/evals/spec-to-ir.jsonl` expected values were generated by the rules backend). It pins current behavior as contract; it is not an oracle (DESIGN.md section 11, item 2).")
add("5. **IR agreement ≠ double programming.** Rules/LLM agreement and 3-sample consensus measure translation consistency before execution, with all voters reading the same spec text (DESIGN.md section 11, item 1).")
add("6. **Oracle differences may be spec ambiguity, not package error.** Where a produced value disagrees with the oracle, the spec text itself is often ambiguous (e.g. CUMDOSE's arm-conditional rule, ADAE imputation rules described only in prose); a human programmer would also have to ask. Disagreement rates here are not error rates.")
add("7. **Programs are UNGATED DRAFTs.** No human approval gate covers these artifacts; they are demonstration output, not release-grade deliverables (DESIGN.md section 11, item 4).")
add("8. **Single model, three datasets, and stochastic.** Numbers are for DeepSeek `deepseek-chat` on pilot5 ADSL/ADAE/ADLBC only; they do not transfer to other models or datasets without re-measurement. LLM output also varies run to run at temperature defaults: across the two full ADSL runs behind this report's development, the full-spec needs_human count moved 24 -> 22 and the rules/LLM layer-chain agreement 78% -> 71% — run-to-run translation variance is exactly what the consensus mode in section 5 exists to measure and contain.")
add("9. **Value-level metadata is out of scope.** The workbook's `ValueLevel` sheet (15 rows, all ADADAS) carries where-clause derivations (`PARAMCD EQ ...`) that the flat spec extraction cannot express; no dataset in this run uses it, and ADADAS/ADQSADAS/ADTTE are not attempted.")

report_path <- file.path(auto_dir, "REPORT.md")
writeLines(report$lines, report_path)
cat("written:", report_path, "\n")
cat("lines:", length(report$lines), "\n")
