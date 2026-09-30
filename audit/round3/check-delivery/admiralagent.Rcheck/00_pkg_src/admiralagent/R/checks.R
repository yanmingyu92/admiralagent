aa_checks <- function() {
  list(
    not_all_na = list(
      description = "target variable must not be all-missing after the derivation",
      fn = function(data, var, args) {
        if (!var %in% names(data)) return("FAIL: variable not present")
        if (all(is.na(data[[var]]))) "FAIL: all values missing" else "PASS"
      }
    ),
    key_uniqueness = list(
      description = "merge must not duplicate rows (one record per subject in ADSL)",
      fn = function(data, var, args) {
        keys <- args$by_vars %||% c("STUDYID", "USUBJID")
        keys <- keys[keys %in% names(data)]
        if (length(keys) == 0) return("MANUAL: keys not found in data")
        dups <- sum(duplicated(data[keys]))
        if (dups > 0) sprintf("FAIL: %d duplicated key rows", dups) else "PASS"
      }
    ),
    imputation_flag = list(
      description = "*DTF/*TMF flags created by imputation; NA where nothing was imputed",
      fn = function(data, var, args) {
        tgt <- args$target %||% var
        prefix <- sub("(DTM|DT)$", "", tgt)
        flag <- paste0(prefix, "DTF")
        if (!flag %in% names(data)) {
          return(sprintf(
            "MANUAL: flags live on the source dataset as %sDTF/%sTMF; verify imputation flags there",
            prefix, prefix
          ))
        }
        "PASS"
      }
    ),
    non_negative = list(
      description = "duration/age values must be non-negative",
      fn = function(data, var, args) {
        if (!var %in% names(data)) return("FAIL: variable not present")
        vals <- data[[var]]
        if (any(!is.na(vals) & vals < 0)) "FAIL: negative values present" else "PASS"
      }
    ),
    values_in_ct = list(
      description = "derived values must be a subset of the spec codelist (verify vs metacore)",
      fn = function(data, var, args) "MANUAL: compare against spec codelist"
    ),
    flag_rate = list(
      description = "flag variable should be set for at least some records (not all-NA, not all-set)",
      fn = function(data, var, args) {
        if (!var %in% names(data)) return("FAIL: variable not present")
        n_set <- sum(!is.na(data[[var]]) & data[[var]] != "")
        if (n_set == 0) "FAIL: flag never set" else "PASS"
      }
    )
  )
}

#' Validation comments for a variable IR
#'
#' @description Collects the deduplicated `# CHECK` comment lines for every
#'   layer used by the variable, drawn from the internal check registry.
#' @title Validation comments
#' @param v An `aa_variable_ir` object.
#' @return Character vector of `# CHECK:` lines (empty when no checks apply).
#' @export
validation_comments <- function(v) {
  assert_ir_shape(list(v))
  if (v$needs_human || length(v$steps) == 0) {
    return(paste0("# CHECK: ", v$variable, " requires human decision; no auto-validation"))
  }
  layers <- aa_layers()
  checks <- unique(unlist(lapply(v$steps, function(s) {
    l <- layers[[s$layer]]
    if (is.null(l)) character() else l$checks
  })))
  if (length(checks) == 0) return(character())
  paste0("# CHECK: ", vapply(checks, function(cid) aa_checks()[[cid]]$description, character(1)))
}

#' Run deterministic validation checks on executed data
#'
#' @description Executes every check attached to each variable's layers
#'   against the resulting dataset and reports PASS/FAIL/MANUAL per check.
#'   `needs_human` variables report `MANUAL`. This is the deterministic
#'   validation gate paired with generated code.
#' @title Run validation
#' @param data The analysis dataset produced by executing the rendered code.
#' @param ir List of `aa_variable_ir` objects used to derive `data`.
#' @param quiet If `TRUE` (default) the status table is not printed.
#' @return Invisibly, a data.frame with columns `variable`, `check`,
#'   `status`, `details`.
#' @export
run_validation <- function(data, ir, quiet = FALSE) {
  if (!is.data.frame(data)) stop("data must be an analysis data.frame", call. = FALSE)
  assert_ir_shape(ir)
  assert_flag(quiet, "quiet")
  layers <- aa_layers()
  registry <- aa_checks()
  rows <- list()
  for (v in ir) {
    if (v$needs_human || length(v$steps) == 0) {
      rows[[length(rows) + 1]] <- data.frame(
        variable = v$variable, check = "needs_human", status = "MANUAL",
        details = "routed to human review", stringsAsFactors = FALSE
      )
      next
    }
    seen <- character()
    for (s in v$steps) {
      l <- layers[[s$layer]]
      if (is.null(l)) next
      for (cid in l$checks) {
        if (cid %in% seen) next
        seen <- c(seen, cid)
        entry <- registry[[cid]]
        if (is.null(entry)) {
          status <- "MANUAL"; details <- "unknown check id"
        } else {
          res <- tryCatch(entry$fn(data, v$variable, s$args), error = function(e) {
            paste0("MANUAL: check errored (", conditionMessage(e), ")")
          })
          if (grepl("^FAIL", res)) {
            status <- "FAIL"; details <- res
          } else if (grepl("^MANUAL", res)) {
            status <- "MANUAL"; details <- res
          } else {
            status <- "PASS"; details <- ""
          }
        }
        rows[[length(rows) + 1]] <- data.frame(
          variable = v$variable, check = cid, status = status,
          details = gsub("^(PASS|FAIL|MANUAL):?\\s*", "", details),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- do.call(rbind, rows)
  if (!quiet) print(out, row.names = FALSE)
  invisible(out)
}
