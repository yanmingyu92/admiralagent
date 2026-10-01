# Stage 04 - oracle compare: produced datasets vs pilot5 original ADaM xpt.
#
# diffdf is not installed on this machine, so comparison is base R: per spec
# variable, join on the dataset's row-identity keys (dataset_oracle_keys():
# ADSL=USUBJID, ADAE=USUBJID+AESEQ, ADLBC=USUBJID+LBSEQ) and compute value
# agreement with a documented tolerance (dates exact after as.Date; numerics
# within 1e-6 or 0.5 absolute for ratio-derived measures like BMI; characters
# exact). Row-count differences are reported, not hidden: the pipeline builds
# each dataset from its full SDTM base domain and does NOT subset to the
# analysis populations, while the oracles do (ADSL 254 subjects; ADAE/ADLBC
# are likewise population- and parameter-subsetted).
#
# Outputs (demo/automation/out/, per dataset; ADSL keeps unsuffixed names):
#   - accuracy_<backend>[_<ds>].csv   per-variable agreement table
#   - accuracy_summary.json           headline numbers per dataset/backend

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("04", "oracle compare")

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
  # Variables unpopulated on BOTH sides (e.g. ADAE *CD MedDRA code vars, which
  # the pilot5 SDTM never collected) have no value pairs to compare; reporting
  # mean(eq) = 0% there would look like total disagreement when it is really
  # "nothing to compare" (finding F-08).
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
    # HEIGHTBL/WEIGHTBL: the oracle stores values rounded to 1 decimal while
    # the spec text says nothing about rounding; report agreement at oracle
    # precision alongside the raw agreement so the rounding convention is
    # visible instead of looking like a derivation error (finding F-05).
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

summary_all <- list(stage = "04_oracle_compare",
                    generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
                    note = paste("produced datasets are built from the full SDTM base domain",
                                 "(no population/parameter subsetting); oracles are subsetted"),
                    datasets = list())

for (ds in showcase_datasets()) {
  oracle_file <- file.path(oracle_dir, paste0(tolower(ds), ".xpt"))
  if (!file.exists(oracle_file)) {
    cat(sprintf("%-6s SKIPPED: no oracle at %s\n", ds, oracle_file))
    next
  }
  spec <- readRDS(out_file_ds("spec", ds, ".rds"))
  oracle <- as.data.frame(haven::read_xpt(oracle_file))
  keys <- dataset_oracle_keys(ds)

  ds_summary <- list(oracle = list(file = oracle_file, rows = nrow(oracle), cols = ncol(oracle)),
                     join_keys = keys, backends = list())

  for (nm in c("rules", "llm", "consensus")) {
    rds <- file.path(out_dir, paste0(tolower(ds), "_", nm, ".rds"))
    if (!file.exists(rds)) next
    ours <- as.data.frame(readRDS(rds))
    rows <- lapply(seq_len(nrow(spec)), function(i) {
      v <- spec$variable[i]
      r <- compare_var(ours, oracle, v, spec$type[i], keys)
      data.frame(variable = v, status = r$status,
                 value_agree = ifelse(is.na(r$agree), NA, round(100 * r$agree, 1)),
                 value_agree_oracle_prec = ifelse(is.na(r$rounded_agree), NA, round(100 * r$rounded_agree, 1)),
                 n_joined = r$n, note = r$note, stringsAsFactors = FALSE)
    })
    acc <- do.call(rbind, rows)
    utils::write.csv(acc, out_file(paste0("accuracy_", nm), ds, ".csv"), row.names = FALSE)

    cmp <- acc[acc$status == "compared" & acc$variable != "USUBJID", ]
    fully <- sum(!is.na(cmp$value_agree) & cmp$value_agree == 100)
    ds_summary$backends[[nm]] <- list(
      produced_rows = nrow(ours),
      spec_variables = nrow(spec),
      compared = nrow(cmp),
      fully_matching = fully,
      partial = sum(!is.na(cmp$value_agree) & cmp$value_agree < 100),
      mean_value_agree = if (nrow(cmp)) round(mean(cmp$value_agree, na.rm = TRUE), 1) else NA_real_
    )
    cat(sprintf("%-6s %-10s compared=%d full-match=%d partial=%d mean-agree=%.1f%%\n",
                ds, nm, nrow(cmp), fully, ds_summary$backends[[nm]]$partial,
                ds_summary$backends[[nm]]$mean_value_agree))
  }
  summary_all$datasets[[ds]] <- ds_summary
}

write_json(summary_all, file.path(out_dir, "accuracy_summary.json"))
