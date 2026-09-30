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
#' @param log_file Audit log destination. Logging is ON by default and writes
#'   one hash-chained record per variable (see [log_run()]) plus exactly one
#'   `run_manifest` record for the call, carrying that call's `run_id` so the
#'   manifest joins the executions it describes; the default destination comes
#'   from `getOption("admiralagent.log_file")`, then `ADMIRALAGENT_LOG_FILE`,
#'   then a session file in [tempdir()]. Pass `NA` to switch logging off for
#'   this call - that suppresses the manifest too.
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
execute_ir <- function(ir, sources = list(), variables = NULL, quiet = TRUE,
                       log_file = aa_log_file()) {
  assert_valid_ir(ir)
  if (!is.list(sources) || is.null(names(sources)) || anyDuplicated(names(sources)) ||
      !valid_name(names(sources), TRUE)) stop("sources must be a uniquely named list of dataset objects including base", call. = FALSE)
  assert_flag(quiet, "quiet")
  if (!is.null(variables) && (!is.character(variables) || anyNA(variables) ||
      any(!variables %in% vapply(ir, function(v) v$variable, character(1))))) stop("variables must name variables present in ir", call. = FALSE)
  if (length(unique(vapply(ir, function(v) v$dataset, character(1)))) != 1L) stop("execute_ir requires one target dataset", call. = FALSE)
  target <- ir[[1]]$dataset
  base_name <- if (!is.null(sources$base)) "base" else tolower(target)
  base <- sources[[base_name]]
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
  env <- seed_exec_env(sources, stats::setNames(list(base_name), target))

  if (!is.null(variables)) {
    ir <- ir[vapply(ir, function(v) v$variable %in% variables, logical(1))]
  }
  # same deterministic order as render_program(): dependency-driven, ties by rank
  log_file <- aa_log_file(log_file)
  run_id <- basename(tempfile("run"))
  loop <- run_ir_loop(ir, env, quiet, log_file, run_id)
  log_run_manifest_auto(run_id, ir, sources, log_file)

  out <- list(
    adsl = env[[target]],
    status = loop$status,
    env = env
  )
  if (!quiet) print(out$status, row.names = FALSE)
  out
}

#' Execute a multi-deliverable IR in one shared environment
#'
#' @description
#' Study-level counterpart of [execute_ir()]: builds every deliverable of an IR
#' in a single execution environment, so a downstream deliverable reads its
#' upstream deliverable as an ordinary in-memory object (an ADTTE `merge_var`
#' with `dataset_add = "ADSL"` simply finds `ADSL`).
#'
#' The whole IR goes through the one existing [order_variables()] call rather
#' than being grouped per deliverable. The dependency keys are already
#' dataset-qualified (`dataset::kind::input`), so interleaving variables of
#' different deliverables is semantically correct and keeps the single
#' deterministic order; grouping by deliverable would instead impose an
#' arbitrary outer order on variables the graph leaves free.
#'
#' One `failed_outputs` accumulator is threaded through every variable of every
#' deliverable, so an ADSL derivation that errors blocks the ADTTE variables
#' consuming its products with the stale-input note instead of letting them read
#' a half-written column.
#'
#' Deliverable membership travels as an ARGUMENT, never in the IR: `aa_variable_ir`
#' has a fixed seven-field schema that [canonical_ir()] hashes, and adding a
#' field there would make two different IRs hash identically.
#'
#' @param ir Non-empty list of `aa_variable_ir` objects, possibly spanning
#'   several datasets.
#' @param sources Named list of source data objects, including one base per
#'   deliverable.
#' @param deliverables Named list (or named character vector) mapping each
#'   deliverable dataset name to the `sources` element holding its base, e.g.
#'   `list(ADSL = "dm", ADTTE = "adtte_base")`. Defaults to the lower-cased
#'   dataset name for every dataset in `ir`, mirroring [execute_ir()]'s
#'   `sources$adsl` convention.
#' @param variables Optional character vector restricting execution to these
#'   spec variables (default all).
#' @param quiet If `TRUE` (default), warnings from the evaluated blocks are
#'   suppressed and nothing is printed.
#' @param log_file Audit log destination. One `run_id` is minted for the whole
#'   study call and threaded through every per-variable record and through the
#'   single `run_manifest` record the call emits, so a study's records group
#'   together. A study is ONE run, so it gets ONE manifest, not one per
#'   deliverable. Pass `NA` to switch logging off - that suppresses the
#'   manifest too.
#'
#' @return A list with elements:
#' - `datasets`: named list of the built deliverables, in dependency
#'   ([deliverable_order()]) order;
#' - `status`: data.frame with columns `dataset`, `variable`, `status`, `note`;
#' - `env`: the shared execution environment;
#' - `adsl`: back-compat alias for the first deliverable, so a single-deliverable
#'   `execute_study()` result reads like an [execute_ir()] result.
#' @noRd
execute_study <- function(ir, sources = list(), deliverables = NULL, variables = NULL,
                          quiet = TRUE, log_file = aa_log_file()) {
  assert_valid_ir(ir)
  if (!is.list(sources) || is.null(names(sources)) || anyDuplicated(names(sources)) ||
      !valid_name(names(sources), TRUE)) stop("sources must be a uniquely named list of dataset objects including one base per deliverable", call. = FALSE)
  assert_flag(quiet, "quiet")
  if (!is.null(variables) && (!is.character(variables) || anyNA(variables) ||
      any(!variables %in% vapply(ir, function(v) v$variable, character(1))))) stop("variables must name variables present in ir", call. = FALSE)

  targets <- unique(vapply(ir, function(v) v$dataset, character(1)))
  deliverables <- resolve_deliverables(deliverables, targets)
  # Relaxed form of execute_ir()'s single-target guard: any number of target
  # datasets, as long as every one of them has a declared base.
  undeclared <- setdiff(targets, names(deliverables))
  if (length(undeclared)) {
    stop(
      "every IR dataset must be declared in deliverables; missing base for: ",
      paste(undeclared, collapse = ", "), call. = FALSE
    )
  }
  for (d in names(deliverables)) {
    nm <- deliverables[[d]]
    if (!nm %in% names(sources)) {
      stop("deliverable '", d, "' declares base '", nm, "', which is not an element of sources", call. = FALSE)
    }
    if (!is.data.frame(sources[[nm]])) stop("deliverable base '", nm, "' must be a data.frame", call. = FALSE)
  }
  # Relaxed form of execute_ir()'s shadowing guard: a source may carry a
  # deliverable's name only when it is that deliverable's declared base;
  # anything else would be silently overwritten by the seeding below.
  shadows <- function(nm) nm %in% names(deliverables) && !identical(deliverables[[nm]], nm)
  bad <- names(sources)[vapply(names(sources), shadows, logical(1))]
  if (length(bad) || any(names(sources) %in% c("exprs", "params"))) {
    stop("sources names must not shadow an undeclared deliverable or the execution helpers", call. = FALSE)
  }
  if (any(!vapply(sources[setdiff(names(sources), "mc")], is.data.frame, logical(1)))) stop("sources datasets must be data.frames", call. = FALSE)

  env <- seed_exec_env(sources, deliverables)
  order <- unique(c(intersect(as.character(deliverable_order(ir)), names(deliverables)),
                    names(deliverables)))
  if (!is.null(variables)) {
    ir <- ir[vapply(ir, function(v) v$variable %in% variables, logical(1))]
  }
  # ONE run id for the whole study, so every record of this call groups together
  log_file <- aa_log_file(log_file)
  run_id <- basename(tempfile("run"))
  loop <- run_ir_loop(ir, env, quiet, log_file, run_id)
  # ONE manifest for the whole study, not one per deliverable: the study call is
  # the run, and `run_id` was minted once above.
  log_run_manifest_auto(run_id, ir, sources, log_file)

  datasets <- stats::setNames(lapply(order, function(d) env[[d]]), order)
  out <- list(
    datasets = datasets,
    status = data.frame(
      dataset = loop$datasets, variable = loop$status$variable,
      status = loop$status$status, note = loop$status$note,
      stringsAsFactors = FALSE
    ),
    env = env,
    adsl = if (length(datasets)) datasets[[1]] else NULL
  )
  if (!quiet) print(out$status, row.names = FALSE)
  out
}

# Deliverable membership is an argument, so the default has to be derivable
# from the IR alone: every dataset takes execute_ir()'s lower-cased convention.
resolve_deliverables <- function(deliverables, targets) {
  if (is.null(deliverables) || !length(deliverables)) {
    return(stats::setNames(as.list(tolower(targets)), targets))
  }
  if (is.character(deliverables)) deliverables <- as.list(deliverables)
  nms <- names(deliverables)
  ok <- is.list(deliverables) && !is.null(nms) && !anyDuplicated(nms) && valid_name(nms, TRUE) &&
    all(vapply(deliverables, function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x), logical(1)))
  if (!ok) stop("deliverables must be a uniquely named list mapping each dataset to the name of its base in sources", call. = FALSE)
  deliverables
}

# The one place an execution environment is built. `deliverables` maps a
# deliverable dataset name to the `sources` element holding its base; every
# other source is assigned under its own name, exactly as execute_ir() has
# always done (its `base` element is addressed by the map, never by name).
seed_exec_env <- function(sources, deliverables) {
  env <- new.env(parent = baseenv())
  for (nm in names(sources)) {
    if (!identical(nm, "base")) assign(nm, sources[[nm]], envir = env)
  }
  for (target in names(deliverables)) env[[target]] <- sources[[deliverables[[target]]]]
  if (requireNamespace("rlang", quietly = TRUE)) env$exprs <- rlang::exprs
  if (requireNamespace("admiral", quietly = TRUE)) env$params <- admiral::params
  env
}

# The shared per-variable loop. Deterministic order and the single
# `failed_outputs` accumulator are the same whether the IR covers one
# deliverable or a whole study: the keys are dataset-qualified, so nothing here
# needs to know how many datasets it is looking at.
run_ir_loop <- function(ir, env, quiet, log_file, run_id) {
  ordered <- order_variables(ir)
  rows <- list()
  failed_outputs <- character()
  for (v in ordered) {
    res <- execute_ir_one(v, env, failed_outputs, quiet, log_file, run_id)
    failed_outputs <- res$failed_outputs
    rows[[length(rows) + 1]] <- res$rows
  }
  list(
    status = if (length(rows)) do.call(rbind, rows) else data.frame(variable = character(), status = character(), note = character()),
    datasets = vapply(ordered, function(v) v$dataset, character(1))
  )
}

#' Execute a single variable IR against a prepared environment
#'
#' @description
#' The per-variable body of [execute_ir()]. The caller owns `env`: it must
#' already hold the target dataset object, every source object and the
#' `exprs`/`params` helpers, exactly as [execute_ir()] seeds it. This function
#' neither creates nor validates that environment.
#'
#' Transactionality is unchanged from the loop it was extracted from: the
#' steps run against a copy of `env`, which is committed back with
#' `list2env()` only when every step of the variable succeeded. On failure
#' `env` is left exactly as it was found and the variable's product keys join
#' `failed_outputs`, so later variables consuming them report the stale-input
#' error instead of reading a half-written dataset.
#'
#' @param ir A single `aa_variable_ir` object (one element of an IR list), not
#'   a list of them.
#' @param env Execution environment seeded by [execute_ir()]; mutated in place
#'   on success, untouched on failure or review.
#' @param failed_outputs Character vector of product keys already marked
#'   failed in this run; a variable consuming one of them errors without
#'   evaluating anything.
#' @param quiet If `TRUE` (default), warnings from the evaluated blocks are
#'   suppressed.
#' @param log_file Audit log destination, resolved by [aa_log_file()] so
#'   logging is on by default; `NULL`/`NA` switches it off. Exactly one
#'   `execute_variable` record is written per call.
#' @param run_id Optional run identifier recorded with the log entry so the
#'   per-variable records of one [execute_ir()] call group together.
#' @return List with `rows` (a one-row status data.frame with columns
#'   `variable`, `status`, `note`) and `failed_outputs` (the input vector,
#'   grown by this variable's product keys when it errored).
#' @noRd
execute_ir_one <- function(ir, env, failed_outputs = character(), quiet = TRUE,
                           log_file = aa_log_file(), run_id = NULL) {
  v <- ir # `ir` elsewhere in this package is a list of variables; `v` is one
  if (isTRUE(v$needs_human) || length(v$steps) == 0) {
    rows <- data.frame(
      variable = v$variable, status = "REVIEW",
      note = "needs human decision", stringsAsFactors = FALSE
    )
    log_execution(v, rows, log_file, run_id)
    return(list(rows = rows, failed_outputs = failed_outputs))
  }
  # Transaction scratch space. Only the objects this variable's steps read or
  # write are copied; everything else in the (study-sized) environment stays
  # reachable through the parent link, which is what turns the former
  # copy-the-whole-env-per-variable pass into a per-variable constant.
  touched <- variable_touched_objects(v)
  work <- new.env(parent = env)
  for (nm in touched) {
    if (exists(nm, envir = env, inherits = FALSE)) {
      assign(nm, get(nm, envir = env, inherits = FALSE), envir = work)
    }
  }
  # Guard each step immediately before execution, preserving intermediate inputs.
  failing_step <- NA_integer_
  status_note <- tryCatch({
    if (length(intersect(variable_input_keys(v), failed_outputs))) exec_stop("upstream derivation failed; stale inputs are not used")
    for (i in seq_along(v$steps)) {
      failing_step <- i
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
  }, error = function(e) redact_exec_error(e, v, failing_step))
  if (!nzchar(status_note)) {
    # `inherits = FALSE` keeps the commit narrow in both directions: it never
    # re-commits a parent object that the steps only read, and an object a step
    # removed from `work` is simply not written back - the caller's copy stays,
    # which is exactly the no-delete semantics list2env() had here before.
    for (nm in touched) {
      if (exists(nm, envir = work, inherits = FALSE)) {
        assign(nm, get(nm, envir = work, inherits = FALSE), envir = env)
      }
    }
  } else {
    failed_outputs <- union(failed_outputs, variable_product_keys(v))
  }
  rows <- data.frame(
    variable = v$variable,
    status = if (nzchar(status_note)) "ERROR" else "EXECUTED",
    note = status_note,
    stringsAsFactors = FALSE
  )
  log_execution(v, rows, log_file, run_id)
  list(rows = rows, failed_outputs = failed_outputs)
}

# One audit record per variable. Only schema-level facts travel: dataset,
# variable, the layer chain and the already-redacted status note.
log_execution <- function(v, rows, log_file, run_id) {
  if (is.null(log_file)) return(invisible(FALSE))
  log_run(
    "execute_variable",
    list(
      run_id = run_id %||% NA_character_,
      dataset = v$dataset,
      variable = rows$variable,
      status = rows$status,
      layers = as.character(vapply(v$steps, function(s) s$layer, character(1))),
      note = rows$note
    ),
    file = log_file
  )
  invisible(TRUE)
}

# ONE run manifest per run, emitted IN-LINE by execute_ir()/execute_study()
# rather than left to the caller to remember.
#
# WHY IN-LINE AT ALL: `run_id` is minted INSIDE those functions, so the only
# place that can record a manifest which JOINS this run's `execute_variable`
# records is inside them. The manifest used to be a three-step operator ritual
# (execute -> log_run_ids() -> log_run_manifest()); a replay manifest someone
# must remember to write is, for audit purposes, closer to absent than present -
# the same failure shape as a control that is complete but inert by default.
# Emitting here is what makes "same IR, different machine, different result, and
# nothing records it" stop being true without anyone opting in.
#
# WHY AFTER run_ir_loop(): it then describes a run that actually happened, and
# it lands AFTER the execution records, which keeps positional readers of the
# log ("the next record is this run's first execution") working. Once per call,
# never once per variable - N manifests would be N contradictory records of one
# run's single set of conditions.
#
# WHAT IT DOES NOT TOUCH: nothing is added to `aa_variable_ir` (`canonical_ir()`
# whitelists exactly seven fields, so a new field would hash identically - a
# silent collision), nothing is added to the audit record schema, and no second
# log file is opened. This is one more `log_run()` EVENT on the same chain.
#
# NO PATIENT DATA: `sources` reaches `log_run_manifest()`, which records digests,
# shapes and column names only - never a cell value.
log_run_manifest_auto <- function(run_id, ir, sources, log_file) {
  # The existing off switch is the only off switch: `log_file = NA` has already
  # resolved to NULL here, logging is off, and no manifest is written either.
  if (is.null(log_file)) return(invisible(FALSE))
  log_run_manifest(
    run_id = run_id,
    # `ir` is the post-`variables` subset, i.e. what this run actually covered.
    ir = if (length(ir)) ir else NULL,
    sources = sources,
    file = log_file
  )
  invisible(TRUE)
}

# Errors admiralagent itself raises inside the execution block are authored
# here and known to be free of patient data, so they survive redaction intact.
exec_stop <- function(...) {
  stop(structure(
    class = c("aa_exec_error", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

# admiral/dplyr assertion errors routinely echo the OFFENDING VALUES, and
# AGENTS.md forbids patient data in logs and sidecars. Anything admiralagent
# did not author is therefore reduced to what debugging actually needs - the
# condition class and the failing call - and the verbatim message is dropped.
# Detail is opt-in and out-of-band via `admiralagent.error_detail`.
redact_exec_error <- function(e, v, step_index) {
  if (inherits(e, "aa_exec_error")) return(conditionMessage(e))
  stash_error_detail(v, e)
  paste0(
    "[", class(e)[[1]], "] ", failing_call_label(v, step_index),
    ": message redacted (may contain data values); enable ",
    "options(admiralagent.error_detail = TRUE) and read aa_last_error_detail()"
  )
}

failing_call_label <- function(v, step_index) {
  if (is.na(step_index) || step_index < 1L || step_index > length(v$steps)) {
    return("preflight")
  }
  s <- v$steps[[step_index]]
  fn <- tryCatch(aa_layers()[[s$layer]]$fn, error = function(e) NULL)
  paste0(
    fn %||% s$layer, "() [step ", step_index, "/", length(v$steps),
    ", layer ", s$layer, "]"
  )
}

# In-memory only, written solely when the operator opted in; never serialized.
error_detail_store <- new.env(parent = emptyenv())

stash_error_detail <- function(v, e) {
  if (!isTRUE(getOption("admiralagent.error_detail", FALSE))) {
    rm(list = ls(error_detail_store, all.names = TRUE), envir = error_detail_store)
    return(invisible(FALSE))
  }
  error_detail_store$last <- list(
    dataset = v$dataset, variable = v$variable,
    class = class(e), message = conditionMessage(e)
  )
  invisible(TRUE)
}

aa_last_error_detail <- function() error_detail_store$last

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

# The *DTF/*TMF naming rule lives in the layer registry (`products()`, see
# R/layers.R), not here. This function used to carry a second, hand-written
# copy of it; the two had to be kept in step by hand, and a renderer for
# another language that changed one would have silently corrupted the
# idempotency guard fed by the other. It now reads the same hook
# `step_products()` (R/dependency.R) reads, so the mirror cannot drift.
step_output_columns <- function(s) {
  args <- s$args
  # an impute_dtc whose target IS its source overwrites in place
  if (s$layer == "impute_dtc" && identical(args$target, args$dtc)) return(character())
  # assign re-derives via mutate, which overwrites in place; dropping the
  # target first would destroy its own input when from == target (direct
  # copy of a base column such as STUDYID = STUDYID)
  if (s$layer %in% c("assign", "compute_var", "date_shift", "categorize")) return(character())
  layer <- aa_layers()[[s$layer]]
  if (is.null(layer)) return(character())
  cols <- layer$products(args)$columns
  if (is.null(cols) || !is.character(cols)) return(character())
  cols[!is.na(cols) & nzchar(cols)]
}

step_output_paramcds <- function(s) {
  if (s$layer %in% c("compute_param", "summary_record")) s$args$paramcd else character()
}

# Every environment object a variable's steps can read or write. The read set
# is exactly what check_step_inputs() enforces - step_refs() names the dataset
# each reference is resolved against - and the write set is the single object
# each rendered step lands on (`on`, defaulting to the variable's dataset);
# every layer template emits `<obj> <- <obj> |> ...` and nothing else.
# Objects reached by name from inside a template but never declared as step
# arguments (the `mc` metacore, `exprs`, `params`) are read-only and stay
# reachable through the work environment's parent, so they need no copy.
variable_touched_objects <- function(v) {
  names <- v$dataset
  for (s in v$steps) {
    names <- c(
      names, s$args$on %||% v$dataset, s$args$dataset_add, s$args$dataset_lookup,
      step_refs(v, s)$dataset
    )
  }
  names <- names[!is.na(names) & nzchar(names)]
  unique(names)
}

check_step_inputs <- function(v, s, env) {
  refs <- step_refs(v, s)
  for (i in seq_len(nrow(refs))) {
    ds <- refs$dataset[i]
    if (!exists(ds, env, inherits = FALSE) || !is.data.frame(get(ds, env, inherits = FALSE))) exec_stop("source dataset '", ds, "' must be supplied as a data.frame")
    if (refs$kind[i] == "column" && !refs$input[i] %in% names(get(ds, env, inherits = FALSE))) exec_stop("column '", refs$input[i], "' is missing from source dataset '", ds, "'")
  }
}
