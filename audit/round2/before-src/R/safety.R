# Internal validation primitives. Never evaluate an IR expression during validation.
scalar_text <- function(x, allow_na = FALSE) {
  is.character(x) && length(x) == 1L &&
    ((allow_na && is.na(x)) || (!is.na(x) && nchar(x, type = "bytes") <= 16384L))
}
valid_name <- function(x, object = FALSE) {
  is.character(x) && length(x) > 0L && !anyNA(x) &&
    all(nchar(x, type = "bytes") <= 128L) &&
    all(grepl(if (object) "^[A-Za-z][A-Za-z0-9_]*$" else "^[A-Z][A-Z0-9_]*$", x)) &&
    !any(x %in% c("TRUE", "FALSE", "NULL", "NA", "Inf", "NaN"))
}
validate_ir_shape <- function(ir) {
  bad <- character()
  if (!is.list(ir) || !length(ir)) return("ir must be a non-empty list of aa_variable_ir objects")
  layers <- aa_layers()
  for (j in seq_along(ir)) {
    v <- ir[[j]]
    id <- paste0("[variable ", j, "]")
    if (!is.list(v) || !inherits(v, "aa_variable_ir")) {
      bad <- c(bad, paste(id, "must be an aa_variable_ir object")); next
    }
    for (nm in c("dataset", "variable")) {
      if (!scalar_text(v[[nm]]) || !valid_name(v[[nm]])) bad <- c(bad, paste(id, nm, "must be one uppercase identifier"))
    }
    for (nm in c("spec_origin", "rationale")) {
      if (!scalar_text(v[[nm]], TRUE)) bad <- c(bad, paste(id, nm, "must be one string (maximum 16384 bytes), or NA"))
    }
    if (!is.logical(v$needs_human) || length(v$needs_human) != 1L || anyNA(v$needs_human)) bad <- c(bad, paste(id, "needs_human must be TRUE or FALSE"))
    if (!is.numeric(v$confidence) || length(v$confidence) != 1L || anyNA(v$confidence) || any(!is.finite(v$confidence)) || any(v$confidence < 0 | v$confidence > 1)) bad <- c(bad, paste(id, "confidence must be a finite number in [0, 1]"))
    if (!is.list(v$steps)) { bad <- c(bad, paste(id, "steps must be a list")); next }
    for (i in seq_along(v$steps)) {
      st <- v$steps[[i]]; sid <- paste(id, "step", i)
      if (!is.list(st) || !scalar_text(st$layer) || !st$layer %in% names(layers)) {
        bad <- c(bad, paste(sid, "unknown layer; use layer_names()")); next
      }
      a <- st$args
      if (!is.list(a) || (length(a) && (is.null(names(a)) || anyNA(names(a)) || any(!nzchar(names(a))) || anyDuplicated(names(a))))) {
        bad <- c(bad, paste(sid, "args must be a uniquely named list")); next
      }
      schema <- c(layers[[st$layer]]$args, list(on = "character, source dataset object"))
      for (nm in names(a)) {
        x <- a[[nm]]; desc <- schema[[nm]]
        if (is.null(desc)) { bad <- c(bad, paste(sid, "unknown arg", nm)); next }
        vector <- grepl("vector", desc, fixed = TRUE)
        good <- if (startsWith(desc, "character")) is.character(x) else if (startsWith(desc, "numeric")) is.numeric(x) else is.logical(x)
        good <- good && length(x) > 0L && (vector || length(x) == 1L) && !anyNA(x)
        if (good && is.character(x)) good <- all(nchar(x, type = "bytes") <= 16384L) && all(nzchar(x))
        if (!good) bad <- c(bad, paste(sid, "arg", paste0("'", nm, "'"), if (startsWith(desc, "numeric") && !vector) "must be" else "must be a", if (vector) sub(",.*", "", desc) else paste(sub(",.*", "", desc), "scalar"), "without NULL/NA or oversized strings"))
      }
    }
  }
  bad
}
safe_expression <- function(text, formula = FALSE) {
  if (!scalar_text(text) || !nzchar(text)) return(FALSE)
  # Lexical tokens reject comments, separators, backticks and all non-whitelisted syntax.
  parsed <- tryCatch(parse(text = text, keep.source = TRUE), error = function(e) NULL)
  if (is.null(parsed) || length(parsed) != 1L) return(FALSE)
  pd <- utils::getParseData(parsed)
  terminals <- pd[pd$terminal, , drop = FALSE]
  allowed <- c("SYMBOL", "NUM_CONST", "STR_CONST", "'('", "')'", "'+'", "'-'", "'*'", "'/'", "'^'", "LT", "LE", "GT", "GE", "EQ", "NE", "AND", "AND2", "OR", "OR2", "'!'")
  if (any(!terminals$token %in% allowed)) return(FALSE)
  sym <- terminals$text[terminals$token == "SYMBOL"]
  if (any(!grepl("^[A-Z][A-Z0-9_]*(\\.[A-Z][A-Z0-9_]*)?$", sym))) return(FALSE)
  walk <- function(x, depth = 0L) {
    if (depth > 64L) return(FALSE)
    if (is.name(x)) return(TRUE)
    if (is.atomic(x)) return(length(x) == 1L && ((is.numeric(x) && is.finite(x)) || (!formula && is.character(x))))
    if (!is.call(x) || !is.name(x[[1]])) return(FALSE)
    op <- as.character(x[[1]])
    ops <- if (formula) c("(", "+", "-", "*", "/", "^") else c("(", "+", "-", "*", "/", "^", "<", "<=", ">", ">=", "==", "!=", "&", "&&", "|", "||", "!")
    op %in% ops && all(vapply(as.list(x)[-1], walk, logical(1), depth = depth + 1L))
  }
  walk(parsed[[1]])
}
validate_ir_tokens <- function(ir) {
  bad <- character()
  columns <- c("target", "from", "source", "dtc", "start", "end", "by_vars", "order", "analysis_var", "parameters", "constant_parameters")
  for (v in ir) for (s in v$steps) {
    a <- s$args; id <- paste0("[", v$variable, " ", s$layer, "]")
    for (nm in intersect(names(a), columns)) if (!valid_name(a[[nm]])) bad <- c(bad, paste(id, nm, "must contain uppercase variable identifiers only"))
    for (nm in intersect(names(a), c("on", "dataset_add", "dataset_lookup"))) if (!valid_name(a[[nm]], TRUE)) bad <- c(bad, paste(id, nm, "must be a dataset object identifier"))
    for (nm in intersect(names(a), c("filter", "restrict_filter", "formula"))) if (!safe_expression(a[[nm]], nm == "formula")) bad <- c(bad, paste(id, nm, "fails token whitelist: use uppercase variables, numbers, quoted filter values, operators and parentheses; no calls or assignments"))
    if (s$layer %in% c("compute_param", "summary_record") && identical(a$on %||% v$dataset, "ADSL")) bad <- c(bad, paste(id, "BDS parameter records cannot be computed directly on ADSL; use a source dataset and merge_var"))
    if (s$layer == "compute_param" && safe_expression(a$formula, TRUE)) {
      refs <- all.vars(parse(text = a$formula))
      if (length(setdiff(refs, paste0("AVAL.", a$parameters)))) bad <- c(bad, paste(id, "formula must reference only AVAL.<PARAMCD> from parameters"))
    }
    if (s$layer == "extreme_flag" && !a$mode %in% c("first", "last")) bad <- c(bad, paste(id, "mode must be first or last"))
    if (s$layer == "date_shift" && (!is.finite(a$days) || a$days != floor(a$days))) bad <- c(bad, paste(id, "days must be finite whole days"))
    if (s$layer == "categorize" && (length(a$breaks) < 2L || is.unsorted(a$breaks, strictly = TRUE))) bad <- c(bad, paste(id, "breaks must be strictly increasing"))
    if (s$layer == "dtm_to_dt" && (!grepl("DTM$", a$source) || !identical(a$target, sub("DTM$", "DT", a$source)))) bad <- c(bad, paste(id, "target must equal source with DTM replaced by DT"))
    if (s$layer == "impute_dtc" && (!grepl(if (identical(a$output_class, "dtm")) "DTM$" else "DT$", a$target) || identical(a$target, a$dtc))) bad <- c(bad, paste(id, "target must end in DT/DTM matching output_class and differ from dtc"))
  }
  bad
}
assert_valid_ir <- function(ir) {
  problems <- validate_ir(ir)
  if (length(problems)) stop(paste(c("Invalid IR:", problems), collapse = "\n- "), call. = FALSE)
  invisible(ir)
}
comment_text <- function(x) gsub("[\r\n]", "\n# ", x)

assert_ir_shape <- function(ir, allow_empty = FALSE) {
  if (allow_empty && is.list(ir) && !length(ir)) return(invisible(ir))
  msg <- validate_ir_shape(ir)
  if (length(msg)) stop(paste(msg, collapse = "; "), call. = FALSE)
  invisible(ir)
}
assert_path <- function(path) {
  if (!scalar_text(path) || !nzchar(path)) stop("path must be one non-empty file path string", call. = FALSE)
  invisible(path)
}
write_utf8 <- function(text, path) {
  con <- file(path, open = "wt", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(enc2utf8(text), con, useBytes = TRUE)
}
