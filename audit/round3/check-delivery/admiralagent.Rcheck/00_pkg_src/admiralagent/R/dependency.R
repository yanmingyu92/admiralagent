#' Order IR variables by data dependency
#'
#' @description
#' Reorders an IR list so that a variable whose steps consume a target produced
#' by another variable's step comes after the producer. Consumption references
#' considered include all registry-declared formula/filter columns, merge keys,
#' source/date inputs, and parameter codes. They are resolved against the
#' dataset on which each step actually reads them. Review-only variables do
#' not produce inputs. Cycles are annotated and rejected by validate_ir().
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
  assert_known_columns(known_columns)
  graph <- dependency_graph(ir, known_columns)
  out <- ir[graph$order]
  if (length(graph$blocked)) attr(out, "cycle_variables") <- vapply(ir[graph$blocked], function(v) v$variable, character(1))
  out
}

step_refs <- function(v, s) {
  a <- s$args; ds <- a$on %||% v$dataset
  rows <- list()
  add <- function(dataset, inputs, kind = "column") {
    for (input in inputs) if (!is.null(input) && is.character(input) && length(input) == 1L && !is.na(input) && nzchar(input)) {
      rows[[length(rows) + 1L]] <<- data.frame(dataset = dataset, input = input, kind = kind)
    }
  }
  for (nm in aa_layers()[[s$layer]]$inputs) {
    x <- a[[nm]]
    if (is.null(x)) next
    kind <- if (nm %in% c("parameters", "constant_parameters")) "parameter" else "column"
    if (nm %in% c("filter", "restrict_filter", "formula")) {
      x <- tryCatch(all.vars(parse(text = x)), error = function(e) character())
    }
    if (nm %in% c("filter", "restrict_filter")) {
      param_ds <- if (s$layer == "merge_var") a$dataset_add else ds
      add(param_ds, filter_parameters(a[[nm]]), "parameter")
    }
    if (s$layer == "merge_var") {
      add(a$dataset_add, x, kind)
      if (nm == "by_vars") add(ds, x)
    } else if (s$layer == "lookup_join") {
      add(a$dataset_lookup, x, kind)
      if (nm == "by_vars") add(ds, x)
    } else add(ds, x, kind)
  }
  if (s$layer == "compute_param") add(ds, c("PARAMCD", "AVAL"))
  if (s$layer == "summary_record") add(ds, c("PARAMCD", a$analysis_var %||% "AVAL"))
  if (!length(rows)) return(data.frame(dataset = character(), input = character(), kind = character()))
  unique(do.call(rbind, rows))
}
step_products <- function(v, s) {
  ds <- s$args$on %||% v$dataset
  if (s$layer %in% c("compute_param", "summary_record")) {
    return(data.frame(dataset = ds, input = s$args$paramcd, kind = "parameter"))
  }
  targets <- s$args$target
  if (s$layer == "impute_dtc" && !is.null(targets)) {
    prefix <- sub("(DTM|DT)$", "", targets)
    targets <- c(targets, paste0(prefix, "DTF"), if (identical(s$args$output_class, "dtm")) paste0(prefix, "TMF"))
  }
  if (is.null(targets)) return(data.frame(dataset = character(), input = character(), kind = character()))
  data.frame(dataset = ds, input = targets, kind = "column")
}
ref_keys <- function(refs) paste(refs$dataset, refs$kind, refs$input, sep = "::")
variable_product_keys <- function(v) unique(unlist(lapply(v$steps, function(s) ref_keys(step_products(v, s)))))
variable_input_keys <- function(v) {
  made <- character(); refs <- character()
  for (s in v$steps) {
    refs <- c(refs, setdiff(ref_keys(step_refs(v, s)), made))
    made <- union(made, ref_keys(step_products(v, s)))
  }
  unique(refs)
}
dependency_graph <- function(ir, known_columns = character()) {
  n <- length(ir)
  if (n <= 1L) return(list(order = seq_len(n), blocked = integer(), duplicate = character()))
  active <- which(!vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
  products <- lapply(ir, variable_product_keys)
  producer <- list()
  for (i in active) for (key in products[[i]]) producer[[key]] <- union(producer[[key]], i)
  duplicate <- names(producer)[lengths(producer) > 1L]
  parents <- rep(list(integer()), n)
  for (i in active) {
    refs <- variable_input_keys(ir[[i]])
    for (key in refs) {
      if (length(known_columns) && sub("^.*::", "", key) %in% known_columns) next
      parents[[i]] <- union(parents[[i]], setdiff(producer[[key]] %||% integer(), i))
    }
  }
  ranks <- vapply(ir, step_rank, numeric(1))
  placed <- integer(); blocked <- integer()
  while (length(placed) < n) {
    remaining <- setdiff(seq_len(n), placed)
    ready <- remaining[vapply(parents[remaining], function(ps) all(ps %in% placed), logical(1))]
    if (!length(ready)) { blocked <- union(blocked, remaining); ready <- remaining }
    pick <- ready[order(ranks[ready], ready)][1]
    placed <- c(placed, pick)
  }
  list(order = placed, blocked = blocked, duplicate = duplicate)
}

#' Report undefined step inputs in an IR
#'
#' @description Audits every step's consumed references (duration endpoints,
#'   assign sources, compute_param/summary_record PARAMCD/AVAL expectations)
#'   against columns produced by earlier executable steps or whitelisted
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
  assert_known_columns(known_columns)
  available <- list()
  rows <- list()
  ordered <- order_variables(ir, known_columns)
  for (v in ordered) {
    if (isTRUE(v$needs_human)) next
    for (s in v$steps) {
      refs <- step_refs(v, s)
      for (i in seq_len(nrow(refs))) {
        key <- ref_keys(refs[i, , drop = FALSE])
        if (!key %in% unlist(available) && !refs$input[i] %in% known_columns) {
          rows[[length(rows) + 1L]] <- data.frame(variable = v$variable, input = refs$input[i],
            dataset = refs$dataset[i], issue = "not defined by earlier executable steps or known_columns; supply the source input or an upstream derivation")
        }
      }
      available[[length(available) + 1L]] <- ref_keys(step_products(v, s))
    }
  }
  cycle <- attr(ordered, "cycle_variables")
  for (v in cycle) rows[[length(rows) + 1L]] <- data.frame(variable = v, input = "<cycle>", dataset = "<graph>", issue = "cyclic dependency: revise derivation inputs")
  if (!length(rows)) return(data.frame(variable = character(), input = character(), dataset = character(), issue = character()))
  unique(do.call(rbind, rows))
}

filter_parameters <- function(text) {
  expr <- tryCatch(parse(text = text)[[1]], error = function(e) NULL)
  visit <- function(x) {
    if (!is.call(x)) return(character())
    if (identical(x[[1]], as.name("==")) && length(x) == 3L) {
      if (identical(x[[2]], as.name("PARAMCD")) && is.character(x[[3]])) return(x[[3]])
      if (identical(x[[3]], as.name("PARAMCD")) && is.character(x[[2]])) return(x[[2]])
    }
    unlist(lapply(as.list(x)[-1], visit), use.names = FALSE)
  }
  unique(visit(expr))
}
