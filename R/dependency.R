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
#' @keywords internal
order_variables <- function(ir, known_columns = character()) {
  assert_ir_shape(ir, allow_empty = TRUE)
  assert_known_columns(known_columns)
  graph <- dependency_graph(ir, known_columns)
  out <- ir[graph$order]
  if (length(graph$blocked)) attr(out, "cycle_variables") <- vapply(ir[graph$blocked], function(v) v$variable, character(1))
  out
}

step_refs <- function(v, s) {
  a <- s$args
  ds <- a$on %||% v$dataset
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
    if (nm %in% c("filter", "restrict_filter", "formula", "condition")) {
      # Column references come from the structured predicate AST, not a second
      # ad-hoc parse of the text; identical result to all.vars() over the
      # sublanguage safe_expression() accepts.
      x <- predicate_names(parse_predicate(x))
    }
    if (nm %in% c("filter", "restrict_filter", "condition")) {
      param_ds <- if (s$layer == "merge_var") a$dataset_add else ds
      add(param_ds, filter_parameters(a[[nm]]), "parameter")
    }
    if (s$layer == "merge_var") {
      add(a$dataset_add, x, kind)
      if (nm == "by_vars") add(ds, x)
    } else if (s$layer == "lookup_join") {
      add(a$dataset_lookup, x, kind)
      if (nm == "by_vars") add(ds, x)
    } else {
      add(ds, x, kind)
    }
  }
  if (s$layer == "compute_param") add(ds, c("PARAMCD", "AVAL"))
  if (s$layer == "summary_record") add(ds, c("PARAMCD", a$analysis_var %||% "AVAL"))
  if (!length(rows)) return(data.frame(dataset = character(), input = character(), kind = character()))
  unique(do.call(rbind, rows))
}
# What a step adds to the data. The naming rules - including admiral's
# *DTF/*TMF imputation flag columns - are declared by the layer registry's
# `products()` hook (R/layers.R), never re-synthesised here: a renderer for
# another language reads the same hook and therefore builds the same graph.
step_products <- function(v, s) {
  ds <- s$args$on %||% v$dataset
  empty <- data.frame(dataset = character(), input = character(), kind = character())
  layer <- aa_layers()[[s$layer]]
  if (is.null(layer)) return(empty)
  made <- layer$products(s$args)
  keep <- function(x) {
    if (is.null(x) || !is.character(x)) return(character())
    x[!is.na(x) & nzchar(x)]
  }
  columns <- keep(made$columns)
  parameters <- keep(made$parameters)
  rows <- list(
    if (length(columns)) data.frame(dataset = ds, input = columns, kind = "column"),
    if (length(parameters)) data.frame(dataset = ds, input = parameters, kind = "parameter")
  )
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(empty)
  do.call(rbind, rows)
}
ref_keys <- function(refs) paste(refs$dataset, refs$kind, refs$input, sep = "::")
variable_product_keys <- function(v) unique(unlist(lapply(v$steps, function(s) ref_keys(step_products(v, s)))))
variable_input_keys <- function(v) {
  made <- character()
  refs <- character()
  for (s in v$steps) {
    refs <- c(refs, setdiff(ref_keys(step_refs(v, s)), made))
    made <- union(made, ref_keys(step_products(v, s)))
  }
  unique(refs)
}
# ---- IR-type seam ----------------------------------------------------------
#
# `dependency_graph()` used to call `variable_product_keys()` /
# `variable_input_keys()` directly, which hard-wired it to `aa_variable_ir`.
# The scheduler itself is not ADaM-specific: it only ever needs, per record,
# the set of `dataset::kind::input` keys the record PRODUCES, the set it
# CONSUMES, and a numeric rank for deterministic tie-breaking. Those three
# questions are now S3 generics, so a second IR type (see R/analysis_ir.R) can
# join the same graph without the scheduler knowing it exists.
#
# The `aa_variable_ir` methods delegate to the original functions UNCHANGED -
# they are not re-implementations, they are the same closures - so the ADaM
# path through `dependency_graph()` is bit-identical to before this seam
# existed. `variable_product_keys()` / `variable_input_keys()` also remain
# callable by name because R/execute.R and the pinned execute/renderer tests
# use them directly.

# Keys a record adds to the world.
ir_products <- function(x, ...) UseMethod("ir_products")
# Keys a record needs from the world, minus the ones it made for itself.
ir_refs <- function(x, ...) UseMethod("ir_refs")
# Scheduling rank; smaller runs earlier among simultaneously ready records.
ir_rank <- function(x, ...) UseMethod("ir_rank")

ir_products.aa_variable_ir <- function(x, ...) variable_product_keys(x)
ir_refs.aa_variable_ir <- function(x, ...) variable_input_keys(x)
ir_rank.aa_variable_ir <- function(x, ...) step_rank(x)

# An unclassed record is treated as an ADaM variable, which is what every
# caller predating the seam passed. No behaviour change, and a malformed
# object still fails inside the original function rather than silently
# contributing an empty node.
ir_products.default <- function(x, ...) variable_product_keys(x)
ir_refs.default <- function(x, ...) variable_input_keys(x)
ir_rank.default <- function(x, ...) step_rank(x)

dependency_graph <- function(ir, known_columns = character()) {
  n <- length(ir)
  if (n <= 1L) return(list(order = seq_len(n), blocked = integer(), duplicate = character()))
  active <- which(!vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
  # Dispatch through an explicit call rather than passing the bare generic to
  # `lapply`: `UseMethod()` resolves methods from the environment of the call
  # to the generic, and `lapply(ir, ir_products)` makes that base's frame,
  # where the methods are not visible.
  products <- lapply(ir, function(v) ir_products(v))
  producer <- list()
  for (i in active) for (key in products[[i]]) producer[[key]] <- union(producer[[key]], i)
  duplicate <- names(producer)[lengths(producer) > 1L]
  parents <- rep(list(integer()), n)
  for (i in active) {
    refs <- ir_refs(ir[[i]])
    for (key in refs) {
      if (length(known_columns) && sub("^.*::", "", key) %in% known_columns) next
      parents[[i]] <- union(parents[[i]], setdiff(producer[[key]] %||% integer(), i))
    }
  }
  ranks <- vapply(ir, function(v) ir_rank(v), numeric(1))
  placed <- integer()
  blocked <- integer()
  while (length(placed) < n) {
    remaining <- setdiff(seq_len(n), placed)
    ready <- remaining[vapply(parents[remaining], function(ps) all(ps %in% placed), logical(1))]
    if (!length(ready)) {
      blocked <- union(blocked, remaining)
      ready <- remaining
    }
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

#' Project the variable dependency graph onto deliverable datasets
#'
#' @description Collapses the variable-level graph used by [order_variables()]
#'   onto dataset nodes. An edge `D_a -> D_b` exists when some variable of
#'   `D_b` consumes an input key whose dataset component is `D_a`, and that key
#'   is produced by an executable variable of the IR. The underlying keys are
#'   already dataset-qualified (`dataset::kind::input`), so an ADTTE variable
#'   merging `source = "TRTSDTM"` from `dataset_add = "ADSL"` matches the ADSL
#'   variable that produces `TRTSDTM`.
#'
#'   Nodes are deliverables only: the distinct `dataset` fields of the IR
#'   variables. Source objects referenced through `on` / `dataset_add` /
#'   `dataset_lookup` that are never declared as a deliverable - raw SDTM
#'   domains such as `ex` or `vs` - are inputs, not deliverables. They have no
#'   producing variable in this IR, nothing about them can be scheduled and
#'   they can never take part in a deliverable cycle, so they are neither nodes
#'   nor edge endpoints.
#'
#'   Dataset identifiers are fused case-insensitively. `v$dataset` must be an
#'   uppercase identifier while `on`/`dataset_add`/`dataset_lookup` carry the
#'   dataset *object* form, which also admits lowercase (`ex`, `adsl`), so
#'   `"ADSL"` and `"adsl"` denote one node here. The normalization is local to
#'   this function; `valid_name()` and every validation rule are untouched.
#'
#'   Self edges are dropped: a dataset consuming its own products is ordinary
#'   within-dataset variable ordering, already resolved by [order_variables()].
#'
#'   The result is deterministic and golden-testable: nodes and edges are
#'   sorted in the C locale (radix), each strongly connected component is
#'   emitted with its members sorted - hence rotated to start at its
#'   lexicographically smallest member - and the components themselves are
#'   sorted by that first member.
#'
#' @title Deliverable-level dependency graph
#' @param ir List of `aa_variable_ir` objects.
#' @return List with `nodes` (sorted character vector of deliverable datasets),
#'   `edges` (data.frame with character columns `from` and `to`, sorted, no
#'   duplicates, no self edges) and `cycles` (list of character vectors: every
#'   strongly connected component with more than one member, plus any node
#'   carrying a self loop).
#' @noRd
deliverable_graph <- function(ir) {
  assert_ir_shape(ir, allow_empty = TRUE)
  nodes <- sort_radix(unique(normalize_dataset(vapply(ir, function(v) v$dataset, character(1)))))
  active <- which(!vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
  produced <- unique(unlist(lapply(ir[active], function(v) normalize_ref_key(ir_products(v))), use.names = FALSE))

  from <- character()
  to <- character()
  for (i in active) {
    consumer <- normalize_dataset(ir[[i]]$dataset)
    keys <- normalize_ref_key(ir_refs(ir[[i]]))
    producers <- unique(ref_key_dataset(keys[keys %in% produced]))
    producers <- sort_radix(setdiff(intersect(producers, nodes), consumer))
    from <- c(from, producers)
    to <- c(to, rep(consumer, length(producers)))
  }
  edges <- unique(data.frame(from = from, to = to, stringsAsFactors = FALSE))
  edges <- edges[order(edges$from, edges$to, method = "radix"), , drop = FALSE]
  rownames(edges) <- NULL
  list(nodes = nodes, edges = edges, cycles = graph_cycles(nodes, edges))
}

#' Topological order of the deliverable datasets
#'
#' @description Kahn ordering of [deliverable_graph()]: a deliverable is emitted
#'   only after every deliverable whose products it consumes. Ties are broken in
#'   the C locale, so the order is deterministic and golden-testable. A cyclic
#'   component cannot be scheduled; its members are emitted in C-locale order and
#'   listed in the `cycle_datasets` attribute, mirroring how [order_variables()]
#'   degrades rather than erroring.
#' @param ir List of `aa_variable_ir` objects.
#' @return Character vector of deliverable dataset names, optionally carrying a
#'   `cycle_datasets` attribute.
#' @noRd
deliverable_order <- function(ir) {
  graph <- deliverable_graph(ir)
  edges <- graph$edges
  remaining <- graph$nodes
  placed <- character()
  blocked <- character()
  while (length(remaining)) {
    ready <- remaining[vapply(remaining, function(n) {
      all(edges$from[edges$to == n] %in% placed)
    }, logical(1))]
    if (!length(ready)) {
      blocked <- union(blocked, remaining)
      ready <- remaining
    }
    pick <- sort_radix(ready)[1]
    placed <- c(placed, pick)
    remaining <- setdiff(remaining, pick)
  }
  if (length(blocked)) attr(placed, "cycle_datasets") <- sort_radix(blocked)
  placed
}

# C-locale ordering keeps golden output independent of the session locale.
sort_radix <- function(x) x[order(x, method = "radix")]
normalize_dataset <- function(x) toupper(x)
ref_key_dataset <- function(keys) if (length(keys)) normalize_dataset(sub("::.*$", "", keys)) else character()
normalize_ref_key <- function(keys) if (length(keys)) paste0(ref_key_dataset(keys), sub("^[^:]*", "", keys)) else character()

# Strongly connected components via transitive closure; node counts here are
# the number of deliverables in one spec, so the cubic closure is free.
graph_cycles <- function(nodes, edges) {
  n <- length(nodes)
  if (!n || !nrow(edges)) return(list())
  reach <- matrix(FALSE, n, n, dimnames = list(nodes, nodes))
  reach[cbind(edges$from, edges$to)] <- TRUE
  for (k in seq_len(n)) reach <- reach | outer(reach[, k], reach[k, ], "&")
  groups <- list()
  for (i in seq_len(n)) {
    # Non-empty only when node i lies on a cycle: a multi-member component, or
    # a self loop (which current edge construction never emits).
    members <- sort_radix(nodes[reach[i, ] & reach[, i]])
    if (length(members)) groups[[length(groups) + 1L]] <- members
  }
  groups <- unique(groups)
  groups[order(vapply(groups, `[`, character(1), 1L), method = "radix")]
}

filter_parameters <- function(text) predicate_paramcd_values(parse_predicate(text))
