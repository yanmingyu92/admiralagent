# Stage 06 - freeform generate (CONTROL ARM of the comparison experiment).
#
# This is the free-form code generation arm of the controlled experiment
# designed in .agents/freeform-comparison-design.md: DeepSeek writes executable
# R code directly (the "skill route"), given the SAME schema-level inputs the
# constrained-IR arm receives (build_context() JSON, SDTM column schemas,
# codelist metadata - never patient data rows). The generated code lives only
# in demo/automation/freeform/, is executed in a separate R process by
# 07_freeform_execute.R, and never enters the package, the production pipeline
# (stages 00-05), or any release surface.
#
# Sandbox rules enforced HERE (before any execution):
#   - static blacklist scan (no package installs, no network, no system calls,
#     no library()/require() calls - the whitelist is preloaded by stage 07);
#   - the file must parse and define exactly the contracted `derive` function.
# BLOCKED / PARSE_FAIL results are recorded, never repaired by hand.
#
# Cost control: per-variable calls, running cost estimate with a hard circuit
# breaker (AA_FREEFORM_BUDGET, default $0.50). Pilot a subset with
# AA_FREEFORM_VARS="AGE,TRTSDT,..."; AA_FREEFORM_FORCE=1 regenerates existing
# sandbox files (re-spends money).
#
# Outputs (demo/automation/out/ + demo/automation/freeform/):
#   - freeform/adsl__<var>__freeform.R   sandbox code, CONTROL ARM banner
#   - freeform/raw/<var>.txt             verbatim LLM responses (audit trail)
#   - out/compare_freeform_gen.csv       per-variable status + code metrics
#   - out/compare_freeform_telemetry.json tokens + cost with rate assumption

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("06", "freeform generate (CONTROL ARM)")

freeform_dir <- file.path(auto_dir, "freeform")
raw_dir <- file.path(freeform_dir, "raw")
for (d in c(freeform_dir, raw_dir)) if (!dir.exists(d)) dir.create(d, recursive = TRUE)

force <- nzchar(Sys.getenv("AA_FREEFORM_FORCE"))
budget <- as.numeric(Sys.getenv("AA_FREEFORM_BUDGET", "0.50"))

# DeepSeek deepseek-chat list prices (same assumption as 01_classify.R so the
# two arms' costs are computed on one recorded rate).
deepseek_rate <- list(input_per_m = 0.27, output_per_m = 1.10, as_of = "2025 price sheet")

chat_tokens <- function(chat) {
  tryCatch({
    turns <- chat$get_turns()
    if (!length(turns)) return(NULL)
    tk <- lapply(turns, function(t) {
      x <- tryCatch(t@tokens, error = function(e) NULL)
      if (is.numeric(x) && length(x) >= 2) x[1:2] else c(NA_real_, NA_real_)
    })
    mat <- do.call(rbind, tk)
    list(input = sum(mat[, 1], na.rm = TRUE), output = sum(mat[, 2], na.rm = TRUE))
  }, error = function(e) NULL)
}

token_cost <- function(tokens) {
  if (is.null(tokens)) return(0)
  tokens$input / 1e6 * deepseek_rate$input_per_m +
    tokens$output / 1e6 * deepseek_rate$output_per_m
}

# --- schema-level context (identical information class as arm A) --------------

spec <- readRDS(out_file_ds("spec", "ADSL", ".rds"))
sdtm <- load_pilot5_sdtm()
codelists <- codelists_from_define_xlsx(spec_xlsx)

# Column-level schema text for every SDTM domain: names, labels, types. This is
# metadata only - no data rows ever enter the prompt (same privacy rule as
# build_context(), AGENTS.md hard rule 5).
sdtm_schema_text <- function(sdtm) {
  blocks <- vapply(names(sdtm), function(nm) {
    df <- sdtm[[nm]]
    cols <- vapply(names(df), function(cn) {
      lab <- attr(df[[cn]], "label")
      lab <- if (is.null(lab) || !nzchar(lab)) "" else paste0(" - ", lab)
      typ <- if (is.numeric(df[[cn]])) "num" else "char"
      sprintf("  %s (%s)%s", cn, typ, lab)
    }, character(1))
    paste0(sprintf("%s [%d rows x %d cols]\n", toupper(nm), nrow(df), ncol(df)),
           paste(cols, collapse = "\n"))
  }, character(1))
  paste(blocks, collapse = "\n\n")
}

# System prompt written to the standard a careful skill author would reach:
# role, full study schema, the admiral usage notes such a skill would carry,
# the output contract, and the safety constraints. It deliberately does NOT
# mention the package's 15-layer vocabulary - that closed vocabulary is arm A's
# private constraint, not public knowledge a free-form baseline would have.
build_freeform_system_prompt <- function(schema_text) {
  paste0(
    "You are an expert clinical statistical programmer writing R code to derive ",
    "ADaM ADSL variables from SDTM data for a CDISC pilot study, using the ",
    "{admiral} package (v1.5) and dplyr.\n\n",
    "## Data available to your code\n\n",
    "Your function receives two arguments:\n",
    "- `adsl`: the ADSL dataset under construction (a tibble). It starts as a copy ",
    "of DM and accumulates derived variables as earlier derivations run, so you may ",
    "use any ADSL variable derived before yours.\n",
    "- `sources`: a named list of SDTM tibbles (dm, ex, vs, ae, sv, ds, sc, mh, qs, lb), ",
    "plus `sources$mc` (a metacore object; you will not normally need it). The vs/lb ",
    "datasets carry convenience columns AVAL and PARAMCD.\n\n",
    "## SDTM schemas (column metadata)\n\n", schema_text, "\n\n",
    "## admiral quick reference (v1.5 signatures, abridged)\n\n",
    "- derive_vars_merged(dataset, dataset_add, by_vars, order = NULL, new_vars = NULL, ",
    "mode = NULL, filter_add = NULL): merge selected/renamed columns from another ",
    "dataset; mode \"first\"/\"last\" with order picks one record per by-group, e.g. ",
    "new_vars = vars(TRTSDT = convert_dtc_to_dt(SVSTDTC)).\n",
    "- derive_vars_dt(dataset, new_vars_prefix, dtc, highest_imputation = \"n\", ",
    "date_imputation = NULL, min_dates = NULL, max_dates = NULL): convert a --DTC ",
    "character column to a *DT date with imputation + DTF flag.\n",
    "- derive_vars_dtm(dataset, new_vars_prefix, dtc, highest_imputation = \"n\", ",
    "date_imputation = NULL, time_imputation = NULL): same for *DTM datetimes.\n",
    "- derive_vars_duration(dataset, new_var, new_var_unit = NULL, start_date, ",
    "end_date, out_unit = \"days\"): duration between two dates.\n",
    "- derive_var_extreme_flag(dataset, by_vars, order, new_var, mode, ",
    "filter_add = NULL, true_value = \"Y\", false_value = NA_character_): flag the ",
    "first/last record per by-group.\n",
    "- derive_param_computed(dataset, dataset_add = NULL, by_vars, parameters, ",
    "set_values_to, filter = NULL): compute a BDS parameter from others.\n",
    "- convert_dtc_to_dt(dtc) / convert_dtc_to_dtm(dtc): parse ISO 8601 --DTC ",
    "strings (partial dates become NA unless imputed).\n",
    "- Plain dplyr (mutate, case_when, cut, recode, coalesce, if_else) is fine for ",
    "categorizations, arithmetic, and conditional constants.\n\n",
    "## Output contract\n\n",
    "Reply with exactly one ```r code fence containing the complete function ",
    "definition, and nothing outside the fence:\n\n",
    "derive <- function(adsl, sources) {\n",
    "  # derive <VAR>: brief explanation of the logic for the human reviewer\n",
    "  adsl <- adsl |> ...\n",
    "  adsl\n",
    "}\n\n",
    "## Rules\n\n",
    "1. Only base R, stats, utils, dplyr and admiral may be used; they are already ",
    "loaded, so never call library() or require().\n",
    "2. Never install packages, access the network, read or write files, or call ",
    "system()/shell().\n",
    "3. Deterministic code only: no randomness, no dependence on the current time.\n",
    "4. The derivation text in the specification is the contract; implement it as ",
    "literally as you can. Comment non-obvious logic - a human will review this.\n",
    "5. SDTM dates are ISO 8601 character strings in --DTC columns and may be ",
    "partial; ADaM *DT/*DTM variables are Date/POSIXct.\n",
    "6. If the specification is so under-specified that any implementation would be ",
    "a guess (information missing from both the derivation text and the schemas), ",
    "do NOT guess: reply with the single line `ABSTAIN: <one-sentence reason>` and ",
    "no code fence."
  )
}

user_prompt_for <- function(row_spec, codelist_tbl) {
  ctx <- build_context(row_spec)
  cl_text <- "none"
  if (!is.null(codelist_tbl)) {
    cl_text <- paste(utils::capture.output(print(codelist_tbl, row.names = FALSE)),
                     collapse = "\n")
  }
  paste0(
    "## ADaM variable specification (JSON)\n\n",
    jsonlite::toJSON(ctx, auto_unbox = TRUE, pretty = TRUE),
    "\n\n## Controlled terminology for this variable\n\n", cl_text,
    "\n\nWrite the derive function for this variable now."
  )
}

# --- static sandbox gate (runs before anything is executed) -------------------

blacklist_patterns <- c(
  "install[.]packages", "remotes::", "devtools::", "pak::",
  "download[.]file", "curl", "httr", "RCurl", "url[ ]*[(]", "socketConnection",
  "system[ ]*[(]", "system2[ ]*[(]", "shell[ ]*[(]", "pipe[ ]*[(]",
  "library[ ]*[(]", "require[ ]*[(]", "::",
  "read[.]xpt", "read[.]csv", "readRDS", "saveRDS", "write[.]csv", "save[ ]*[(]", "load[ ]*[(]",
  "setwd", "source[ ]*[(]", "Sys[.]setenv"
)

static_gate <- function(code) {
  hits <- blacklist_patterns[vapply(blacklist_patterns, function(p) grepl(p, code), logical(1))]
  # "::" alone would ban dplyr::mutate-style qualification; the real rule is "no
  # namespace loading outside the whitelist", enforced by banning :: for any
  # package outside the preloaded set.
  hits <- setdiff(hits, "::")
  ns <- regmatches(code, gregexpr("[A-Za-z][A-Za-z0-9.]*::", code))[[1]]
  bad_ns <- setdiff(sub("::$", "", ns), c("base", "stats", "utils", "dplyr", "admiral"))
  if (length(bad_ns)) hits <- c(hits, paste0("namespace:", bad_ns))
  hits
}

extract_code <- function(resp) {
  if (grepl("^ABSTAIN:", trimws(resp))) return(list(abstain = trimws(resp), code = NULL))
  m <- regmatches(resp, regexpr("(?s)```r?\n(.*?)```", resp, perl = TRUE))
  if (!length(m) || !nzchar(m)) return(list(abstain = NULL, code = NULL))
  code <- sub("^```r?\n", "", sub("```$", "", trimws(m)))
  list(abstain = NULL, code = code)
}

code_metrics <- function(path) {
  lines <- readLines(path, warn = FALSE)
  nonblank <- nzchar(trimws(lines))
  is_comment <- grepl("^#", trimws(lines))
  code_idx <- which(nonblank & !is_comment)
  bare <- sum(vapply(code_idx, function(i) i == 1L || !is_comment[i - 1L], logical(1)))
  list(loc = sum(nonblank), comment_lines = sum(is_comment), bare_logic_points = bare)
}

banner <- paste(
  "# CONTROL ARM - free-form generation experiment. NOT package output. Do not ship.",
  "# Generated by demo/automation/06_freeform_generate.R (DeepSeek, direct R code",
  "# generation without the constrained-IR vocabulary). Executed only in the",
  "# sandbox of 07_freeform_execute.R; see .agents/freeform-comparison-design.md.",
  sep = "\n"
)

# --- variable selection -------------------------------------------------------

sel <- Sys.getenv("AA_FREEFORM_VARS")
vars <- if (nzchar(sel)) trimws(strsplit(sel, ",")[[1]]) else spec$variable
missing <- setdiff(vars, spec$variable)
if (length(missing)) stop("AA_FREEFORM_VARS names not in spec: ", paste(missing, collapse = ", "))
cat(sprintf("variables to generate: %d (budget cap $%.2f)\n", length(vars), budget))

sys_prompt <- build_freeform_system_prompt(sdtm_schema_text(sdtm))

rows <- list()
total_cost <- 0
total_in <- 0
total_out <- 0
t0_all <- Sys.time()

for (var in vars) {
  row_spec <- spec[spec$variable == var, , drop = FALSE]
  sandbox_file <- file.path(freeform_dir, sprintf("adsl__%s__freeform.R", tolower(var)))
  raw_file <- file.path(raw_dir, paste0(tolower(var), ".txt"))

  if (file.exists(sandbox_file) && !force) {
    cat(sprintf("%-10s cached (sandbox file exists; AA_FREEFORM_FORCE=1 to re-spend)\n", var))
    next
  }
  if (total_cost >= budget) {
    cat(sprintf("BUDGET BREAKER: cumulative estimate $%.4f >= $%.2f; stopping at %s\n",
                total_cost, budget, var))
    break
  }

  cl_name <- row_spec$codelist
  cl_tbl <- if (!is.na(cl_name) && cl_name %in% names(codelists)) codelists[[cl_name]] else NULL
  prompt <- user_prompt_for(row_spec, cl_tbl)

  status <- "error"
  note <- ""
  attempts <- 0L
  code <- NULL
  var_in <- 0
  var_out <- 0
  feedback <- NULL

  while (attempts < 2L && is.null(code) && status != "abstain") {
    attempts <- attempts + 1L
    chat <- make_chat()
    chat$set_system_prompt(sys_prompt)
    full_prompt <- if (is.null(feedback)) {
      prompt
    } else {
      paste0(prompt, "\n\n## Previous attempt failed\n\n", feedback, "\n\nFix it.")
    }
    resp <- tryCatch(chat$chat(full_prompt), error = function(e) e)
    tk <- chat_tokens(chat)
    if (!is.null(tk)) {
      var_in <- var_in + tk$input
      var_out <- var_out + tk$output
    }
    if (inherits(resp, "error")) {
      status <- "error"
      note <- conditionMessage(resp)
      feedback <- paste("The API call failed with:", conditionMessage(resp))
      next
    }
    writeLines(resp, raw_file)
    ex <- extract_code(resp)
    if (!is.null(ex$abstain)) {
      status <- "abstain"
      note <- ex$abstain
    } else if (is.null(ex$code)) {
      status <- "parse_fail"
      note <- "no ```r code fence in response"
      feedback <- "Your reply contained no ```r code fence. Follow the output contract."
    } else {
      parsed <- tryCatch(parse(text = ex$code), error = function(e) e)
      if (inherits(parsed, "error")) {
        status <- "parse_fail"
        note <- conditionMessage(parsed)
        feedback <- paste("Your code did not parse:", conditionMessage(parsed))
      } else {
        env <- new.env(parent = baseenv())
        eval(parsed, envir = env)
        if (!is.function(env$derive) || !identical(names(formals(env$derive)), c("adsl", "sources"))) {
          status <- "parse_fail"
          note <- "no derive <- function(adsl, sources) definition found"
          feedback <- paste("Define exactly `derive <- function(adsl, sources)`.",
                            "No other top-level entry point is called.")
        } else {
          hits <- static_gate(ex$code)
          if (length(hits)) {
            status <- "blocked"
            note <- paste("static sandbox gate:", paste(hits, collapse = ", "))
            feedback <- paste("Your code violates the sandbox rules:",
                              paste(hits, collapse = ", "),
                              "- see rules 1-2. Rewrite without them.")
            code <- NULL
          } else {
            status <- "ok"
            code <- ex$code
          }
        }
      }
    }
  }
  if (attempts >= 2L && is.null(code) && status %in% c("parse_fail", "blocked")) {
    note <- paste0(note, " (after ", attempts, " attempts)")
  }

  var_cost <- token_cost(list(input = var_in, output = var_out))
  total_cost <- total_cost + var_cost
  total_in <- total_in + var_in
  total_out <- total_out + var_out

  if (!is.null(code)) {
    writeLines(c(banner, "", code), sandbox_file)
  } else if (file.exists(sandbox_file)) {
    file.remove(sandbox_file)
  }

  m <- if (file.exists(sandbox_file)) {
    code_metrics(sandbox_file)
  } else {
    list(loc = NA_integer_, comment_lines = NA_integer_, bare_logic_points = NA_integer_)
  }
  rows[[length(rows) + 1L]] <- data.frame(
    variable = var, status = status,
    loc = m$loc, comment_lines = m$comment_lines, bare_logic_points = m$bare_logic_points,
    tokens_in = var_in, tokens_out = var_out, cost_usd = round(var_cost, 5),
    attempts = attempts, note = substr(note, 1, 300),
    stringsAsFactors = FALSE
  )
  cat(sprintf("%-10s %-10s attempts=%d in=%d out=%d cost=$%.4f %s\n",
              var, status, attempts, var_in, var_out, var_cost,
              if (nzchar(note)) paste0("| ", substr(note, 1, 80)) else ""))
}

gen_csv <- file.path(out_dir, "compare_freeform_gen.csv")
if (length(rows)) {
  new <- do.call(rbind, rows)
  old <- if (file.exists(gen_csv)) utils::read.csv(gen_csv, stringsAsFactors = FALSE) else NULL
  merged <- if (is.null(old)) new else rbind(old[!old$variable %in% new$variable, ], new)
  merged <- merged[order(match(merged$variable, spec$variable)), ]
  utils::write.csv(merged, gen_csv, row.names = FALSE)
}

telemetry <- list(
  stage = "06_freeform_generate",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  arm = "B (free-form code generation, CONTROL ARM - not package output)",
  model = "deepseek-chat",
  rate_assumption = deepseek_rate,
  budget_cap_usd = budget,
  variables_attempted = length(rows),
  tokens = list(input = total_in, output = total_out),
  cost_usd = round(total_cost, 4),
  latency_secs = round(as.numeric(difftime(Sys.time(), t0_all, units = "secs")), 1)
)
write_json(telemetry, file.path(out_dir, "compare_freeform_telemetry.json"))
cat(sprintf("\ntotal: %d variables, $%.4f of $%.2f budget\n", length(rows), total_cost, budget))
