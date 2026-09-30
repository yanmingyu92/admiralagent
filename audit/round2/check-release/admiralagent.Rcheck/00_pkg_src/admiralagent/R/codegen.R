step_rank <- function(v) {
  if (v$needs_human || length(v$steps) == 0) return(99)
  layers <- aa_layers()
  min(vapply(v$steps, function(s) {
    l <- layers[[s$layer]]
    if (is.null(l)) 99 else l$rank
  }, numeric(1)))
}

#' Render one IR step as code
#'
#' @description Renders a single step with its block header (variable, step
#'   index, layer, spec origin, rationale, confidence) and the `# CHECK`
#'   validation comments attached to the layer. Renders only; never executes.
#' @title Render a step
#' @param step An `aa_step` object.
#' @param v The parent `aa_variable_ir` object.
#' @param i Step index (1-based) within `v$steps`.
#' @return A character string of commented R code.
#' @export
render_step <- function(step, v, i) {
  assert_valid_ir(list(v))
  if (!real_numeric(i) || length(i) != 1L || !is.finite(i) || i < 1 ||
      i != floor(i) || i > length(v$steps)) stop("i must be a valid step index within v$steps", call. = FALSE)
  if (!identical(step, v$steps[[i]])) stop("step must be identical to v$steps[[i]]; validate the complete parent IR", call. = FALSE)
  render_step_validated(step, v, i)
}

render_step_validated <- function(step, v, i) {
  layers <- aa_layers()
  if (!step$layer %in% names(layers)) {
    stop("unknown layer '", step$layer, "' in step ", i, " of ", v$variable, call. = FALSE)
  }
  l <- layers[[step$layer]]
  obj <- step$args$on %||% v$dataset
  code <- l$render(step$args, obj)
  total <- length(v$steps)
  checks <- vapply(l$checks, function(cid) aa_checks()[[cid]]$description, character(1))
  check_lines <- paste0("# CHECK: ", checks)
  if (step$layer == "merge_var" &&
      is.null(step$args$order) &&
      !is.null(step$args$mode) && step$args$mode %in% c("first", "last")) {
    check_lines <- c(
      check_lines,
      paste0(
        "# CHECK: no `order` specified; confirm exactly one record per by_vars ",
        "after the filter (otherwise selection is nondeterministic)"
      )
    )
  }
  check_lines <- paste(check_lines, collapse = "\n")
  header <- c(
    "# DISCLAIMER: DRAFT CODE - qualified human review required before use.",
    paste0("# ---- ", v$variable, " | step ", i, "/", total, ": ", step$layer, " ----"),
    if (!is.na(v$spec_origin) && nzchar(v$spec_origin)) paste0("# Spec origin: \"", comment_text(v$spec_origin), "\"") else NULL,
    if (!is.na(comment_text(v$rationale)) && nzchar(comment_text(v$rationale))) paste0("# Agent rationale: ", comment_text(v$rationale)) else NULL,
    paste0("# Confidence: ", sprintf("%.2f", v$confidence))
  )
  paste0(
    paste(header, collapse = "\n"), "\n",
    check_lines, "\n",
    code
  )
}

#' Render one variable IR as code
#'
#' @description Renders a variable's full step pipeline via [render_step()],
#' or a `NEEDS HUMAN REVIEW` header block when the variable abstained.
#' @title Render a variable
#' @param v An `aa_variable_ir` object.
#' @return A character string of commented R code.
#' @export
render_variable <- function(v) {
  assert_valid_ir(list(v))
  render_variable_validated(v)
}

render_variable_validated <- function(v) {
  if (v$needs_human || length(v$steps) == 0) {
    header <- c(
      "# DISCLAIMER: DRAFT CODE - qualified human review required before use.",
      paste0("# ---- ", v$variable, " | NEEDS HUMAN REVIEW ----"),
      if (!is.na(v$spec_origin) && nzchar(v$spec_origin)) paste0("# Spec origin: \"", comment_text(v$spec_origin), "\"") else NULL,
      if (!is.na(comment_text(v$rationale)) && nzchar(comment_text(v$rationale))) paste0("# Rationale: ", comment_text(v$rationale)) else NULL,
      "# No code generated: this derivation requires a human decision.",
      "# CHECK: statistician decides rule, then reclassify or hand-write."
    )
    return(paste(header, collapse = "\n"))
  }
  blocks <- vapply(seq_along(v$steps), function(i) render_step_validated(v$steps[[i]], v, i), character(1))
  paste(blocks, collapse = "\n\n")
}

#' Render a full analysis program from an IR
#'
#' @description Assembles the complete dataset program: DISCLAIMER header,
#'   library calls, source-dataset placeholders, all variables in
#'   dependency-driven order via [order_variables()], and an optional
#'   finalize block (metatools/xportr spec-compliance tail). Fails when
#'   [check_admiral_compat()] reports a version conflict.
#' @title Render program
#' @param ir Non-empty list of `aa_variable_ir` objects.
#' @param backend_label Backend label recorded in the header (`"rules"` or
#'   `"llm"`).
#' @param finalize Whether to append the commented finalize/export block.
#' @return A single character string of R code.
#' @export
render_program <- function(ir, backend_label = "rules", finalize = TRUE) {
  assert_valid_ir(ir)
  backend_label <- comment_text(backend_label)
  msg <- check_admiral_compat(ir)
  if (length(msg) > 0) stop(msg, call. = FALSE)
  datasets <- unique(vapply(ir, function(v) v$dataset, character(1)))
  target <- datasets[[1]]
  source_objs <- sort(unique(unlist(lapply(ir, function(v) {
    unlist(lapply(v$steps, function(s) {
      out <- c(s$args$on, s$args$dataset_add)
      out[!is.na(out) & nzchar(out)]
    }))
  }))))
  source_objs <- setdiff(source_objs, target)

  header <- c(
    "# ============================================================",
    paste0("# ", target, " analysis dataset program"),
    paste0("# Generated by admiralagent v", pkg_ver(), " (backend: ", backend_label, ")"),
    "# DISCLAIMER: DRAFT CODE - starting point only. A qualified human",
    "# must review every derivation against the spec before any use in a",
    "# regulated workflow. See # CHECK comments and the artifact sidecar.",
    "# ============================================================",
    "library(admiral)",
    "library(dplyr)",
    "library(rlang)",
    "",
    "# ---- Source datasets (placeholders: replace with study data) ----"
  )
  for (obj in source_objs) {
    header <- c(header, paste0("# ", obj, " <- ...  # SDTM ", toupper(obj), " dataset"))
  }
  header <- c(header, paste0(target, " <- dm  # base subject-level dataset (placeholder)"), "")

  body <- vapply(order_variables(ir), render_variable_validated, character(1))

  tail_block <- if (finalize) c(
    "",
    "# ---- Finalize: spec compliance, order, export ------------------",
    "# CHECK: variable set/type/length vs spec (metacore) before export",
    "# Requires a metacore object `mc` from the study spec:",
    paste0("# ", target, " <- metatools::drop_unspec_vars(", target, ", mc)"),
    paste0("# metatools::check_variables(", target, ", mc)"),
    paste0("# ", target, " <- metatools::order_cols(", target, ", mc)"),
    paste0("# ", target, " <- metatools::sort_by_key(", target, ", mc)"),
    paste0("# ", target, " <- xportr::xportr_type(", target, ", mc, domain = \"", target, "\")"),
    paste0("# ", target, " <- xportr::xportr_length(", target, ", mc, domain = \"", target, "\")"),
    paste0("# ", target, " <- xportr::xportr_label(", target, ", mc, domain = \"", target, "\")"),
    paste0("# xportr::xportr_write(", target, ", path = \"", tolower(target), ".xpt\")  # filename <= 8 chars")
  ) else NULL

  paste(
    paste(header, collapse = "\n"),
    paste(body, collapse = "\n\n"),
    paste(tail_block, collapse = "\n"),
    sep = "\n\n"
  )
}
