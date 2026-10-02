# Stage 08 - compare: constrained-IR arm vs free-form CONTROL ARM on ADSL.
#
# Scores both arms of the experiment in .agents/freeform-comparison-design.md
# with ONE oracle yardstick: compare_var() is copied verbatim from
# 04_oracle_compare.R (same join keys, same tolerances, same status semantics)
# so arm B's numbers are computed by exactly the code that produced arm A's.
# Arm A numbers are READ from the existing out/ machine files (cache of
# 2026-10-01, telemetry carried in llm_telemetry.json); this stage never
# re-runs arm A and never invents a number - every figure in
# compare_summary.json names the file it came from.
#
# Metric definitions (also embedded in compare_summary.json$definitions):
#   coverage        EXECUTED / 49 spec variables, per arm
#   silent_error    EXECUTED, nothing flagged the variable (arm A: validation
#                   status PASS; arm B: no warning captured), oracle compared,
#                   value_agree < 100 - the answer is wrong and no tripwire fired
#   fail_closed     arm A only: needs_human abstentions + validation FAILs +
#                   execution ERRORs, i.e. cases where the pipeline refused or
#                   blew up instead of silently emitting a wrong answer
#   review_burden   proxy only: non-blank LOC / comment lines / bare logic
#                   points (code line not preceded by a comment) of the code a
#                   reviewer must read; arm A artifacts include the mandated
#                   CHECK comments and DISCLAIMER header
#
# Outputs (demo/automation/out/):
#   - compare_accuracy_freeform.csv   arm B oracle agreement (accuracy_*.csv schema)
#   - compare_review_burden.csv       per-variable code metrics, both arms
#   - compare_summary.json            the machine-readable headline table

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("08", "compare arms (constrained IR vs free-form)")

# --- compare_var, VERBATIM copy from 04_oracle_compare.R (do not "improve") ---

as_compare_date <- function(x) {
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (inherits(x, "Date")) return(x)
  if (is.numeric(x)) return(as.Date(x, origin = "1960-01-01"))
  suppressWarnings(as.Date(x))
}

compare_var <- function(ours, oracle, var, type, keys) {
  if (!var %in% names(ours)) return(list(status = "not_produced", agree = NA_real_, n = 0L, rounded_agree = NA_real_, note = ""))
  if (!var %in% names(oracle)) return(list(status = "not_in_oracle", agree = NA_real_, n = 0L, rounded_agree = NA_real_, note = ""))
  if (identical(var, "USUBJID")) {
    return(list(status = "compared", agree = mean(ours[[var]] %in% oracle[[var]]),
                n = nrow(ours), rounded_agree = NA_real_,
                note = "set overlap (row populations differ by design)"))
  }
  if (var %in% keys) {
    return(list(status = "join_key", agree = NA_real_, n = 0L, rounded_agree = NA_real_,
                note = "row-identity key used for the join; not compared as a value"))
  }
  m <- merge(ours[, c(keys, var), drop = FALSE],
             oracle[, c(keys, var), drop = FALSE],
             by = keys, suffixes = c(".ours", ".oracle"))
  a <- m[[paste0(var, ".ours")]]
  b <- m[[paste0(var, ".oracle")]]
  if (nrow(m) > 0L && all(is.na(a)) && all(is.na(b))) {
    return(list(status = "all_missing", agree = NA_real_, n = nrow(m), rounded_agree = NA_real_,
                note = "unpopulated on both sides; no value pairs to compare"))
  }
  is_date <- grepl("(DT|DTM)$", var)
  rounded_agree <- NA_real_
  if (is_date) {
    a <- as_compare_date(a)
    b <- as_compare_date(b)
    eq <- !is.na(a) & !is.na(b) & a == b
  } else if (type %in% c("integer", "float")) {
    a <- suppressWarnings(as.numeric(a))
    b <- suppressWarnings(as.numeric(b))
    tol <- if (var %in% c("BMIBL", "AVGDD")) 0.5 else 1e-6
    eq <- !is.na(a) & !is.na(b) & abs(a - b) <= tol
    if (var %in% c("HEIGHTBL", "WEIGHTBL")) {
      rounded_agree <- mean(!is.na(a) & !is.na(b) & round(a, 1) == b)
    }
  } else {
    eq <- !is.na(a) & !is.na(b) & as.character(a) == as.character(b)
  }
  na_agree <- mean(is.na(a) == is.na(b))
  list(status = "compared", agree = mean(eq), n = nrow(m),
       rounded_agree = rounded_agree,
       note = sprintf("na_agree=%.2f", na_agree))
}

accuracy_for <- function(ours, oracle, spec, keys) {
  rows <- lapply(seq_len(nrow(spec)), function(i) {
    v <- spec$variable[i]
    r <- compare_var(ours, oracle, v, spec$type[i], keys)
    data.frame(variable = v, status = r$status,
               value_agree = ifelse(is.na(r$agree), NA, round(100 * r$agree, 1)),
               value_agree_oracle_prec = ifelse(is.na(r$rounded_agree), NA, round(100 * r$rounded_agree, 1)),
               n_joined = r$n, note = r$note, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

acc_headline <- function(acc) {
  cmp <- acc[acc$status == "compared" & acc$variable != "USUBJID", ]
  list(compared = nrow(cmp),
       fully_matching = sum(!is.na(cmp$value_agree) & cmp$value_agree == 100),
       partial = sum(!is.na(cmp$value_agree) & cmp$value_agree < 100),
       mean_value_agree = if (nrow(cmp)) round(mean(cmp$value_agree, na.rm = TRUE), 1) else NA_real_)
}

code_metrics <- function(path) {
  lines <- readLines(path, warn = FALSE)
  nonblank <- nzchar(trimws(lines))
  is_comment <- grepl("^#", trimws(lines))
  code_idx <- which(nonblank & !is_comment)
  bare <- sum(vapply(code_idx, function(i) i == 1L || !is_comment[i - 1L], logical(1)))
  list(loc = sum(nonblank), comment_lines = sum(is_comment), bare_logic_points = bare)
}

spec <- readRDS(out_file_ds("spec", "ADSL", ".rds"))
keys <- dataset_oracle_keys("ADSL")
oracle <- as.data.frame(haven::read_xpt(file.path(oracle_dir, "adsl.xpt")))

# --- arm B: free-form ---------------------------------------------------------

ff_rds <- file.path(out_dir, "adsl_freeform.rds")
if (!file.exists(ff_rds)) stop("run 07_freeform_execute.R first; ", ff_rds, " missing")
ff <- as.data.frame(readRDS(ff_rds))
acc_b <- accuracy_for(ff, oracle, spec, keys)
exec_b <- utils::read.csv(file.path(out_dir, "compare_exec_status.csv"), stringsAsFactors = FALSE)
# Scoring gate: a variable the arm never derived is NOT "produced", even when
# the column rides along from the DM seed every arm starts from. Otherwise
# untried DM copies (SITEID, RACE, ...) would inflate arm B's agreement table.
# Verified symmetric for arm A: all 20 of its compared variables are EXECUTED.
not_derived <- !acc_b$variable %in% exec_b$variable[exec_b$status == "EXECUTED"]
acc_b$status[not_derived & acc_b$status == "compared"] <- "not_produced"
acc_b$value_agree[not_derived] <- NA_real_
acc_b$note[not_derived] <- "not derived by this arm (column only present via the DM seed)"
utils::write.csv(acc_b, file.path(out_dir, "compare_accuracy_freeform.csv"), row.names = FALSE)
gen_b <- utils::read.csv(file.path(out_dir, "compare_freeform_gen.csv"), stringsAsFactors = FALSE)
tel_b <- jsonlite::read_json(file.path(out_dir, "compare_freeform_telemetry.json"), simplifyVector = FALSE)

hl_b <- acc_headline(acc_b)
silent_b_df <- merge(exec_b[exec_b$status == "EXECUTED" & !exec_b$had_warning, c("variable", "error_msg")],
                     acc_b[acc_b$status == "compared" & acc_b$variable != "USUBJID" &
                             !is.na(acc_b$value_agree) & acc_b$value_agree < 100, ],
                     by = "variable")
silent_b_df <- silent_b_df[!nzchar(silent_b_df$error_msg), ]

# --- arm A: constrained IR (read-only, cached evidence) -----------------------

acc_a <- utils::read.csv(file.path(out_dir, "accuracy_llm.csv"), stringsAsFactors = FALSE)
exec_a <- utils::read.csv(file.path(out_dir, "exec_status_llm.csv"), stringsAsFactors = FALSE)
val_a <- utils::read.csv(file.path(out_dir, "validation_llm.csv"), stringsAsFactors = FALSE)
gate <- jsonlite::read_json(file.path(out_dir, "gate_report.json"), simplifyVector = FALSE)
tel_a <- jsonlite::read_json(file.path(out_dir, "llm_telemetry.json"), simplifyVector = FALSE)
ir_a <- readRDS(out_file("ir_llm", "ADSL", ".rds"))

hl_a <- acc_headline(acc_a[acc_a$variable %in% exec_a$variable[exec_a$status == "EXECUTED"], ])
val_status <- stats::setNames(val_a$status, val_a$variable)
exec_ok_a <- exec_a$variable[exec_a$status == "EXECUTED"]
silent_a <- acc_a$variable[acc_a$status == "compared" & acc_a$variable != "USUBJID" &
                             !is.na(acc_a$value_agree) & acc_a$value_agree < 100 &
                             acc_a$variable %in% exec_ok_a &
                             val_status[acc_a$variable] == "PASS"]

nh_a <- sum(vapply(ir_a, function(v) isTRUE(v$needs_human), logical(1)))
arm_a_cost <- tryCatch({
  e <- tel_a$datasets$ADSL$runs$full
  if (isTRUE(e$cached)) e <- e$last_uncached
  e$cost_usd
}, error = function(e) NULL)

# Per-variable detail for every silent error, so the mechanical metric can be
# audited against known oracle conventions (e.g. F-05 rounding) instead of
# quoted as a bare count.
silent_detail <- function(vars, acc) {
  if (!length(vars)) return(list())
  lapply(vars, function(v) {
    r <- acc[acc$variable == v, ]
    list(variable = v, value_agree = r$value_agree,
         value_agree_oracle_prec = if (is.na(r$value_agree_oracle_prec)) NULL else r$value_agree_oracle_prec)
  })
}
silent_a_detail <- silent_detail(silent_a, acc_a)
silent_b_detail <- silent_detail(silent_b_df$variable, acc_b)

# --- review burden proxy, both arms -------------------------------------------

burden <- list()
art_dir <- file.path(out_dir, "artifacts", "llm")
# Variable artifacts are named with the hash of the WHOLE IR set, not the
# single variable (write_artifact: artifact_hash(ir)); the current cache's set
# hash matches gate_report.json$datasets$ADSL$llm$artifact_hash.
set_hash_a <- artifact_hash(ir_a)
for (v in ir_a) {
  if (isTRUE(v$needs_human)) next
  f <- file.path(art_dir, sprintf("adsl__%s__%s.R", tolower(v$variable), set_hash_a))
  if (!file.exists(f)) next
  m <- code_metrics(f)
  burden[[length(burden) + 1L]] <- data.frame(
    variable = v$variable, arm = "constrained_ir", loc = m$loc,
    comment_lines = m$comment_lines, bare_logic_points = m$bare_logic_points,
    stringsAsFactors = FALSE
  )
}
for (i in seq_len(nrow(gen_b))) {
  if (gen_b$status[i] != "ok") next
  f <- file.path(auto_dir, "freeform", sprintf("adsl__%s__freeform.R", tolower(gen_b$variable[i])))
  if (!file.exists(f)) next
  m <- code_metrics(f)
  burden[[length(burden) + 1L]] <- data.frame(
    variable = gen_b$variable[i], arm = "freeform", loc = m$loc,
    comment_lines = m$comment_lines, bare_logic_points = m$bare_logic_points,
    stringsAsFactors = FALSE
  )
}
burden <- do.call(rbind, burden)
utils::write.csv(burden, file.path(out_dir, "compare_review_burden.csv"), row.names = FALSE)

burden_sum <- function(arm) {
  b <- burden[burden$arm == arm, ]
  list(variables = nrow(b), total_loc = sum(b$loc),
       total_comment_lines = sum(b$comment_lines),
       total_bare_logic_points = sum(b$bare_logic_points),
       median_loc = stats::median(b$loc))
}

# --- headline summary ----------------------------------------------------------

src <- function(...) file.path("demo/automation/out", ...)
summary <- list(
  stage = "08_compare",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  design_doc = ".agents/freeform-comparison-design.md",
  dataset = "ADSL", spec_variables = nrow(spec), model = "deepseek-chat",
  arms = list(
    constrained_ir = c(list(
      description = "LLM translates spec to closed-vocabulary Layer IR; deterministic compiler renders code; validate_ir() fail-closed",
      evidence_files = list(src("ir_llm.rds"), src("accuracy_llm.csv"), src("exec_status_llm.csv"),
                            src("validation_llm.csv"), src("gate_report.json"), src("llm_telemetry.json")),
      cache_date = "2026-10-01 (reused, zero new LLM spend)",
      abstained_needs_human = nh_a,
      executed = sum(exec_a$status == "EXECUTED"),
      execution_errors = sum(exec_a$status == "ERROR"),
      validation_fail = sum(val_a$status == "FAIL"),
      silent_errors = length(silent_a),
      silent_error_variables = silent_a,
      silent_error_detail = silent_a_detail,
      review_burden = burden_sum("constrained_ir"),
      cost_usd = arm_a_cost
    ), hl_a),
    freeform = c(list(
      description = "LLM writes executable R directly, same schema-level inputs, sandboxed; NOT package output",
      evidence_files = list(src("compare_freeform_gen.csv"), src("compare_exec_status.csv"),
                            src("compare_accuracy_freeform.csv"), src("compare_freeform_telemetry.json")),
      generated_ok = sum(gen_b$status == "ok"),
      abstained = sum(gen_b$status == "abstain"),
      blocked_by_static_gate = sum(gen_b$status == "blocked"),
      parse_fail = sum(gen_b$status == "parse_fail"),
      call_errors = sum(gen_b$status == "error"),
      executed = sum(exec_b$status == "EXECUTED"),
      execution_errors = sum(exec_b$status == "ERROR"),
      executed_with_warnings = sum(exec_b$status == "EXECUTED" & exec_b$had_warning),
      silent_errors = nrow(silent_b_df),
      silent_error_variables = silent_b_df$variable,
      silent_error_detail = silent_b_detail,
      review_burden = burden_sum("freeform"),
      cost_usd = tel_b$cost_usd
    ), hl_b)
  ),
  definitions = list(
    coverage = "executed / 49 spec variables, per arm",
    silent_error = paste("EXECUTED + nothing flagged the variable (arm A: validation PASS;",
                         "arm B: no warning captured) + oracle compared + value_agree < 100"),
    fail_closed = "arm A: needs_human abstentions + validation FAIL + execution ERROR; arm B analogues: abstain + static-gate BLOCKED + execution ERROR",
    review_burden = "proxy: non-blank LOC / comment lines / bare logic points of generated code; arm A LOC includes mandated CHECK comments and DISCLAIMER header"
  ),
  honesty = list(
    "variables an arm did not derive are scored not_produced even when the DM seed every arm starts from already carries the column (verified a no-op for arm A: its 20 compared variables are all EXECUTED)",
    "single model (deepseek-chat), single study (pilot5 ADSL), single run per arm",
    "arm A numbers are from the 2026-10-01 cached run; arm B is a fresh run - run-to-run LLM variance is documented in REPORT.md limitation 8",
    "oracle agreement is not double programming (DESIGN.md section 11.1)",
    "review burden is a mechanical proxy, not a measured human review effort",
    "spec-ambiguity disagreements (findings F-04/F-09) are not scored as errors for either arm"
  )
)
write_json(summary, file.path(out_dir, "compare_summary.json"))

cat(sprintf("\n%-28s %14s %12s\n", "", "constrained_ir", "freeform"))
row <- function(label, a, b) cat(sprintf("%-28s %14s %12s\n", label, a, b))
row("abstained / blocked", nh_a, sum(gen_b$status %in% c("abstain", "blocked", "parse_fail", "error")))
row("executed", sum(exec_a$status == "EXECUTED"), sum(exec_b$status == "EXECUTED"))
row("execution errors", sum(exec_a$status == "ERROR"), sum(exec_b$status == "ERROR"))
row("oracle compared", hl_a$compared, hl_b$compared)
row("full match (100%)", hl_a$fully_matching, hl_b$fully_matching)
row("mean value agree %", hl_a$mean_value_agree, hl_b$mean_value_agree)
row("SILENT ERRORS", length(silent_a), nrow(silent_b_df))
row("cost USD", ifelse(is.null(arm_a_cost), "n/a", arm_a_cost), tel_b$cost_usd)
