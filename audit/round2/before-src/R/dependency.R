#' Order IR variables by data dependency
#'
#' @description
#' Reorders an IR list so that a variable whose steps consume a target produced
#' by another variable's step comes after the producer. Consumption references
#' considered:
#' \itemize{
#'   \item `duration` `start`/`end`, resolved against the dataset the step runs on
#'   \item `assign` `from` (same-dataset references only)
#'   \item `merge_var` `source`, resolved against `dataset_add`, so foreign-dataset
#'     targets produced via `on` are ordered before the variables that merge them in
#' }
#' Producers are step targets (`target`, or `paramcd` for parameter-adding layers)
#' on the dataset the step runs on (`on`, defaulting to the variable's dataset).
#'
#' The order is stable and deterministic: variables that are simultaneously
#' ready (no pending producers) are emitted by layer rank (`step_rank()`), ties
#' broken by original spec position, so the result never depends on hash or map
#' iteration order. Variables needing human review (or without steps) are kept
#' last, as before. References listed in `known_columns` are treated as
#' pre-existing columns and do not create ordering edges.
#'
#' Cycle safety: if the dependency graph contains a cycle, no error is raised.
#' The involved variables fall back to the rank-based order (rank, then
#' original position) and a valid permutation of the input is always returned;
#' flagging cyclic or otherwise unresolved specs remains the responsibility of
#' `validate_ir()` and `ir_dependency_report()`.
#'
#' @title Dependency-driven variable ordering
#' @param ir List of `aa_variable_ir` objects, as built by `new_variable_ir()`.
#' @param known_columns Character vector of column names assumed to pre-exist in
#'   the source data; consuming them never creates an ordering constraint.
#' @return The same list of variable IRs with only the order changed (length and
#'   elements are preserved).
#' @export
order_variables <- function(ir, known_columns = character()) {
  assert_ir_shape(ir, allow_empty = TRUE)
  n <- length(ir)
  if (n <= 1L) return(ir)

  is_stub <- vapply(ir, function(v) isTRUE(v$needs_human) || length(v$steps) == 0L, logical(1))
  ranks <- vapply(ir, step_rank, numeric(1))
  keys <- ranks * (n + 1) + seq_len(n)

  producers <- list()
  for (i in which(!is_stub)) {
    v <- ir[[i]]
    for (s in v$steps) {
      ds <- s$args$on %||% v$dataset
      tg <- s$args$target %||% s$args$paramcd
      if (!is.null(tg) && length(tg) == 1L && !is.na(tg) && nzchar(tg)) {
        k <- paste(ds, tg, sep = "\r")
        producers[[k]] <- unique(c(producers[[k]], i))
      }
    }
  }

  edge_keys <- character()
  edge_from <- integer()
  edge_to <- integer()
  add_edge <- function(from, to) {
    if (identical(from, to)) return(invisible(NULL))
    ek <- paste(from, to, sep = "\r")
    if (ek %in% edge_keys) return(invisible(NULL))
    edge_keys <<- c(edge_keys, ek)
    edge_from <<- c(edge_from, from)
    edge_to <<- c(edge_to, to)
    invisible(NULL)
  }
  for (i in which(!is_stub)) {
    v <- ir[[i]]
    for (s in v$steps) {
      ds <- s$args$on %||% v$dataset
      consumed <- switch(s$layer,
        duration = list(c(ds, s$args$start), c(ds, s$args$end)),
        assign = if (identical(ds, v$dataset)) list(c(ds, s$args$from)) else list(),
        merge_var = list(c(s$args$dataset_add, s$args$source)),
        list()
      )
      for (ref in consumed) {
        if (length(ref) != 2L || any(is.na(ref)) || !all(nzchar(ref))) next
        if (ref[[2]] %in% known_columns) next
        for (p in producers[[paste(ref[[1]], ref[[2]], sep = "\r")]] %||% integer()) {
          add_edge(p, i)
        }
      }
    }
  }

  succ <- vector("list", n)
  indeg <- integer(n)
  for (e in seq_along(edge_from)) {
    succ[[edge_from[[e]]]] <- c(succ[[edge_from[[e]]]], edge_to[[e]])
    indeg[[edge_to[[e]]]] <- indeg[[edge_to[[e]]]] + 1L
  }

  placed <- logical(n)
  work_indeg <- indeg
  result <- integer(n)
  for (pos in seq_len(n)) {
    ready <- which(!placed & work_indeg == 0L)
    pick <- if (length(ready) > 0L) {
      ready[[which.min(keys[ready])]]
    } else {
      stalled <- which(!placed)
      stalled[[which.min(keys[stalled])]]
    }
    placed[[pick]] <- TRUE
    result[[pos]] <- pick
    for (b in succ[[pick]]) work_indeg[[b]] <- work_indeg[[b]] - 1L
  }
  ir[result]
}

#' Report undefined step inputs in an IR
#'
#' @description Audits every step's consumed references (duration endpoints,
#'   assign sources, compute_param/summary_record PARAMCD/AVAL expectations)
#'   against the columns defined by the spec, by other steps, or whitelisted
#'   via `known_columns`, and lists everything unresolved.
#' @title IR dependency report
#' @param ir List of `aa_variable_ir` objects.
#' @param known_columns Character vector of column names assumed to pre-exist
#'   in the source data.
#' @return A data.frame with columns `variable`, `input`, `dataset`, `issue`
#'   (zero rows when every input resolves).
#' @export
ir_dependency_report <- function(ir, known_columns = character()) {
  assert_ir_shape(ir, allow_empty = TRUE)
  spec_targets <- unique(vapply(ir, function(v) v$variable, character(1)))
  step_targets <- list()
  collect_target <- function(v, s) {
    ds <- s$args$on %||% v$dataset
    tg <- s$args$target %||% s$args$paramcd
    if (!is.null(tg) && length(tg) == 1 && nzchar(tg)) {
      step_targets[[ds]] <<- c(step_targets[[ds]], tg)
    }
  }
  for (v in ir) {
    if (isTRUE(v$needs_human) || length(v$steps) == 0) next
    for (s in v$steps) collect_target(v, s)
  }

  rows <- NULL
  for (v in ir) {
    if (isTRUE(v$needs_human) || length(v$steps) == 0) next
    for (s in v$steps) {
      ds <- s$args$on %||% v$dataset
      avail <- if (identical(ds, v$dataset)) {
        c(spec_targets, step_targets[[ds]], known_columns)
      } else {
        c(step_targets[[ds]], known_columns)
      }
      refs <- switch(s$layer,
        duration = c(s$args$start, s$args$end),
        assign = s$args$from,
        compute_param = , summary_record = {
          if (is.null(s$args$on)) c("PARAMCD", "AVAL") else NULL
        },
        NULL
      )
      for (r in refs) {
        if (!is.null(r) && is.character(r) && nzchar(r) && !r %in% avail) {
          rows <- rbind(rows, data.frame(
            variable = v$variable,
            input = r,
            dataset = ds,
            issue = "not defined by spec, earlier steps, or known_columns; add upstream source/derivation or whitelist it",
            stringsAsFactors = FALSE
          ))
        }
      }
    }
  }
  if (is.null(rows)) {
    rows <- data.frame(variable = character(), input = character(),
                       dataset = character(), issue = character(),
                       stringsAsFactors = FALSE)
  }
  rows[!duplicated(paste(rows$variable, rows$input)), , drop = FALSE]
}
