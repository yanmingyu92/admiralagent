# Second IR type: analysis results (TLF), alongside `aa_variable_ir` (ADaM).
#
# WHY A SECOND TYPE AND NOT A SECOND LAYER. See .agents/ARS-SPIKE.md for the
# evidence; the short form:
#
#   * CDISC ARS's unit of analysis is a SCALAR STATISTIC OVER A ROW SET -
#     `Analysis` = AnalysisSet x DataSubset x grouping cell x Method/Operation,
#     with results landing in `OperationResult`, not in a column of the input
#     dataset. Every one of the 15 `aa_layers()` render closures emits
#     `dataset <- dataset |> ...`: one input table mutated in place. An
#     analysis produces a NEW RESULT OBJECT, so it cannot be a layer without
#     rewriting all 15 closures.
#   * ARS carries NO executable operation vocabulary: `Operation` has only
#     free-text `name`/`description`/`label` plus a display `resultPattern`,
#     and `AnalysisMethod.codeTemplate` is opaque sponsor-authored source.
#     ARS is therefore a SINK FORMAT, not an IR, and the compiler must own its
#     own closed operation registry - `aa_operations()` below - exactly as
#     `aa_layers()` is the closed vocabulary for derivations (AGENTS.md rule 1).
#   * No field may be added to `aa_variable_ir`: `canonical_ir()` whitelists
#     exactly seven fields, so two IRs differing only in a new field would
#     hash identically. A second TYPE is safe; a new field is not.
#
# This file defines the type, its registry, its validation gate, and its
# methods for the `ir_products()` / `ir_refs()` / `ir_rank()` seam in
# R/dependency.R. Everything here is internal: no @export, NAMESPACE untouched.

# Rank of every analysis record. `step_rank()` returns at most 99 (the
# needs-human / no-steps sentinel) for ADaM variables, so 100 places analyses
# strictly after every derivation in a mixed schedule. Analyses never produce
# columns, so they can never be a producer for a variable and the ordering is
# a genuine invariant, not a heuristic.
ANALYSIS_RANK <- 100

# The reference kind for an analysis result. `R/dependency.R` mints keys as
# `dataset::kind::input` with kind in {column, parameter}; a result cell is
# neither, so the vocabulary gains a third member. The key GRAMMAR is
# unchanged, which is why `normalize_ref_key()` and `ref_key_dataset()` keep
# working verbatim - only the namespace component now names an OUTPUT rather
# than a dataset when the kind is "result".
RESULT_KIND <- "result"

#' Operation registry for analysis results
#'
#' @description The closed vocabulary of statistical operations an
#'   `aa_analysis_ir` may request, mirroring what [aa_layers()] is for
#'   derivations. This registry exists because CDISC ARS does not supply one:
#'   its `Operation` class names the statistic in free text, which cannot be
#'   validated or rendered deterministically. ARS is a serialization target for
#'   this registry, never a source of it.
#'
#'   Each entry declares `label` (human text), `scale` (the measurement scale
#'   the operation is defined on: `"numeric"`, `"categorical"` or `"any"`),
#'   `result_pattern` (the display format, which maps to ARS
#'   `Operation.resultPattern`), `ars_name` (the free text to write into ARS
#'   `Operation.name`) and `order` (position within a method, which maps to the
#'   required ARS `Operation.order`).
#' @return A named list; one entry per operation id.
#' @noRd
aa_operations <- function() {
  list(
    n = list(
      label = "Number of non-missing observations",
      scale = "any", result_pattern = "XX", ars_name = "n", order = 1
    ),
    count = list(
      label = "Number of subjects or records in the group",
      scale = "categorical", result_pattern = "XX", ars_name = "Count", order = 2
    ),
    pct = list(
      label = "Percentage of the enclosing denominator",
      scale = "categorical", result_pattern = "XX.X", ars_name = "Percentage", order = 3
    ),
    mean = list(
      label = "Arithmetic mean",
      scale = "numeric", result_pattern = "XX.X", ars_name = "Mean", order = 4
    ),
    sd = list(
      label = "Standard deviation",
      scale = "numeric", result_pattern = "XX.XX", ars_name = "Standard Deviation", order = 5
    ),
    median = list(
      label = "Median",
      scale = "numeric", result_pattern = "XX.X", ars_name = "Median", order = 6
    ),
    q1 = list(
      label = "First quartile",
      scale = "numeric", result_pattern = "XX.X", ars_name = "First Quartile", order = 7
    ),
    q3 = list(
      label = "Third quartile",
      scale = "numeric", result_pattern = "XX.X", ars_name = "Third Quartile", order = 8
    ),
    min = list(
      label = "Minimum",
      scale = "numeric", result_pattern = "XX.X", ars_name = "Minimum", order = 9
    ),
    max = list(
      label = "Maximum",
      scale = "numeric", result_pattern = "XX.X", ars_name = "Maximum", order = 10
    )
  )
}

#' Names of the registered operations
#' @noRd
operation_names <- function() names(aa_operations())

# Output identifiers are display names ("T14-3-1"), not R symbols, so
# `valid_name()` - which demands a syntactic uppercase identifier - is the
# wrong gate. Hyphens and dots are admitted; everything else follows the same
# uppercase, bounded-length discipline as the rest of the IR.
valid_output_id <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) &&
    nchar(x, type = "bytes") <= 128L && grepl("^[A-Z][A-Z0-9._-]*$", x)
}

ANALYSIS_IR_FIELDS <- c(
  "output", "analysis_id", "dataset", "variable", "operations",
  "analysis_set", "data_subset", "grouping", "needs_human", "spec_origin"
)

#' Construct an analysis (TLF) IR record
#'
#' @description One ARS-shaped `Analysis`: a set of operations applied to
#'   `variable` in `dataset`, restricted to a subject population
#'   (`analysis_set`) and optionally a record subset (`data_subset`), optionally
#'   subdivided by `grouping` factors, contributing result cells to `output`.
#'
#'   `analysis_set` and `data_subset` are predicate expressions in the same
#'   sublanguage `safe_expression()` already fences for layer filters, so the
#'   columns and PARAMCD values they reference are recovered from the structured
#'   AST rather than re-parsed ad hoc - identical treatment to `filter` /
#'   `restrict_filter` on the ADaM path.
#'
#'   Unlike ARS - where `dataset` and `variable` are optional free strings - both
#'   are REQUIRED here. We are the producer, so we can be stricter than the
#'   serialization format, and requiring them is what makes the ADaM -> TLF
#'   edges derivable rather than merely hoped for.
#' @param output Output (TLF) identifier this analysis feeds, e.g. `"T14-3-1"`.
#' @param analysis_id Identifier of the analysis within the output.
#' @param dataset Input ADaM dataset, e.g. `"ADSL"`.
#' @param variable Analysis variable in `dataset`, e.g. `"AGE"`.
#' @param operations Character vector of ids from [aa_operations()].
#' @param analysis_set Predicate string selecting the subject population, or NA.
#' @param data_subset Predicate string selecting records, or NA.
#' @param grouping Character vector of grouping variables in `dataset`.
#' @param needs_human Logical; routes to human review instead of generation.
#' @param spec_origin Verbatim source text, or NA.
#' @return A list of class `aa_analysis_ir`.
#' @noRd
new_analysis_ir <- function(output,
                            analysis_id,
                            dataset,
                            variable,
                            operations = character(),
                            analysis_set = NA_character_,
                            data_subset = NA_character_,
                            grouping = character(),
                            needs_human = FALSE,
                            spec_origin = NA_character_) {
  structure(
    list(
      output = output,
      analysis_id = analysis_id,
      dataset = dataset,
      variable = variable,
      operations = operations,
      analysis_set = analysis_set,
      data_subset = data_subset,
      grouping = grouping,
      needs_human = needs_human,
      spec_origin = spec_origin
    ),
    class = c("aa_analysis_ir", "list")
  )
}

# A predicate arg that is present and meaningful. NA and "" both mean absent.
has_predicate <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

#' Validate one analysis IR record
#'
#' @description Schema and semantic gate for `aa_analysis_ir`, in the same
#'   spirit as [validate_ir()]: problems are reported, never guessed at or
#'   repaired. Checks exact field set, identifier shape, operation membership in
#'   [aa_operations()], operation uniqueness, and that predicate strings parse
#'   inside the `safe_expression()` sublanguage.
#' @param x Candidate record.
#' @return Character vector of human-readable problems; empty when valid.
#' @noRd
validate_analysis_ir_record <- function(x) {
  id <- if (is.list(x) && valid_output_id(x$analysis_id %||% NA)) x$analysis_id else "<unnamed>"
  tag <- function(...) sprintf("[%s] %s", id, paste0(...))

  if (!is.list(x) || !inherits(x, "aa_analysis_ir")) {
    return("analysis record must be an aa_analysis_ir object built by new_analysis_ir()")
  }
  if (!exact_fields(x, ANALYSIS_IR_FIELDS)) {
    return(tag("fields must be uniquely named, exact analysis IR fields: ",
               paste(ANALYSIS_IR_FIELDS, collapse = ", ")))
  }

  problems <- character()
  if (!valid_output_id(x$output)) problems <- c(problems, tag("output must be one uppercase output identifier"))
  if (!valid_output_id(x$analysis_id)) problems <- c(problems, tag("analysis_id must be one uppercase identifier"))
  if (!scalar_text(x$dataset) || !valid_name(x$dataset)) problems <- c(problems, tag("dataset must be one uppercase identifier"))
  if (!scalar_text(x$variable) || !valid_name(x$variable)) problems <- c(problems, tag("variable must be one uppercase identifier"))
  if (!scalar_flag(x$needs_human)) problems <- c(problems, tag("needs_human must be TRUE or FALSE"))
  if (!scalar_text(x$spec_origin, TRUE)) problems <- c(problems, tag("spec_origin must be one string, or NA"))

  grouping <- x$grouping
  if (!is.character(grouping) || (length(grouping) && !valid_name(grouping))) {
    problems <- c(problems, tag("grouping must be a character vector of uppercase identifiers"))
  }

  ops <- x$operations
  known <- operation_names()
  if (!is.character(ops) || anyNA(ops)) {
    problems <- c(problems, tag("operations must be a character vector"))
  } else if (!isTRUE(x$needs_human) && !length(ops)) {
    problems <- c(problems, tag("has no operations and needs_human is FALSE"))
  } else {
    unknown <- setdiff(ops, known)
    if (length(unknown)) {
      problems <- c(problems, tag("unknown operation(s) ", paste(unknown, collapse = ", "),
                                  "; allowed: ", paste(known, collapse = ", ")))
    }
    if (anyDuplicated(ops)) problems <- c(problems, tag("duplicate operations are not allowed"))
  }

  for (nm in c("analysis_set", "data_subset")) {
    value <- x[[nm]]
    if (!scalar_text(value, TRUE)) {
      problems <- c(problems, tag(nm, " must be one predicate string, or NA"))
      next
    }
    if (has_predicate(value) && !safe_expression(value)) {
      problems <- c(problems, tag(nm, " is not an accepted predicate expression"))
    }
  }
  problems
}

#' Validate a list of analysis IR records
#' @param ir List of `aa_analysis_ir` objects.
#' @return Character vector of problems; empty when valid.
#' @noRd
validate_analysis_ir <- function(ir) {
  if (!is.list(ir) || !length(ir)) return("analysis ir must be a non-empty list of aa_analysis_ir objects")
  problems <- unlist(lapply(ir, validate_analysis_ir_record), use.names = FALSE)
  if (length(problems)) return(problems)
  keys <- vapply(ir, function(x) paste(x$output, x$analysis_id, sep = "::"), character(1))
  if (anyDuplicated(keys)) problems <- c(problems, "duplicate output/analysis_id records are not allowed")
  problems
}

# ---- Dependency seam methods -----------------------------------------------
#
# These are the whole point of the second type: with them, `dependency_graph()`
# schedules a mixed ADaM + analysis IR without knowing analyses exist, and the
# ADaM-only path stays bit-identical because it never reaches this code.

# What an analysis PRODUCES: one result cell per operation, namespaced by the
# output rather than by a dataset. Nothing else in the compiler produces keys
# of kind "result", so an analysis can never collide with a derivation.
#' @noRd
ir_products.aa_analysis_ir <- function(x, ...) {
  if (!length(x$operations)) return(character())
  unique(paste(x$output, RESULT_KIND, paste(x$analysis_id, x$operations, sep = "."), sep = "::"))
}

# What an analysis CONSUMES: the analysed variable, every grouping factor, and
# every column named by its population / subset predicates - all qualified by
# the input ADaM dataset, which is exactly the key shape a variable IR produces.
# That shared shape is what makes the ADaM -> TLF edge fall out of the existing
# graph with no special case. PARAMCD values referenced in a predicate become
# "parameter" keys, matching how compute_param/summary_record products are keyed
# on the ADaM side, so a BDS analysis depends on the variable that adds its
# parameter.
#' @noRd
ir_refs.aa_analysis_ir <- function(x, ...) {
  ds <- x$dataset
  columns <- c(x$variable, x$grouping)
  parameters <- character()
  for (nm in c("analysis_set", "data_subset")) {
    text <- x[[nm]]
    if (!has_predicate(text)) next
    ast <- parse_predicate(text)
    columns <- c(columns, predicate_names(ast))
    parameters <- c(parameters, filter_parameters(text))
  }
  keep <- function(v) {
    v <- v[!is.na(v) & nzchar(v)]
    unique(v)
  }
  c(
    if (length(keep(columns))) paste(ds, "column", keep(columns), sep = "::"),
    if (length(keep(parameters))) paste(ds, "parameter", keep(parameters), sep = "::")
  )
}

#' @noRd
ir_rank.aa_analysis_ir <- function(x, ...) ANALYSIS_RANK

# ---- ADaM -> TLF projection ------------------------------------------------

#' Project a mixed IR onto dataset and output nodes
#'
#' @description The analysis counterpart of [deliverable_graph()]. Given a list
#'   mixing `aa_variable_ir` (ADaM) and `aa_analysis_ir` (TLF) records, returns
#'   the edges `ADaM dataset -> output` that exist because some analysis of that
#'   output consumes a key produced by an executable variable of that dataset.
#'
#'   Edge derivation is entirely by key matching through the same
#'   `ir_products()` / `ir_refs()` seam the scheduler uses, so an analysis
#'   reading `AGE` from `ADSL` is linked to whichever variable record produces
#'   `ADSL::column::AGE`. An analysis reading a column nobody derives - a raw
#'   collected variable - contributes no edge, mirroring how
#'   [deliverable_graph()] treats undeclared source domains.
#'
#'   Dataset identifiers are fused case-insensitively and output ids are taken
#'   verbatim; nodes and edges are sorted in the C locale so the result is
#'   deterministic and golden-testable.
#' @param ir List mixing `aa_variable_ir` and `aa_analysis_ir` records.
#' @return List with `datasets`, `outputs` and `edges` (data.frame `from`/`to`).
#' @noRd
analysis_graph <- function(ir) {
  if (!is.list(ir)) stop("ir must be a list of IR records", call. = FALSE)
  is_analysis <- vapply(ir, function(x) inherits(x, "aa_analysis_ir"), logical(1))
  variables <- ir[!is_analysis]
  analyses <- ir[is_analysis]

  datasets <- sort_radix(unique(normalize_dataset(
    vapply(variables, function(v) v$dataset, character(1))
  )))
  outputs <- sort_radix(unique(vapply(analyses, function(a) a$output, character(1))))

  # Only executable variables produce; a needs_human variable is a promise, not
  # a product - same rule as deliverable_graph().
  live <- variables[!vapply(variables, function(v) isTRUE(v$needs_human), logical(1))]
  owner <- list()
  for (v in live) {
    ds <- normalize_dataset(v$dataset)
    for (key in normalize_ref_key(ir_products(v))) owner[[key]] <- union(owner[[key]], ds)
  }

  from <- character()
  to <- character()
  for (a in analyses) {
    if (isTRUE(a$needs_human)) next
    keys <- normalize_ref_key(ir_refs(a))
    matched <- unlist(owner[intersect(keys, names(owner))], use.names = FALSE)
    producers <- sort_radix(unique(as.character(matched)))
    from <- c(from, producers)
    to <- c(to, rep(a$output, length(producers)))
  }
  edges <- unique(data.frame(from = from, to = to, stringsAsFactors = FALSE))
  edges <- edges[order(edges$from, edges$to, method = "radix"), , drop = FALSE]
  rownames(edges) <- NULL
  list(datasets = datasets, outputs = outputs, edges = edges)
}

#' Describe one analysis as ARS-facing metadata
#'
#' @description Resolves an `aa_analysis_ir`'s operations against
#'   [aa_operations()] into the fields an ARS `AnalysisMethod` / `Operation`
#'   serializer would write. This is deliberately a DESCRIPTION, not a writer:
#'   the spike concluded ARS is a sink, and the sink writer is future work. It
#'   exists so the registry's ARS-facing contract is exercised and pinned.
#' @param x An `aa_analysis_ir`.
#' @return Data.frame with columns `operation`, `order`, `ars_name`,
#'   `result_pattern`, `scale`, sorted by registry order.
#' @noRd
analysis_method_spec <- function(x) {
  problems <- validate_analysis_ir_record(x)
  if (length(problems)) stop(paste(problems, collapse = "; "), call. = FALSE)
  registry <- aa_operations()
  ops <- x$operations
  if (!length(ops)) {
    return(data.frame(operation = character(), order = numeric(), ars_name = character(),
                      result_pattern = character(), scale = character(), stringsAsFactors = FALSE))
  }
  out <- data.frame(
    operation = ops,
    order = vapply(ops, function(o) as.double(registry[[o]]$order), numeric(1), USE.NAMES = FALSE),
    ars_name = vapply(ops, function(o) registry[[o]]$ars_name, character(1), USE.NAMES = FALSE),
    result_pattern = vapply(ops, function(o) registry[[o]]$result_pattern, character(1), USE.NAMES = FALSE),
    scale = vapply(ops, function(o) registry[[o]]$scale, character(1), USE.NAMES = FALSE),
    stringsAsFactors = FALSE
  )
  out <- out[order(out$order, out$operation, method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  out
}
