# Canonicalization: one semantic form per derivation.
#
# Two IRs that mean the same thing must compare equal even when they were
# produced independently (rules vs LLM), or round-tripped through a sidecar.
# Everything here is pure and offline: no data, no model, no dependency beyond
# the layer registry. Canonical form is for COMPARISON ONLY - it is not a valid
# `aa_variable_ir` (intermediates are alpha-renamed) and never reaches codegen.

# Args whose value is a set: element order carries no meaning.
SET_SEMANTIC_ARGS <- c("by_vars", "parameters", "constant_parameters")
# Args naming columns in some dataset; subject to intermediate alpha-renaming.
COLUMN_ARGS <- c("target", "from", "source", "dtc", "start", "end", "analysis_var", "by_vars", "order")
# Args holding an expression; normalized through the R parser, then renamed.
EXPR_ARGS <- c("filter", "restrict_filter", "formula")
# Args naming a dataset object; case-insensitive by `valid_name(object = TRUE)`.
DATASET_ARGS <- c("on", "dataset_add", "dataset_lookup")

# Fill registry-declared defaults so an omitted arg compares equal to the same
# arg stated explicitly. A default may be a literal or a function of the
# already-supplied args (duration$trunc_out depends on out_unit).
apply_layer_defaults <- function(args, defaults) {
  for (nm in names(defaults)) {
    if (is.null(args[[nm]])) {
      value <- defaults[[nm]]
      args[[nm]] <- if (is.function(value)) value(args) else value
    }
  }
  args
}

# Collapse whitespace and quoting variants by round-tripping through the
# parser. Input has already passed `safe_expression()`; an unparseable string
# is returned verbatim so canonicalization never masks a validation failure.
canonical_expression <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) return(text)
  parsed <- tryCatch(parse(text = text)[[1]], error = function(e) NULL)
  if (is.null(parsed)) return(text)
  paste(deparse(parsed, width.cutoff = 500L), collapse = " ")
}

# Columns a variable's own steps create that are not the variable itself.
# These are private scratch names - `rules` mints EXST_TRTSDTM where an LLM
# writes EXSTDTM - so their spelling must not count as a semantic difference.
# Order is first-appearance, which is stable because steps are ordered.
canonical_intermediates <- function(v) {
  produced <- character()
  for (s in v$steps) {
    tgt <- s$args$target
    if (!(is.character(tgt) && length(tgt) == 1L && !is.na(tgt) && nzchar(tgt))) next
    produced <- c(produced, tgt)
    if (identical(s$layer, "impute_dtc")) {
      prefix <- sub("(DTM|DT)$", "", tgt)
      produced <- c(produced, paste0(prefix, "DTF"))
      if (identical(s$args$output_class, "dtm")) produced <- c(produced, paste0(prefix, "TMF"))
    }
  }
  setdiff(unique(produced), v$variable)
}

canonical_renames <- function(v) {
  temps <- canonical_intermediates(v)
  stats::setNames(
    if (length(temps)) paste0("%T", seq_along(temps), "%") else character(),
    temps
  )
}

# Word-boundary substitution: EXSTDTC is never touched by a rename of EXSTDTM,
# and longest-first ordering keeps overlapping names independent.
rename_tokens <- function(x, map) {
  if (!length(map) || !is.character(x)) return(x)
  for (nm in names(map)[order(nchar(names(map)), decreasing = TRUE)]) {
    x <- gsub(paste0("\\b", nm, "\\b"), map[[nm]], x, perl = TRUE)
  }
  x
}

canonical_step <- function(s, v, map, layers) {
  args <- apply_layer_defaults(s$args %||% list(), layers[[s$layer]]$defaults)
  # An absent `on` means the variable's own dataset (see validate_ir foreign_only).
  args$on <- args$on %||% v$dataset
  for (nm in names(args)) {
    x <- args[[nm]]
    if (nm %in% DATASET_ARGS) {
      x <- tolower(x)
    } else if (nm %in% EXPR_ARGS) {
      x <- rename_tokens(canonical_expression(x), map)
    } else if (nm %in% COLUMN_ARGS) {
      x <- rename_tokens(x, map)
    }
    if (is.numeric(x)) x <- as.double(x)
    if (nm %in% SET_SEMANTIC_ARGS && is.character(x)) x <- sort(x)
    args[[nm]] <- x
  }
  list(layer = s$layer, args = if (length(args)) args[order(names(args))] else args)
}

# Canonical form of one variable IR. Provenance (spec_origin, rationale,
# confidence) is dropped: it is free text and self-reported, never semantics.
canonical_variable_ir <- function(v) {
  layers <- aa_layers()
  map <- canonical_renames(v)
  structure(
    list(
      dataset = tolower(v$dataset),
      variable = v$variable,
      needs_human = isTRUE(v$needs_human),
      steps = lapply(v$steps, canonical_step, v = v, map = map, layers = layers)
    ),
    class = c("aa_canonical_ir", "list")
  )
}

canonical_json <- function(x) {
  as.character(jsonlite::toJSON(
    unclass(x), auto_unbox = TRUE, null = "null", na = "null", digits = NA
  ))
}

# Three nested identities for one variable, coarse to fine:
#   abstention  - did this voter derive the variable at all?
#   layer_chain - which layers, rank-normalized; ignores every argument.
#   full        - complete canonical semantics.
# Two voters agreeing at `full` agree on the derivation; agreeing only at
# `layer_chain` means the same shape with different arguments, which is the
# divergence class most worth showing a human.
ir_fingerprint <- function(v, level = c("full", "layer_chain", "abstention")) {
  level <- match.arg(level)
  payload <- switch(level,
    abstention = if (isTRUE(v$needs_human) || !length(v$steps)) "abstain" else "derived",
    layer_chain = {
      layers <- aa_layers()
      names_chr <- vapply(v$steps, function(s) s$layer, character(1))
      ranks <- vapply(v$steps, function(s) as.double(layers[[s$layer]]$rank), numeric(1))
      paste(names_chr[order(ranks, names_chr)], collapse = ">")
    },
    full = canonical_json(canonical_variable_ir(v))
  )
  digest::digest(paste0(level, "|", payload), algo = "xxhash64", serialize = FALSE)
}
