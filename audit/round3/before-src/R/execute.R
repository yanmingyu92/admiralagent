#' Execute a Layer IR against source datasets
#'
#' @description
#' Runs each variable's rendered code block ([render_variable()]) inside a
#' fresh environment with baseenv() as parent and reports a per-variable status. This is the
#' programmatic replacement for the demo glue loops: idempotent, re-runnable,
#' and safe to call on an IR that mixes executable variables with
#' `needs_human` review variables.
#'
#' Contract:
#' - `sources` must contain the base for the target dataset under the name
#'   `base` (preferred) or under the target dataset name lower-cased (e.g.
#'   `adsl` for target `ADSL`). It is the one-row-per-subject starting point
#'   and is assigned into the execution environment as the target dataset
#'   object.
#' - Every other element of `sources` is assigned into the environment under
#'   its list name, e.g. `list(base = dm, ex = ex, vs = vs_bds)` creates
#'   `ADSL <- base`, `ex`, `vs_bds`. Step args like `on = "ex"` or
#'   `dataset_add = "ex"` must match those names. A `codelist_var` step needs
#'   a metacore object named `mc`; pass it as `sources$mc` (typically a
#'   [metacore::select_dataset()] subset of [mock_metacore()] output).
#' - Each variable executes transactionally: errors roll back all its changes
#'   to target and source datasets, and dependent variables report ERROR.
#' - Before each step's code runs, an idempotency guard removes columns
#'   (and computed PARAMCD rows) that this variable's steps would create,
#'   from the objects those steps land on - including imputation temp
#'   columns and their flag columns on foreign datasets. Calling
#'   `execute_ir()` twice therefore yields identical output, and a partially
#'   failed run can be retried without "already exists" warnings or stale
#'   values.
#'
#' The `admiralagent` layer templates render bare `exprs()`/`params()`
#' helpers; if `rlang`/`admiral` are installed these are pre-assigned into
#' the environment, otherwise the affected variables report `ERROR`.
#'
#' @param ir Non-empty list of `aa_variable_ir` objects (as produced by
#'   [classify_variables()]).
#' @param sources Named list of source data objects; must contain `base` (or
#'   the lower-cased target dataset name). See the Description for the full
#'   contract.
#' @param variables Optional character vector restricting execution to these
#'   spec variables (default all). Only selected variables run; required prior
#'   results must be supplied in sources. Unknown names are rejected.
#' @param quiet If `TRUE` (default), warnings from the evaluated blocks are
#'   suppressed and nothing is printed; if `FALSE`, warnings pass through and
#'   the status table is printed.
#'
#' @return A list with elements:
#' - `adsl`: the target dataset after execution (named after the IR's first
#'   dataset, so `ADSL` for an ADSL IR);
#' - `status`: data.frame with columns `variable`, `status` (one of
#'   `EXECUTED`, `ERROR`, `REVIEW`), `note` (error message when `ERROR`,
#'   otherwise empty or the review reason);
#' - `env`: the execution environment (useful for inspecting mutated source
#'   objects such as imputation temps on `ex`).
#'
#' @examples
#' \dontrun{
#' spec <- mock_spec_adsl()
#' ir <- classify_variables(spec, "ADSL", backend = "rules")
#' res <- execute_ir(ir, sources = list(base = dm, ex = ex, vs = vs_bds))
#' res$status
#' }
#' @export
execute_ir <- function(ir, sources = list(), variables = NULL, quiet = TRUE) {
  assert_valid_ir(ir)
  if (!is.list(sources) || is.null(names(sources)) || anyDuplicated(names(sources)) ||
      !valid_name(names(sources), TRUE)) stop("sources must be a uniquely named list of dataset objects including base", call. = FALSE)
  if (!is.logical(quiet) || length(quiet) != 1L || is.na(quiet)) stop("quiet must be TRUE or FALSE", call. = FALSE)
  if (!is.null(variables) && (!is.character(variables) || anyNA(variables) ||
      any(!variables %in% vapply(ir, function(v) v$variable, character(1))))) stop("variables must name variables present in ir", call. = FALSE)
  if (length(unique(vapply(ir, function(v) v$dataset, character(1)))) != 1L) stop("execute_ir requires one target dataset", call. = FALSE)
  target <- ir[[1]]$dataset
  base <- sources$base %||% sources[[tolower(target)]]
  if (is.null(base)) {
    stop(
      "sources must contain the target dataset base: pass sources$base ",
      "(or sources$", tolower(target), ") with the one-row-per-subject starting dataset",
      call. = FALSE
    )
  }

  if (!is.data.frame(base)) stop("sources base must be a data.frame", call. = FALSE)
  if (any(names(sources) %in% c(target, "exprs", "params"))) stop("sources names must not shadow the target or execution helpers", call. = FALSE)
  if (any(!vapply(sources[setdiff(names(sources), "mc")], is.data.frame, logical(1)))) stop("sources datasets must be data.frames", call. = FALSE)
  env <- new.env(parent = baseenv())
  env[[target]] <- base
  for (nm in names(sources)) {
    if (!identical(nm, "base")) assign(nm, sources[[nm]], envir = env)
  }
  if (requireNamespace("rlang", quietly = TRUE)) env$exprs <- rlang::exprs
  if (requireNamespace("admiral", quietly = TRUE)) env$params <- admiral::params

  if (!is.null(variables)) {
    ir <- ir[vapply(ir, function(v) v$variable %in% variables, logical(1))]
  }
  # same deterministic order as render_program(): dependency-driven, ties by rank
  rows <- list()
  failed_outputs <- character()
  for (v in order_variables(ir)) {
    if (isTRUE(v$needs_human) || length(v$steps) == 0) {
      rows[[length(rows) + 1]] <- data.frame(
        variable = v$variable, status = "REVIEW",
        note = "needs human decision", stringsAsFactors = FALSE
      )
      next
    }
    work <- list2env(as.list(env, all.names = TRUE), parent = baseenv())
    # Guard each step immediately before execution, preserving intermediate inputs.
    status_note <- tryCatch({
      if (length(intersect(variable_input_keys(v), failed_outputs))) stop("upstream derivation failed; stale inputs are not used", call. = FALSE)
      for (i in seq_along(v$steps)) {
        one <- v
        one$steps <- v$steps[i]
        idempotency_guard(one, work)
        check_step_inputs(v, v$steps[[i]], work)
        block <- render_step(v$steps[[i]], v, i)
      if (quiet) {
        suppressWarnings(eval(parse(text = block, encoding = "UTF-8"), envir = work))
      } else {
        eval(parse(text = block, encoding = "UTF-8"), envir = work)
      }
      }
      ""
    }, error = function(e) conditionMessage(e))
    if (!nzchar(status_note)) {
      list2env(as.list(work, all.names = TRUE), envir = env)
    } else {
      failed_outputs <- union(failed_outputs, variable_product_keys(v))
    }
    rows[[length(rows) + 1]] <- data.frame(
      variable = v$variable,
      status = if (nzchar(status_note)) "ERROR" else "EXECUTED",
      note = status_note,
      stringsAsFactors = FALSE
    )
  }

  out <- list(
    adsl = env[[target]],
    status = if (length(rows)) do.call(rbind, rows) else data.frame(variable = character(), status = character(), note = character()),
    env = env
  )
  if (!quiet) print(out$status, row.names = FALSE)
  out
}

# Remove outputs a variable's steps would create from the objects they land
# on: target columns (plus imputation flag columns) everywhere, and computed
# PARAMCD rows on BDS-style objects. Keeps re-execution clean.
idempotency_guard <- function(v, env) {
  for (s in v$steps) {
    obj_name <- s$args$on %||% v$dataset
    if (!exists(obj_name, envir = env, inherits = FALSE)) next
    obj <- get(obj_name, envir = env, inherits = FALSE)
    if (!is.data.frame(obj)) next

    cols <- step_output_columns(s)
    if (length(cols) > 0) obj <- obj[, setdiff(names(obj), cols), drop = FALSE]

    for (pc in step_output_paramcds(s)) {
      if ("PARAMCD" %in% names(obj)) {
        obj <- obj[is.na(obj$PARAMCD) | obj$PARAMCD != pc, , drop = FALSE]
      }
    }
    assign(obj_name, obj, envir = env)
  }
}

step_output_columns <- function(s) {
  args <- s$args
  if (s$layer == "impute_dtc") {
    tgt <- args$target
    if (identical(tgt, args$dtc)) return(character())
    prefix <- sub("(DTM|DT)$", "", tgt)
    return(unique(c(tgt, paste0(prefix, c("DTF", "TMF")))))
  }
  # assign re-derives via mutate, which overwrites in place; dropping the
  # target first would destroy its own input when from == target (direct
  # copy of a base column such as STUDYID = STUDYID)
  if (s$layer %in% c("assign", "compute_var", "date_shift", "categorize")) return(character())
  # any other layer that declares a target arg creates/overwrites that
  # column on the object it runs on (merge_var, duration, dtm_to_dt,
  # date_shift, extreme_flag, obs_number, codelist_var, categorize, ...)
  tgt <- args$target
  if (is.character(tgt) && length(tgt) == 1L && !is.na(tgt) && nzchar(tgt)) tgt else character()
}

step_output_paramcds <- function(s) {
  if (s$layer %in% c("compute_param", "summary_record")) s$args$paramcd else character()
}

check_step_inputs <- function(v, s, env) {
  refs <- step_refs(v, s)
  for (i in seq_len(nrow(refs))) {
    ds <- refs$dataset[i]
    if (!exists(ds, env, inherits = FALSE) || !is.data.frame(get(ds, env, inherits = FALSE))) stop("source dataset '", ds, "' must be supplied as a data.frame", call. = FALSE)
    if (refs$kind[i] == "column" && !refs$input[i] %in% names(get(ds, env, inherits = FALSE))) stop("column '", refs$input[i], "' is missing from source dataset '", ds, "'", call. = FALSE)
  }
}
