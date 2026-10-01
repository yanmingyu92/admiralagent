# Stage 04 - oracle compare: produced ADSL vs pilot5 original ADaM adsl.xpt.
#
# diffdf is not installed on this machine, so comparison is base R: per spec
# variable, join on USUBJID and compute value agreement with a documented
# tolerance (dates exact after as.Date; numerics within 1e-6 relative or
# 0.5 absolute for ratio-derived measures like BMI; characters exact).
# Row-count differences are reported, not hidden: the pipeline builds ADSL
# from DM (all screened subjects) and does NOT subset to the randomized
# population, while the oracle has 254 subjects.
#
# Outputs (demo/automation/out/):
#   - accuracy_<backend>.csv   per-variable agreement table
#   - accuracy_summary.json    headline numbers per backend

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("04", "oracle compare")

spec <- readRDS(file.path(OUT_DIR, "spec_adsl.rds"))
oracle <- as.data.frame(haven::read_xpt(file.path(ORACLE_DIR, "adsl.xpt")))

as_compare_date <- function(x) {
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (inherits(x, "Date")) return(x)
  if (is.numeric(x)) return(as.Date(x, origin = "1960-01-01"))
  suppressWarnings(as.Date(x))
}

compare_var <- function(ours, oracle, var, type) {
  if (!var %in% names(ours)) return(list(status = "not_produced", agree = NA_real_, n = 0L, rounded_agree = NA_real_, note = ""))
  if (!var %in% names(oracle)) return(list(status = "not_in_oracle", agree = NA_real_, n = 0L, rounded_agree = NA_real_, note = ""))
  if (identical(var, "USUBJID")) {
    return(list(status = "compared", agree = mean(ours[[var]] %in% oracle[[var]]),
                n = nrow(ours), rounded_agree = NA_real_,
                note = "set overlap (row populations differ by design)"))
  }
  m <- merge(ours[, c("USUBJID", var), drop = FALSE],
             oracle[, c("USUBJID", var), drop = FALSE],
             by = "USUBJID", suffixes = c(".ours", ".oracle"))
  a <- m[[paste0(var, ".ours")]]
  b <- m[[paste0(var, ".oracle")]]
  is_date <- grepl("(DT|DTM)$", var)
  rounded_agree <- NA_real_
  if (is_date) {
    a <- as_compare_date(a); b <- as_compare_date(b)
    eq <- !is.na(a) & !is.na(b) & a == b
  } else if (type %in% c("integer", "float")) {
    a <- suppressWarnings(as.numeric(a)); b <- suppressWarnings(as.numeric(b))
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

backends <- c("rules", "llm", "consensus")
summary_all <- list(stage = "04_oracle_compare",
                    generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
                    oracle = list(file = file.path(ORACLE_DIR, "adsl.xpt"),
                                  rows = nrow(oracle), cols = ncol(oracle)),
                    note = "produced ADSL is built from DM (no population subset); oracle has 254 subjects",
                    backends = list())

for (nm in backends) {
  rds <- file.path(OUT_DIR, paste0("adsl_", nm, ".rds"))
  if (!file.exists(rds)) next
  ours <- as.data.frame(readRDS(rds))
  rows <- lapply(seq_len(nrow(spec)), function(i) {
    v <- spec$variable[i]
    r <- compare_var(ours, oracle, v, spec$type[i])
    data.frame(variable = v, status = r$status,
               value_agree = ifelse(is.na(r$agree), NA, round(100 * r$agree, 1)),
               value_agree_oracle_prec = ifelse(is.na(r$rounded_agree), NA, round(100 * r$rounded_agree, 1)),
               n_joined = r$n, note = r$note, stringsAsFactors = FALSE)
  })
  acc <- do.call(rbind, rows)
  utils::write.csv(acc, file.path(OUT_DIR, paste0("accuracy_", nm, ".csv")), row.names = FALSE)

  cmp <- acc[acc$status == "compared" & acc$variable != "USUBJID", ]
  fully <- sum(!is.na(cmp$value_agree) & cmp$value_agree == 100)
  summary_all$backends[[nm]] <- list(
    produced_rows = nrow(ours),
    spec_variables = nrow(spec),
    compared = nrow(cmp),
    fully_matching = fully,
    partial = sum(!is.na(cmp$value_agree) & cmp$value_agree < 100),
    mean_value_agree = if (nrow(cmp)) round(mean(cmp$value_agree, na.rm = TRUE), 1) else NA_real_
  )
  cat(sprintf("%-10s compared=%d full-match=%d partial=%d mean-agree=%.1f%%\n",
              nm, nrow(cmp), fully, summary_all$backends[[nm]]$partial,
              summary_all$backends[[nm]]$mean_value_agree))
}

write_json(summary_all, file.path(OUT_DIR, "accuracy_summary.json"))
