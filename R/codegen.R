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
#' @keywords internal
render_step <- function(step, v, i) {
  assert_valid_ir(list(v))
  if (!real_numeric(i) || length(i) != 1L || !is.finite(i) || i < 1 ||
      i != floor(i) || i > length(v$steps)) stop("i must be a valid step index within v$steps", call. = FALSE)
  if (!identical(step, v$steps[[i]])) stop("step must be identical to v$steps[[i]]; validate the complete parent IR", call. = FALSE)
  render_step_validated(step, v, i)
}

render_step_validated <- function(step, v, i, language = "r") {
  layers <- aa_layers()
  if (!step$layer %in% names(layers)) {
    stop("unknown layer '", step$layer, "' in step ", i, " of ", v$variable, call. = FALSE)
  }
  l <- layers[[step$layer]]
  obj <- step$args$on %||% v$dataset
  code <- l$render[[language]](step$args, obj)
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
    # FREE-TEXT POLICY (`rationale`): comment_text() already neutralises code
    # injection (newlines become comment continuations; pinned by
    # test-audit-security.R). The remaining *echo* channel is handled per
    # surface: on the in-process classify path `rationale` is machine-written
    # from a closed vocabulary and is rendered verbatim here; on the MCP paths
    # every tool that accepts or produces IR digests BOTH free-text fields at
    # ingress in `mcp_redact_ir()` (R/mcp.R) - `spec_origin` becomes
    # 'origin:<hex>' and `rationale` becomes 'rationale:<hex>', as the tool
    # descriptions state - so client-supplied text never reaches generated
    # code, responses or sidecars. Rendering here stays text-faithful for
    # in-process callers; redaction is the MCP boundary's job, not this one's.
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

# The abstention block's headline, as one exact line. It is the only marker
# that says "no code was generated for this variable", so `read_artifact()`
# uses it to check that a sidecar's `needs_human` still agrees with the code
# that was actually rendered. Keep the two definitions in one place.
review_block_marker <- function(v) {
  paste0("# ---- ", v$variable, " | NEEDS HUMAN REVIEW ----")
}

# TRUE when this variable renders the abstention block rather than code.
renders_review_block <- function(v) isTRUE(v$needs_human) || length(v$steps) == 0

render_variable_validated <- function(v, language = "r") {
  if (renders_review_block(v)) {
    header <- c(
      "# DISCLAIMER: DRAFT CODE - qualified human review required before use.",
      review_block_marker(v),
      if (!is.na(v$spec_origin) && nzchar(v$spec_origin)) paste0("# Spec origin: \"", comment_text(v$spec_origin), "\"") else NULL,
      if (!is.na(comment_text(v$rationale)) && nzchar(comment_text(v$rationale))) paste0("# Rationale: ", comment_text(v$rationale)) else NULL,
      "# No code generated: this derivation requires a human decision.",
      "# CHECK: statistician decides rule, then reclassify or hand-write."
    )
    return(paste(header, collapse = "\n"))
  }
  blocks <- vapply(seq_along(v$steps), function(i) render_step_validated(v$steps[[i]], v, i, language), character(1))
  paste(blocks, collapse = "\n\n")
}

# Layers used by the executable variables of an IR that have no renderer for
# `language`. Named, sorted and deduplicated so the error message is a usable
# work list rather than "not supported".
unimplemented_layers <- function(ir, language) {
  layers <- aa_layers()
  used <- unique(unlist(lapply(ir, function(v) {
    if (isTRUE(v$needs_human)) return(character())
    vapply(v$steps, function(s) s$layer %||% NA_character_, character(1))
  })))
  used <- sort(intersect(used[!is.na(used)], names(layers)))
  used[!vapply(used, function(nm) layer_implements(layers[[nm]], language), logical(1))]
}

# Approval provenance for a reader who only ever sees the .R file. Free-text
# signer and reason go through comment_text() for the same reason spec_origin
# does: a newline in either would otherwise escape the comment block.
# Returns NULL when ungated, so an ungated program renders byte-identically.
gate_header_lines <- function(gate) {
  if (is.null(gate)) return(NULL)
  g <- as_gate(gate)
  c(
    paste0("# Approval gate ", g$gate_id, " (", g$decision, ") signed by ",
           comment_text(g$signer)),
    paste0("# Signed at: ", comment_text(g$time)),
    paste0("# Scope: ", comment_text(paste(g$scope, collapse = ", "))),
    paste0("# Reason: ", comment_text(g$reason)),
    "# An approval gate records WHO approved this program and WHEN. It is not",
    "# evidence that any derivation is correct, and it does not replace",
    "# independent double programming of the output data."
  )
}

assert_render_language <- function(language) {
  if (!is.character(language) || length(language) != 1L || is.na(language) ||
      !language %in% AA_LANGUAGES) {
    stop("language must be one of ", paste(AA_LANGUAGES, collapse = ", "), call. = FALSE)
  }
  invisible(language)
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
#' @param language Target language for the rendered program. Only `"r"` is
#'   implemented; `"sas"` and `"python"` are recognised targets that fail
#'   naming every layer in this IR that has no renderer yet.
#' @param gate Optional approval gate (see `sign_gate()`). When supplied, the
#'   signer, moment and reason are reproduced in the program header so a reader
#'   of the code alone can see who approved it. The header states plainly that
#'   an approval is not evidence of correctness; omitting the gate leaves the
#'   rendered program byte-identical to an ungated render.
#' @return A single character string of R code.
#' @export
render_program <- function(ir, backend_label = "rules", finalize = TRUE, language = "r",
                           gate = NULL) {
  assert_valid_ir(ir)
  assert_flag(finalize, "finalize")
  assert_render_language(language)
  if (!scalar_text(backend_label) || !nzchar(backend_label)) stop("backend_label must be one non-empty string", call. = FALSE)
  backend_label <- comment_text(backend_label)
  missing_layers <- unimplemented_layers(ir, language)
  if (!identical(language, "r") && !length(missing_layers)) {
    stop(
      "NotImplemented: render_program(language = \"", language,
      "\") has no program scaffold renderer", call. = FALSE
    )
  }
  if (length(missing_layers)) {
    stop(
      "NotImplemented: render_program(language = \"", language,
      "\") has no renderer for layer(s): ", paste(missing_layers, collapse = ", "),
      call. = FALSE
    )
  }
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
    gate_header_lines(gate),
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

  body <- vapply(order_variables(ir), render_variable_validated, character(1), language = language)

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

#' Render one program per deliverable plus a driver
#'
#' @description Splits an IR that spans several deliverable datasets into one
#'   [render_program()] per deliverable, emitted in the topological order of
#'   [deliverable_order()] so a dataset is always built after the deliverables
#'   whose columns and parameters it consumes. The driver is a runnable script
#'   that sources the programs in that order; it carries the same DISCLAIMER as
#'   the programs it drives.
#'
#'   A cyclic deliverable graph is not scheduleable. Rather than emit a driver
#'   that silently runs in the wrong order, the cycle members are named in the
#'   error, matching how `validate_ir()` treats variable-level cycles.
#' @param ir Non-empty list of `aa_variable_ir` objects, possibly spanning
#'   several datasets.
#' @param backend_label Backend label recorded in each program header.
#' @param finalize Whether each program appends the finalize/export block.
#' @param language Target language; see [render_program()].
#' @return List with `order` (deliverables, topologically sorted), `programs`
#'   (named list of program code, in that order), `files` (named list of
#'   suggested file names) and `driver` (the driver script).
#' @noRd
render_study <- function(ir, backend_label = "rules", finalize = TRUE, language = "r") {
  assert_valid_ir(ir)
  assert_render_language(language)
  order <- deliverable_order(ir)
  cycles <- attr(order, "cycle_datasets")
  if (length(cycles)) {
    stop(
      "cyclic deliverable dependency: ", paste(cycles, collapse = ", "),
      "; revise the cross-dataset derivations before rendering a study",
      call. = FALSE
    )
  }
  order <- as.character(order)
  datasets <- vapply(ir, function(v) normalize_dataset(v$dataset), character(1))
  files <- stats::setNames(paste0(tolower(order), ".R"), order)
  programs <- stats::setNames(lapply(order, function(node) {
    render_program(ir[datasets == node], backend_label = backend_label,
                   finalize = finalize, language = language)
  }), order)

  driver <- c(
    "# ============================================================",
    "# Study driver: builds every deliverable in dependency order",
    paste0("# Generated by admiralagent v", pkg_ver(), " (backend: ", comment_text(backend_label), ")"),
    "# DISCLAIMER: DRAFT CODE - starting point only. A qualified human",
    "# must review every derivation against the spec before any use in a",
    "# regulated workflow. See # CHECK comments and the artifact sidecar.",
    "# CHECK: confirm each program's source-dataset placeholders are bound",
    "# before running this driver end to end.",
    "# ============================================================",
    paste0("# Build order: ", paste(order, collapse = " -> ")),
    ""
  )
  for (node in order) {
    driver <- c(driver, paste0("source(\"", files[[node]], "\")  # ", node))
  }
  list(order = order, programs = programs, files = as.list(files),
       driver = paste(driver, collapse = "\n"))
}
