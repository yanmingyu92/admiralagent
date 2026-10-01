#' Construct a layer step
#'
#' @description Builds one step of a variable's derivation pipeline: a layer
#'   name plus its named args. Nested one-element lists are flattened (JSON
#'   round-trip normalization) and empty args are dropped.
#' @title New layer step
#' @param layer Layer name; must be one of [layer_names()].
#' @param args Named list of layer arguments.
#' @return A list of class `aa_step` with elements `layer` and `args`.
#' @export
new_step <- function(layer, args = list()) {
  args <- lapply(args, function(a) {
    if (is.list(a) && length(a) && all(vapply(a, function(x) is.atomic(x) && length(x) == 1L && !is.null(x), logical(1)))) unlist(a, use.names = FALSE) else a
  })
  args <- args[lengths(args) > 0]
  structure(list(layer = layer, args = args), class = c("aa_step", "list"))
}

bds_artifacts <- c("AVAL", "AVALC", "PARAM", "PARAMCD", "AVALU", "AVISIT", "ADY", "ADT", "DTYPE")

vector_args <- list(
  merge_var = c("by_vars", "order"),
  lookup_join = "by_vars",
  compute_param = c("parameters", "constant_parameters", "by_vars"),
  summary_record = "by_vars",
  extreme_flag = c("by_vars", "order"),
  obs_number = c("by_vars", "order")
)

#' Construct a variable IR
#'
#' @description Builds the intermediate representation for one spec variable:
#'   dataset, variable name, ordered [new_step()] pipeline, plus provenance
#'   fields (verbatim spec text, confidence, review flag, rationale).
#' @title New variable IR
#' @param dataset Dataset the variable belongs to (e.g. `"ADSL"`).
#' @param variable Variable name (e.g. `"TRTSDTM"`).
#' @param steps List of `aa_step` objects in execution order.
#' @param spec_origin Verbatim derivation text from the spec.
#' @param confidence Classifier confidence in `[0, 1]`.
#' @param needs_human Logical; `TRUE` routes the variable to human review
#'   instead of code generation.
#' @param rationale Free-text explanation of the chosen layer chain.
#' @return A list of class `aa_variable_ir`.
#' @export
new_variable_ir <- function(dataset,
                            variable,
                            steps = list(),
                            spec_origin = NA_character_,
                            confidence = 1,
                            needs_human = FALSE,
                            rationale = NA_character_) {
  structure(
    list(
      dataset = dataset,
      variable = variable,
      steps = steps,
      spec_origin = spec_origin,
      confidence = confidence,
      needs_human = needs_human,
      rationale = rationale
    ),
    class = c("aa_variable_ir", "list")
  )
}

#' Check whether an IR is valid
#'
#' @description Shorthand for `length(validate_ir(ir)) == 0L`.
#' @title IR validity predicate
#' @param ir List of `aa_variable_ir` objects.
#' @return `TRUE` when the IR passes the full validation gate.
#' @export
is_valid_ir <- function(ir) {
  length(validate_ir(ir)) == 0L
}

#' Validate a variable IR
#'
#' @description Runs the schema and semantic gate every IR must pass before
#'   rendering: class/shape, layer known, required args present, exclusive-arg
#'   groups, per-layer semantic rules (enum values, formula token whitelists,
#'   label/break length agreement), BDS-artifact assign guards, vector-arg
#'   typing, foreign-only dataset detection, and column-rename tracking: a step
#'   that references a column on a dataset where an earlier merge brought that
#'   column in under a different name is reported (the old name only exists in
#'   the merge's source dataset). Dependency cycles are gated at
#'   two levels: variable-level cycles report `cyclic dependencies: ...`, and
#'   cycles between deliverable datasets report a distinct
#'   `cyclic deliverable dependencies: ...` problem naming the datasets that
#'   cannot be built in any order. Problems are reported, never
#'   guessed or repaired. String arguments are limited to 16384 bytes.
#'   Expressions admit uppercase identifiers, finite numbers, comparison and
#'   logical operators, arithmetic, parentheses and quoted filter values.
#'   Calls, assignments, indexing, comments and statement separators are rejected.
#' @title IR validation gate
#' @param ir List of `aa_variable_ir` objects built by [new_variable_ir()].
#' @return Character vector of human-readable problems; empty when valid.
#' @export
validate_ir <- function(ir) {
  shape <- validate_ir_shape(ir)
  if (length(shape)) return(shape)
  problems <- character()
  layers <- aa_layers()

  is_var_ir <- function(x) inherits(x, "aa_variable_ir")
  if (!is.list(ir) || length(ir) == 0 || !all(vapply(ir, is_var_ir, logical(1)))) {
    return("ir must be a non-empty list of `aa_variable_ir` objects built by new_variable_ir()")
  }

  for (v in ir) {
    vname <- if (is.null(v$variable)) "<unnamed>" else v$variable

    if (is.null(v$dataset) || !nzchar(v$dataset)) {
      problems <- c(problems, sprintf("[%s] missing `dataset`", vname))
    }
    if (is.null(v$variable) || !nzchar(v$variable)) {
      problems <- c(problems, sprintf("[%s] missing `variable`", vname))
    }
    if (isTRUE(v$needs_human) && length(v$steps) == 0L) next
    if (length(v$steps) == 0L) {
      problems <- c(problems, sprintf("[%s] has no steps and needs_human is FALSE", vname))
      next
    }

    for (i in seq_along(v$steps)) {
      s <- v$steps[[i]]
      id <- sprintf("[%s step %d]", vname, i)

      if (is.null(s$layer) || !s$layer %in% names(layers)) {
        problems <- c(problems, sprintf(
          "%s unknown layer '%s'; allowed: %s",
          id, paste0(s$layer, collapse = ""), paste(names(layers), collapse = ", ")
        ))
        next
      }
      l <- layers[[s$layer]]
      args <- s$args %||% list()

      for (req in l$required) {
        val <- args[[req]]
        if (is.null(val) || (is.character(val) && (length(val) == 0 || all(is.na(val) | !nzchar(val))))) {
          problems <- c(problems, sprintf("%s missing required arg '%s'", id, req))
        }
      }

      if (!is.null(l$exclusive)) {
        for (grp in l$exclusive) {
          present <- grp[vapply(grp, function(g) !is.null(args[[g]]) && !is.na(args[[g]]), logical(1))]
          if (length(present) != 1L) {
            problems <- c(problems, sprintf(
              "%s layer '%s' requires exactly one of [%s], got %d",
              id, s$layer, paste(grp, collapse = "/"), length(present)
            ))
          }
        }
      }

      problems <- c(problems, validate_step_semantics(s$layer, args, id))

      if (s$layer == "assign" && !is.null(args$from) && args$from %in% bds_artifacts) {
        problems <- c(problems, sprintf(
          "%s assign.from '%s' is a source-dataset BDS artifact; use merge_var to pull values across datasets",
          id, args$from
        ))
      }
      vec_args <- vector_args[[s$layer]]
      if (!is.null(vec_args)) {
        for (va in vec_args) {
          val <- args[[va]]
          if (!is.null(val) && !is.character(val)) {
            problems <- c(problems, sprintf("%s arg '%s' must be a character vector", id, va))
          }
        }
      }
    }

    foreign_only <- all(vapply(v$steps, function(s) {
      on <- s$args$on
      !is.null(on) && is.character(on) && nzchar(on) && !identical(on, v$dataset)
    }, logical(1)))
    if (foreign_only) {
      problems <- c(problems, sprintf(
        "[%s] all steps run on foreign datasets; add a merge_var/lookup_join step to bring the result into %s",
        vname, v$dataset
      ))
    }
  }
  if (length(problems)) return(problems)
  problems <- validate_ir_tokens(ir)
  if (length(problems)) return(problems)
  problems <- c(problems, renamed_column_problems(ir))
  if (length(problems)) return(problems)
  keys <- vapply(ir, function(v) paste(v$dataset, v$variable, sep = "::"), character(1))
  if (anyDuplicated(keys)) problems <- c(problems, "duplicate dataset/variable records are not allowed")
  graph <- dependency_graph(ir)
  if (length(graph$blocked)) problems <- c(problems, "cyclic dependencies: revise derivation inputs before execution")
  problems <- c(problems, deliverable_cycle_problems(ir))
  if (length(graph$duplicate)) problems <- c(problems, paste("multiple variables produce the same output:", paste(graph$duplicate, collapse = ", ")))
  for (v in ir) if (v$confidence < 0.7 && !v$needs_human) problems <- c(problems, paste(v$variable, "confidence below 0.7 requires needs_human=true"))
  problems
}

# Deliverable-level cycles are an unconditional problem, with no rank fallback.
# A variable cycle still renders a well-formed program because order_variables()
# falls back to rank ordering; a cycle between deliverables means no build order
# exists at all. Must run after validate_ir_shape(): deliverable_graph() asserts
# the IR shape and stops, whereas validate_ir() returns shape problems.
deliverable_cycle_problems <- function(ir) {
  cycles <- deliverable_graph(ir)$cycles
  if (!length(cycles)) return(character())
  sprintf(
    "cyclic deliverable dependencies: datasets %s cannot be built in any order; break the cross-dataset reference",
    paste(vapply(cycles, paste, character(1), collapse = " -> "), collapse = "; ")
  )
}

validate_step_semantics <- function(layer, args, id) {
  chr_nonempty <- function(x) is.character(x) && length(x) > 0 && all(!is.na(x) & nzchar(x))
  problems <- character()

  one_of <- function(arg, allowed) {
    val <- args[[arg]]
    if (!is.null(val) && (!chr_nonempty(val) || !val %in% allowed)) {
      sprintf("%s arg '%s' must be one of [%s]", id, arg, paste(allowed, collapse = ", "))
    }
  }

  if (layer == "merge_var") {
    problems <- c(problems, one_of("mode", c("first", "last")))
  }
  if (layer == "impute_dtc") {
    if (identical(args$output_class, "dt") && !is.null(args$time_imputation)) {
      problems <- c(problems, paste(id, "time_imputation is only valid for output_class='dtm'; omit it for dates"))
    }
    problems <- c(problems, one_of("output_class", c("dtm", "dt")))
    problems <- c(problems, one_of("highest_imputation", c("Y", "M", "D")))
    problems <- c(problems, one_of("date_imputation", c("first", "last")))
    if (!is.null(args$time_imputation)) {
      problems <- c(problems, one_of("time_imputation", c("first", "last")))
    }
  }
  if (layer == "duration") {
    problems <- c(problems, one_of("out_unit", c("years", "months", "days")))
  }
  if (layer == "date_shift") {
    if (!is.null(args$days) && !is.numeric(args$days)) {
      problems <- c(problems, sprintf("%s arg 'days' must be numeric (whole days)", id))
    }
  }
  if (layer == "categorize") {
    breaks <- args$breaks
    labels <- args$labels
    if (!is.null(breaks) && !is.numeric(breaks)) {
      problems <- c(problems, sprintf("%s arg 'breaks' must be a numeric vector", id))
    }
    if (!is.null(breaks) && !is.null(labels) && length(labels) != length(breaks) - 1) {
      problems <- c(problems, sprintf(
        "%s arg 'labels' must have length length(breaks) - 1 = %d, got %d",
        id, length(breaks) - 1, length(labels)
      ))
    }
  }
  if (layer == "summary_record") {
    problems <- c(problems, one_of("summary_fun", c("mean", "median", "min", "max", "sum")))
  }
  if (layer == "compute_param") {
    formula <- args$formula %||% ""
    params <- args$parameters %||% character()
    if (chr_nonempty(formula) && chr_nonempty(params)) {
      tokens <- strsplit(gsub("[^A-Za-z0-9._]+", " ", formula), " +")[[1]]
      tokens <- tokens[nzchar(tokens)]
      allowed <- paste0("AVAL.", params)
      bad <- setdiff(tokens, c(allowed, as.character(params), "0":"9"))
      bad <- bad[!grepl("^[0-9.]+$", bad)]
      if (length(bad) > 0) {
        problems <- c(problems, sprintf(
          "%s formula uses tokens not in parameters [%s]: %s",
          id, paste(params, collapse = ", "), paste(bad, collapse = ", ")
        ))
      }
    }
  }
  if (layer == "compute_var") {
    formula <- args$formula %||% ""
    if (chr_nonempty(formula)) {
      tokens <- strsplit(gsub("[^A-Za-z0-9._]+", " ", formula), " +")[[1]]
      tokens <- tokens[nzchar(tokens)]
      bad_tokens <- tokens[!grepl("^[0-9.]+$", tokens) & make.names(tokens) != tokens]
      if (length(bad_tokens) > 0) {
        problems <- c(problems, sprintf(
          "%s compute_var formula tokens must be syntactic column names or numeric literals: %s",
          id, paste(bad_tokens, collapse = ", ")
        ))
      }
    }
  }
  problems
}

# A cross-dataset merge that renames a column (source != target) leaves the
# source name existing only in the SOURCE dataset; on the target dataset the
# values now live under the target name. A later step that still references the
# old name on the target dataset fails at execution (finding F-01: merge_var
# source=SVSTDTC -> target=TRTSDT, then impute_dtc dtc=SVSTDTC on ADSL). The
# gate catches that here by walking the IR in execution order and tracking, per
# dataset, both produced columns and rename evidence. A reference is only
# flagged when the IR itself contains the rename evidence AND nothing produced
# the old name on that dataset earlier - plain references to base columns
# (which validate_ir cannot see) and references to the new name stay legal.
renamed_column_problems <- function(ir) {
  problems <- character()
  produced <- list() # per dataset: columns earlier executable steps produced
  renamed <- list()  # per dataset: named char vector, old name -> new name
  for (v in order_variables(ir)) {
    if (isTRUE(v$needs_human)) next
    for (i in seq_along(v$steps)) {
      s <- v$steps[[i]]
      refs <- step_refs(v, s)
      for (j in seq_len(nrow(refs))) {
        if (refs$kind[j] != "column") next
        ds <- toupper(refs$dataset[j])
        col <- refs$input[j]
        if (col %in% produced[[ds]]) next
        rn <- renamed[[ds]]
        if (!is.null(rn)) {
          new_name <- unname(rn[col])
          if (!is.na(new_name)) {
            problems <- c(problems, sprintf(
              "[%s step %d] references column '%s' on dataset %s, but an earlier merge brought that column in as '%s'; reference the new name",
              v$variable, i, col, ds, new_name
            ))
          }
        }
      }
      prod <- step_products(v, s)
      for (ds in toupper(unique(prod$dataset))) {
        produced[[ds]] <- union(produced[[ds]], prod$input[toupper(prod$dataset) == ds & prod$kind == "column"])
      }
      a <- s$args
      if (!is.null(s$layer) && s$layer %in% c("merge_var", "lookup_join") &&
            !is.null(a$source) && !is.null(a$target) &&
            is.character(a$source) && is.character(a$target) &&
            length(a$source) == 1L && length(a$target) == 1L &&
            !is.na(a$source) && !is.na(a$target) && !identical(a$source, a$target)) {
        ds <- toupper(a$on %||% v$dataset)
        from_ds <- if (s$layer == "merge_var") a$dataset_add else a$dataset_lookup
        # A self-merge keeps the source column under its old name; only a merge
        # from a different dataset renames it away.
        if (is.null(from_ds) || !identical(toupper(from_ds), ds)) {
          rn <- renamed[[ds]] %||% stats::setNames(character(), character())
          rn[a$source] <- a$target
          renamed[[ds]] <- rn
        }
      }
    }
  }
  problems
}
