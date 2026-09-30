exprs_chr <- function(x) paste(x, collapse = ", ")

# Languages the renderer seam knows about. "r" is the only one implemented;
# the others exist so an unimplemented target fails loudly and by name.
AA_LANGUAGES <- c("r", "sas", "python")

#' Quote a literal for one target language
#'
#' @description Replaces the former `q_chr()`, which produced a JSON literal via
#'   `jsonlite::toJSON()`. JSON escaping merely *coincides* with R string-literal
#'   syntax; it is not a quoting rule for any other language. In particular JSON
#'   leaves the apostrophe unescaped, which is correct for R (double-quoted) and
#'   wrong for SAS (single-quoted, apostrophe doubled) and Python
#'   (single-quoted, apostrophe backslash-escaped) - and apostrophes really do
#'   occur in PARAM text ("Investigator's choice"). Quoting is therefore a
#'   per-language decision taken here, not a serialisation side effect.
#' @param x Values to quote; coerced with `as.character()`.
#' @param language One of `AA_LANGUAGES`.
#' @return Character vector of literals in the target language's syntax.
#' @noRd
quote_literal <- function(x, language = "r") {
  if (!is.character(language) || length(language) != 1L || is.na(language)) {
    stop("language must be one string", call. = FALSE)
  }
  txt <- enc2utf8(as.character(x))
  switch(
    language,
    # encodeString() is R's own literal writer: exact round-trip through
    # parse(), including apostrophes, embedded double quotes and backslashes.
    r = unname(encodeString(txt, quote = "\"")),
    sas = paste0("'", gsub("'", "''", txt, fixed = TRUE), "'"),
    python = paste0("'", gsub("(['\\\\])", "\\\\\\1", txt), "'"),
    stop("no literal quoting rule for language '", language, "'", call. = FALSE)
  )
}

arg_line <- function(name, value, quoted = FALSE, language = "r") {
  if (is.null(value) || length(value) == 0 || all(is.na(value))) return(NULL)
  val <- if (quoted) quote_literal(value, language) else as.character(value)
  paste0(name, " = ", val)
}

collapse_lines <- function(parts, indent = "    ") {
  keep <- !vapply(parts, is.null, logical(1))
  paste(unlist(parts[keep]), collapse = paste0(",\n", indent))
}

#' Layer registry for admiralagent
#'
#' @description Returns the single source of truth mapping each derivation
#'   layer to its admiral/metatools function, argument schema, required args,
#'   render closure, check ids, and ordering rank. The LLM output space is the
#'   cartesian product of this registry; nothing outside it passes
#'   [validate_ir()].
#' @title Layer registry
#' @return A named list; one entry per layer with elements `fn`, `label`,
#'   `args`, `required`, `rank`, `checks`, `inputs`, `render`, and - where the
#'   layer has optional args with an implied value - `defaults`, a named list
#'   of literals or functions of the supplied args. Defaults are applied to
#'   `render` input and by canonicalization, so an omitted arg and the same arg
#'   stated explicitly are one derivation.
#' @export
aa_layers <- function() {
  registry <- list(
    assign = list(
      fn = "dplyr::mutate",
      label = "Direct assignment: copy a source variable or set a literal constant",
      args = list(
        target = "character, new variable name",
        from = "character, source variable name in current dataset (mutually exclusive with literal)",
        literal = "character, literal constant value (quoted)"
      ),
      required = "target",
      exclusive = list(c("from", "literal")),
      rank = 9,
      checks = c("not_all_na"),
      render = function(args, dataset) {
        value <- if (!is.null(args$literal) && !is.na(args$literal)) {
          quote_literal(args$literal, "r")
        } else if (!is.null(args$from)) {
          args$from
        } else {
          stop("layer 'assign': exactly one of `from` or `literal` is required", call. = FALSE)
        }
        paste0(
          dataset, " <- ", dataset, " |>\n  dplyr::mutate(",
          args$target, " = ", value, ")"
        )
      }
    ),
    merge_var = list(
      fn = "admiral::derive_vars_merged",
      label = "Pull a value from another dataset/timepoint, e.g. first dose date from EX",
      args = list(
        target = "character, new variable name",
        source = "character, variable name in dataset_add",
        dataset_add = "character, source dataset object name (e.g. 'ex')",
        by_vars = "character vector, merge keys",
        order = "character vector, ordering variables within by_vars (optional)",
        mode = "character, 'first' or 'last'",
        filter = "character, filter expression on dataset_add (optional)"
      ),
      required = c("target", "source", "dataset_add", "by_vars", "mode"),
      rank = 1,
      checks = c("key_uniqueness", "not_all_na"),
      predicates = "filter",
      render = function(args, dataset) {
        parts <- list(
          paste0("dataset_add = ", args$dataset_add),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          if (!is.null(args$order)) paste0("order = exprs(", exprs_chr(args$order), ")"),
          paste0("mode = ", quote_literal(args$mode, "r")),
          paste0("new_vars = exprs(", args$target, " = ", args$source, ")"),
          if (!is.null(args$filter)) paste0("filter_add = ", args$filter)
        )
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_vars_merged(\n    ",
          collapse_lines(parts), "\n  )"
        )
      }
    ),
    lookup_join = list(
      fn = "admiral::derive_vars_merged_lookup",
      label = "Join a lookup table, e.g. VSTESTCD -> PARAMCD",
      args = list(
        target = "character, new variable name",
        source = "character, variable in lookup dataset",
        dataset_lookup = "character, lookup dataset object name",
        by_vars = "character vector, lookup join keys"
      ),
      required = c("target", "source", "dataset_lookup", "by_vars"),
      rank = 1,
      checks = c("not_all_na"),
      render = function(args, dataset) {
        parts <- list(
          paste0("dataset_add = ", args$dataset_lookup),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          paste0("new_vars = exprs(", args$target, " = ", args$source, ")")
        )
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_vars_merged_lookup(\n    ",
          collapse_lines(parts), "\n  )"
        )
      }
    ),
    impute_dtc = list(
      fn = "admiral::derive_vars_dtm",
      label = "Impute a --DTC character date(-time) into numeric *DTM/*DT with flag columns",
      args = list(
        target = "character, new variable name ending in DT/DTM matching output_class; must differ from dtc",
        dtc = "character, source --DTC character variable",
        output_class = "character, 'dtm' (datetime) or 'dt' (date)",
        highest_imputation = "character, highest component allowed to impute: 'Y','M' or 'D'",
        date_imputation = "character, 'first' or 'last'",
        time_imputation = "character, 'first' or 'last' (dtm only, optional; forbidden for dt)"
      ),
      required = c("target", "dtc", "output_class", "highest_imputation", "date_imputation"),
      rank = 2,
      checks = c("imputation_flag", "not_all_na"),
      admiral_min = "1.5.0",
      # admiral's *DTF/*TMF flag columns are part of this derivation's output
      # contract, not an R implementation detail: a SAS or Python renderer that
      # does not emit them produces a program with the wrong DEPENDENCY GRAPH.
      # Declared here so every consumer reads one source of truth.
      products = function(args) list(columns = impute_dtc_outputs(args$target, args$output_class)),
      render = function(args, dataset) {
        prefix <- sub("(DTM|DT)$", "", args$target)
        parts <- list(
          paste0("new_vars_prefix = ", quote_literal(prefix, "r")),
          paste0("dtc = ", args$dtc),
          paste0("highest_imputation = ", quote_literal(args$highest_imputation, "r")),
          paste0("date_imputation = ", quote_literal(args$date_imputation, "r"))
        )
        if (identical(args$output_class, "dtm") && !is.null(args$time_imputation)) {
          parts <- c(parts, list(paste0("time_imputation = ", quote_literal(args$time_imputation, "r"))))
        }
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_vars_", args$output_class, "(\n    ",
          collapse_lines(parts), ",\n    flag_imputation = \"auto\"\n  )"
        )
      }
    ),
    dtm_to_dt = list(
      fn = "admiral::derive_vars_dtm_to_dt",
      label = "Extract the date part of a *DTM datetime variable into the matching *DT variable",
      args = list(
        target = "character, new variable name (the admiral API derives it from source by replacing DTM with DT)",
        source = "character, *DTM datetime variable to extract the date part from"
      ),
      required = c("target", "source"),
      rank = 2.5,
      checks = c("not_all_na"),
      render = function(args, dataset) {
        parts <- list(paste0("source_vars = exprs(", args$source, ")"))
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_vars_dtm_to_dt(\n    ",
          collapse_lines(parts), "\n  )"
        )
      }
    ),
    duration = list(
      fn = "admiral::derive_vars_duration",
      label = "Duration/age between two dates, e.g. AGE = years from BRTHDT to TRTSDT",
      args = list(
        target = "character, new variable name",
        start = "character, start date variable",
        end = "character, end date variable",
        out_unit = "character, 'years', 'months' or 'days'",
        add_one = "logical, inclusive day count (default FALSE for age)",
        trunc_out = "logical, truncate toward zero (TRUE for age)"
      ),
      required = c("target", "start", "end", "out_unit"),
      rank = 3,
      checks = c("not_all_na", "non_negative"),
      defaults = list(
        add_one = FALSE,
        trunc_out = function(args) identical(args$out_unit, "years")
      ),
      render = function(args, dataset) {
        add_one <- if (is.null(args$add_one)) FALSE else isTRUE(args$add_one)
        trunc_out <- if (is.null(args$trunc_out)) identical(args$out_unit, "years") else isTRUE(args$trunc_out)
        parts <- list(
          paste0("new_var = ", args$target),
          paste0("start_date = ", args$start),
          paste0("end_date = ", args$end),
          paste0("out_unit = ", quote_literal(args$out_unit, "r")),
          paste0("add_one = ", tocharacter_lgl(add_one)),
          paste0("trunc_out = ", tocharacter_lgl(trunc_out))
        )
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_vars_duration(\n    ",
          collapse_lines(parts), "\n  )"
        )
      }
    ),
    date_shift = list(
      fn = "dplyr::mutate",
      label = "Shift a date by a fixed number of days, e.g. TRTEDT = TRTSDT + 7 (days may be negative)",
      args = list(
        target = "character, new variable name",
        source = "character, date variable to shift",
        days = "numeric, whole days to add; may be negative"
      ),
      required = c("target", "source", "days"),
      rank = 3.5,
      checks = c("not_all_na"),
      render = function(args, dataset) {
        days <- format(as.numeric(args$days), trim = TRUE, scientific = FALSE, digits = 17)
        paste0(
          dataset, " <- ", dataset, " |>\n  dplyr::mutate(",
          args$target, " = as.Date(", args$source, ") + ", days, ")"
        )
      }
    ),
    compute_param = list(
      fn = "admiral::derive_param_computed",
      label = "Compute a new parameter from other parameters, e.g. BMI from WEIGHT/HEIGHT",
      args = list(
        paramcd = "character, new PARAMCD value",
        param = "character, new PARAM description",
        avalu = "character, analysis unit (optional)",
        parameters = "character vector, PARAMCD values the formula uses",
        formula = "character, expression over AVAL.<PARAMCD> tokens, e.g. 'AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2'",
        by_vars = "character vector, e.g. c('STUDYID','USUBJID'); must cover any keys a later merge_var will join on, since non-by_vars columns are NA in computed records",
        filter = "character, filter expression on the source records, e.g. \"VISIT == 'BASELINE'\" (optional)",
        constant_parameters = "character vector, subject-level constants broadcast across visits (optional)"
      ),
      required = c("paramcd", "param", "parameters", "formula", "by_vars"),
      rank = 4,
      checks = c("not_all_na"),
      admiral_min = "1.5.0",
      predicates = "filter",
      products = function(args) list(parameters = args$paramcd),
      render = function(args, dataset) {
        parts <- list(
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          paste0("parameters = c(", exprs_chr(quote_literal(args$parameters, "r")), ")"),
          paste0(
            "set_values_to = exprs(AVAL = ", args$formula,
            ", PARAMCD = ", quote_literal(args$paramcd, "r"),
            ", PARAM = ", quote_literal(args$param, "r"),
            if (!is.null(args$avalu)) paste0(", AVALU = ", quote_literal(args$avalu, "r")) else "",
            ")"
          ),
          if (!is.null(args$filter)) paste0("filter = ", args$filter),
          if (!is.null(args$constant_parameters)) {
            paste0("constant_parameters = c(", exprs_chr(quote_literal(args$constant_parameters, "r")), ")")
          }
        )
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_param_computed(\n    ",
          collapse_lines(parts), "\n  )"
        )
      }
    ),
    summary_record = list(
      fn = "admiral::derive_summary_records",
      label = "Add a summary record across replicates, e.g. AVERAGE of AVAL within by_vars",
      args = list(
        paramcd = "character, summary PARAMCD",
        param = "character, summary PARAM description",
        by_vars = "character vector, grouping keys",
        analysis_var = "character, usually 'AVAL'",
        summary_fun = "character, one of 'mean','median','min','max','sum'"
      ),
      required = c("paramcd", "param", "by_vars", "summary_fun"),
      rank = 5,
      checks = c("not_all_na"),
      admiral_min = "1.5.0",
      defaults = list(analysis_var = "AVAL"),
      products = function(args) list(parameters = args$paramcd),
      render = function(args, dataset) {
        av <- if (is.null(args$analysis_var)) "AVAL" else args$analysis_var
        parts <- list(
          paste0("dataset_add = ", dataset),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          paste0(
            "set_values_to = exprs(PARAMCD = ", quote_literal(args$paramcd, "r"),
            ", PARAM = ", quote_literal(args$param, "r"), ", ",
            av, " = ", args$summary_fun, "(", av, ", na.rm = TRUE))"
          )
        )
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_summary_records(\n    ",
          collapse_lines(parts), "\n  )"
        )
      }
    ),
    extreme_flag = list(
      fn = "admiral::derive_var_extreme_flag",
      label = "Flag one extreme record, e.g. ABLFL = Y on last record before treatment; use restrict_filter to scope",
      args = list(
        target = "character, flag variable name",
        by_vars = "character vector, grouping keys",
        order = "character vector, ordering variables",
        mode = "character, 'first' or 'last'",
        true_value = "character, flag value, usually 'Y'",
        restrict_filter = "character, filter restricting which records are flagged (optional)"
      ),
      required = c("target", "by_vars", "order", "mode"),
      rank = 6,
      checks = c("flag_rate"),
      defaults = list(true_value = "Y"),
      predicates = "restrict_filter",
      render = function(args, dataset) {
        tv <- if (is.null(args$true_value)) "Y" else args$true_value
        parts <- list(
          paste0("new_var = ", args$target),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          paste0("order = exprs(", exprs_chr(args$order), ")"),
          paste0("mode = ", quote_literal(args$mode, "r")),
          paste0("true_value = ", quote_literal(tv, "r"))
        )
        inner <- paste0(
          "admiral::derive_var_extreme_flag(\n      ",
          collapse_lines(parts, indent = "      "), "\n    )"
        )
        if (is.null(args$restrict_filter)) {
          paste0(dataset, " <- ", dataset, " |>\n  ", inner)
        } else {
          paste0(
            dataset, " <- ", dataset, " |>\n  admiral::restrict_derivation(\n",
            "    derivation = admiral::derive_var_extreme_flag,\n",
            "    args = params(new_var = ", args$target,
            ", by_vars = exprs(", exprs_chr(args$by_vars),
            "), order = exprs(", exprs_chr(args$order),
            "), mode = ", quote_literal(args$mode, "r"),
            ", true_value = ", quote_literal(tv, "r"), "),\n",
            "    filter = ", args$restrict_filter, "\n  )"
          )
        }
      }
    ),
    codelist_var = list(
      fn = "metatools::create_var_from_codelist",
      label = "Derive numeric/short variable from codelist, e.g. RACE -> RACEN",
      args = list(
        target = "character, new variable name",
        from = "character, input variable holding the decode side",
        decode_to_code = "logical, TRUE when input holds decode (default TRUE)"
      ),
      required = c("target", "from"),
      rank = 7,
      checks = c("values_in_ct", "not_all_na"),
      admiral_min = "1.5.0",
      defaults = list(decode_to_code = TRUE),
      render = function(args, dataset) {
        d2c <- if (is.null(args$decode_to_code)) TRUE else isTRUE(args$decode_to_code)
        paste0(
          dataset, " <- ", dataset, " |>\n  metatools::create_var_from_codelist(\n",
          "    metacore = mc,\n",
          "    input_var = ", args$from, ",\n",
          "    out_var = ", args$target, ",\n",
          "    decode_to_code = ", tocharacter_lgl(d2c), "\n",
          "  )"
        )
      }
    ),
    obs_number = list(
      fn = "admiral::derive_var_obs_number",
      label = "Analysis sequence number within by_vars",
      args = list(
        target = "character, new variable name",
        by_vars = "character vector, grouping keys",
        order = "character vector, ordering variables (optional)"
      ),
      required = c("target", "by_vars"),
      rank = 8,
      checks = c("not_all_na"),
      render = function(args, dataset) {
        parts <- list(
          paste0("new_var = ", args$target),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          if (!is.null(args$order)) paste0("order = exprs(", exprs_chr(args$order), ")")
        )
        paste0(
          dataset, " <- ", dataset, " |>\n  admiral::derive_var_obs_number(\n    ",
          collapse_lines(parts), "\n  )"
        )
      }
    ),
    categorize = list(
      fn = "dplyr::mutate",
      label = "Categorize a numeric variable into explicit breakpoint intervals, e.g. AGEGR1 from AGE",
      args = list(
        target = "character, new variable name",
        from = "character, source numeric variable to categorize",
        breaks = "numeric vector, increasing breakpoints passed to cut()",
        labels = "character vector, interval labels; length must be length(breaks) - 1",
        right = "logical, intervals closed on the right (default TRUE)",
        include_lowest = "logical, whether the lowest boundary is included (default TRUE)"
      ),
      required = c("target", "from", "breaks", "labels"),
      rank = 9.5,
      checks = c("not_all_na", "values_in_ct"),
      defaults = list(right = TRUE, include_lowest = TRUE),
      render = function(args, dataset) {
        right <- if (is.null(args$right)) TRUE else isTRUE(args$right)
        include_lowest <- if (is.null(args$include_lowest)) TRUE else isTRUE(args$include_lowest)
        breaks <- paste(vapply(args$breaks, function(x) format(x, trim = TRUE, scientific = FALSE, digits = 17), character(1)), collapse = ", ")
        labels <- paste(quote_literal(args$labels, "r"), collapse = ", ")
        paste0(
          dataset, " <- ", dataset, " |>\n",
          "  dplyr::mutate(\n",
          "    ", args$target, " = cut(\n",
          "      ", args$from, ",\n",
          "      breaks = c(", breaks, "),\n",
          "      labels = c(", labels, "),\n",
          "      right = ", tocharacter_lgl(right), ",\n",
          "      include.lowest = ", tocharacter_lgl(include_lowest), "\n",
          "    )\n",
          "  )\n",
          "# CHECK: human must confirm breakpoints and labels before use"
        )
      }
    ),
    compute_var = list(
      fn = "dplyr::mutate",
      label = "Column-wise arithmetic within existing records, e.g. CHG = AVAL - BASE; every column token in the formula must already exist in the dataset or be produced by an earlier step",
      args = list(
        target = "character, new variable name",
        formula = "character, arithmetic expression over EXISTING column names, e.g. 'AVAL - BASE'; grouping parentheses are allowed; function calls are rejected"
      ),
      required = c("target", "formula"),
      rank = 9.7,
      checks = c("not_all_na"),
      render = function(args, dataset) {
        paste0(
          dataset, " <- ", dataset, " |> dplyr::mutate(",
          args$target, " = ", args$formula, ")"
        )
      }
    )
  )
  # Dependency schema lives beside argument and render definitions.
  input_args <- list(assign = "from", merge_var = c("by_vars", "order", "source", "filter"),
    lookup_join = c("by_vars", "source"), impute_dtc = "dtc", dtm_to_dt = "source",
    duration = c("start", "end"), date_shift = "source",
    compute_param = c("by_vars", "parameters", "constant_parameters", "filter"),
    summary_record = c("by_vars", "analysis_var"), extreme_flag = c("by_vars", "order", "restrict_filter"),
    codelist_var = "from", obs_number = c("by_vars", "order"), categorize = "from", compute_var = "formula")
  for (nm in names(registry)) registry[[nm]]$inputs <- input_args[[nm]]
  out <- lapply(names(registry), function(nm) {
    layer <- registry[[nm]]
    layer$args$on <- "character, dataset object name for this step (optional)"
    # Every layer declares what it produces. Only the three layers with a
    # naming rule of their own state it explicitly; the rest produce their
    # `target` column, which is the default below.
    if (is.null(layer$products)) layer$products <- function(args) list(columns = args$target)
    if (is.null(layer$predicates)) layer$predicates <- character()
    # Defaults are applied once, here, so the registry stays the single source
    # of truth for both rendering and canonicalization. Render output is
    # unchanged: every closure already fell back to these exact values.
    if (length(layer$defaults)) {
      inner <- layer$render
      defaults <- layer$defaults
      layer$render <- function(args, dataset) inner(apply_layer_defaults(args, defaults), dataset)
    }
    # `render` is now a per-language renderer set: `layer$render[["r"]]` is the
    # implemented closure, the other languages are stubs that error by name.
    # The set is itself the R closure, so `layer$render(args, dataset)` keeps
    # working byte-identically for every existing caller.
    layer$render <- aa_renderset(nm, layer$render)
    layer
  })
  stats::setNames(out, names(registry))
}

# admiral derives the imputation flag columns from the target's stem: <stem>DTF
# always, plus <stem>TMF when a datetime is produced. This is the one place the
# rule is written down; dependency and execution consumers call it.
impute_dtc_outputs <- function(target, output_class) {
  if (is.null(target) || !is.character(target) || length(target) != 1L ||
      is.na(target) || !nzchar(target)) return(character())
  prefix <- sub("(DTM|DT)$", "", target)
  unique(c(target, paste0(prefix, "DTF"), if (identical(output_class, "dtm")) paste0(prefix, "TMF")))
}

# ---- Renderer seam ---------------------------------------------------------

render_not_implemented <- function(layer, language) {
  fn <- function(args, dataset) {
    stop(
      "NotImplemented: layer '", layer, "' has no ", language, " renderer",
      call. = FALSE
    )
  }
  attr(fn, "aa_stub") <- TRUE
  fn
}

# A renderer set is the R closure carrying every language's closure as an
# attribute, so it is simultaneously callable (`set(args, dataset)`, the legacy
# and R form) and subsettable (`set[["sas"]]`, the language-explicit form).
aa_renderset <- function(layer, r) {
  languages <- list(r = r)
  for (language in setdiff(AA_LANGUAGES, "r")) {
    languages[[language]] <- render_not_implemented(layer, language)
  }
  set <- r
  attr(set, "aa_languages") <- languages
  class(set) <- "aa_renderset"
  set
}

#' @noRd
`[[.aa_renderset` <- function(x, i, ...) {
  languages <- attr(x, "aa_languages")
  if (!is.character(i) || length(i) != 1L || is.na(i) || !i %in% names(languages)) {
    stop(
      "unknown render language; known languages are ",
      paste(names(languages), collapse = ", "),
      call. = FALSE
    )
  }
  languages[[i]]
}

# Registered at load time so `layer$render[["sas"]]` also dispatches when the
# package is installed; NAMESPACE is roxygen-generated and left untouched.
.onLoad <- function(libname, pkgname) {
  registerS3method("[[", "aa_renderset", `[[.aa_renderset`, envir = asNamespace(pkgname))
  invisible(NULL)
}

layer_render_fn <- function(layer, language = "r") {
  languages <- attr(layer$render, "aa_languages")
  if (is.null(languages)) return(layer$render)
  fn <- languages[[language]]
  if (is.null(fn)) {
    stop(
      "unknown render language '", language, "'; known languages are ",
      paste(names(languages), collapse = ", "), call. = FALSE
    )
  }
  fn
}

layer_implements <- function(layer, language = "r") {
  !isTRUE(attr(layer_render_fn(layer, language), "aa_stub"))
}

# ---- Predicate AST ---------------------------------------------------------

#' Structured predicate carried alongside a filter's text
#'
#' @description Filter args (`filter`, `restrict_filter`) are raw expression
#'   strings that today are pasted into generated R verbatim. That is an R leak:
#'   another language cannot re-emit them and cannot see which columns and
#'   PARAMCD values they reference. `step_predicates()` returns, for one step,
#'   every registry-declared predicate arg as a triple of `arg`, the original
#'   `text`, and a language-neutral `ast`. The IR schema is untouched - the AST
#'   is derived from the registry plus the step args, never stored in the IR.
#' @param step An `aa_step`-shaped list (`layer`, `args`).
#' @return Named list; one entry per predicate arg present on the step, each a
#'   list of `arg`, `text` and `ast`.
#' @noRd
step_predicates <- function(step) {
  layer <- aa_layers()[[step$layer]]
  if (is.null(layer)) return(list())
  out <- list()
  for (nm in layer$predicates) {
    text <- step$args[[nm]]
    if (is.null(text) || !is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) next
    out[[nm]] <- list(arg = nm, text = text, ast = parse_predicate(text))
  }
  out
}

# The accepted filter sublanguage is fenced by safe_expression(): names,
# scalar literals, parentheses, arithmetic, comparison and logical operators.
# The AST mirrors exactly that and nothing more.
parse_predicate <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || !nzchar(text)) return(NULL)
  parsed <- tryCatch(parse(text = text), error = function(e) NULL)
  if (is.null(parsed) || length(parsed) == 0L) return(NULL)
  expr <- if (length(parsed) == 1L) parsed[[1]] else as.call(c(list(as.name("{")), as.list(parsed)))
  predicate_node(expr)
}

predicate_node <- function(x) {
  if (is.call(x)) {
    head <- x[[1]]
    rest <- as.list(x)[-1]
    return(list(
      type = "call",
      op = if (is.name(head)) as.character(head) else NA_character_,
      head = if (is.name(head)) NULL else predicate_node(head),
      arg_names = if (is.null(names(rest))) rep("", length(rest)) else names(rest),
      args = unname(lapply(rest, predicate_node))
    ))
  }
  if (is.name(x)) return(list(type = "name", name = as.character(x)))
  if (is.atomic(x) && length(x) == 1L) return(list(type = "literal", value = x, mode = mode(x)))
  list(type = "opaque", text = paste(deparse(x), collapse = " "))
}

PREDICATE_TIGHT_OPS <- c("^", ":", "$", "@", "::", ":::")

#' Reconstruct predicate text from its AST in one target language
#'
#' @description Inverse of [parse_predicate()] for the accepted sublanguage: a
#'   canonical-form filter round-trips byte-identically. Only `"r"` is
#'   implemented; other languages error by name, exactly like the layer render
#'   stubs, so a renderer cannot silently emit R syntax into a SAS program.
#' @param node A node produced by [parse_predicate()].
#' @param language One of `AA_LANGUAGES`.
#' @return A single expression string.
#' @noRd
deparse_predicate <- function(node, language = "r") {
  if (!identical(language, "r")) {
    stop("NotImplemented: predicate deparsing has no ", language, " renderer", call. = FALSE)
  }
  if (is.null(node)) return(NA_character_)
  switch(
    node$type,
    name = node$name,
    literal = if (is.character(node$value)) quote_literal(node$value, language)
      else if (is.logical(node$value)) as.character(node$value)
      else format(node$value, trim = TRUE, scientific = FALSE, digits = 17),
    opaque = node$text,
    call = deparse_predicate_call(node, language),
    stop("unknown predicate node type", call. = FALSE)
  )
}

deparse_predicate_call <- function(node, language) {
  parts <- vapply(node$args, deparse_predicate, character(1), language = language)
  op <- node$op
  if (!is.na(op) && identical(op, "(") && length(parts) == 1L) return(paste0("(", parts, ")"))
  if (!is.na(op) && op %in% c("-", "+", "!") && length(parts) == 1L) return(paste0(op, parts))
  if (!is.na(op) && length(parts) == 2L && !grepl("^[A-Za-z._]", op)) {
    sep <- if (op %in% PREDICATE_TIGHT_OPS) "" else " "
    return(paste0(parts[1], sep, op, sep, parts[2]))
  }
  named <- ifelse(nzchar(node$arg_names), paste0(node$arg_names, " = ", parts), parts)
  head <- if (is.null(node$head)) op else deparse_predicate(node$head, language)
  paste0(head, "(", paste(named, collapse = ", "), ")")
}

# Column references of a predicate or formula, in order of appearance. Matches
# all.vars() over the accepted sublanguage; `$`/`@` descend only on the left.
predicate_names <- function(node) {
  out <- character()
  walk <- function(n) {
    if (is.null(n) || !is.list(n) || is.null(n$type)) return(invisible(NULL))
    if (identical(n$type, "name")) {
      out <<- c(out, n$name)
    } else if (identical(n$type, "call")) {
      if (!is.null(n$head)) walk(n$head)
      if (!is.na(n$op) && n$op %in% c("$", "@")) {
        if (length(n$args)) walk(n$args[[1]])
      } else {
        for (a in n$args) walk(a)
      }
    }
    invisible(NULL)
  }
  walk(node)
  unique(out)
}

# PARAMCD literals compared for equality anywhere in the predicate.
predicate_paramcd_values <- function(node) {
  visit <- function(n) {
    if (is.null(n) || !is.list(n) || !identical(n$type, "call")) return(character())
    if (identical(n$op, "==") && length(n$args) == 2L) {
      a <- n$args[[1]]; b <- n$args[[2]]
      if (identical(a$type, "name") && identical(a$name, "PARAMCD") &&
          identical(b$type, "literal") && is.character(b$value)) return(b$value)
      if (identical(b$type, "name") && identical(b$name, "PARAMCD") &&
          identical(a$type, "literal") && is.character(a$value)) return(a$value)
    }
    unlist(lapply(n$args, visit), use.names = FALSE)
  }
  unique(visit(node))
}

tocharacter_lgl <- function(x) toupper(as.character(x))

#' Names of all registered derivation layers
#'
#' @description Convenience accessor over [aa_layers()] returning the allowed
#'   `layer` vocabulary.
#' @title Layer names
#' @return Character vector of layer names.
#' @export
layer_names <- function() names(aa_layers())

#' Human-readable documentation of every layer
#'
#' @description Renders each registry entry (function, label, args, required
#'   args) into a compact text card. These cards are embedded verbatim in the
#'   LLM system prompt built by [build_system_prompt()].
#' @title Layer documentation cards
#' @return Named character vector, one documentation block per layer.
#' @export
layer_docs <- function() {
  layers <- aa_layers()
  vapply(names(layers), function(nm) {
    l <- layers[[nm]]
    arg_txt <- paste(
      vapply(names(l$args), function(a) paste0("    - ", a, ": ", l$args[[a]]), character(1)),
      collapse = "\n"
    )
    paste0(
      "layer: ", nm, "\n",
      "  fn: ", l$fn, "\n",
      "  label: ", l$label, "\n",
      "  args:\n", arg_txt, "\n",
      "  required: ", paste(l$required, collapse = ", ")
    )
  }, character(1))
}

admiral_required_layers <- function(ir) {
  layers <- aa_layers()
  used <- unique(unlist(lapply(ir, function(v) {
    vapply(v$steps, function(s) if (is.null(s$layer)) NA_character_ else s$layer, character(1))
  })))
  used <- intersect(used[!is.na(used)], names(layers))
  mins <- vapply(used, function(nm) layers[[nm]]$admiral_min %||% NA_character_, character(1))
  mins <- mins[!is.na(mins)]
  if (length(mins) == 0) return(NULL)
  versions <- package_version(mins)
  req <- max(versions)
  list(version = req, layers = sort(names(mins)[versions == req]))
}

#' Check admiral version compatibility of an IR
#'
#' @description Compares the minimum admiral version required by the layers
#'   used in the IR against the installed admiral version. Absence of admiral
#'   is not an error: rendering is static and only execution is blocked.
#' @title admiral compatibility check
#' @param ir List of `aa_variable_ir` objects.
#' @param installed admiral version to compare against; defaults to the
#'   installed `utils::packageVersion("admiral")` (NA-safe when missing).
#' @return A character vector of problem messages (empty when compatible); the
#'   vector carries a `note` attribute when admiral is not installed.
#' @export
check_admiral_compat <- function(ir, installed = NA) {
  assert_ir_shape(ir, allow_empty = TRUE)
  if (!is.null(installed) && !inherits(installed, "numeric_version") &&
      !(is.character(installed) && scalar_text(installed) && nzchar(installed)) &&
      !(is.atomic(installed) && is.null(dim(installed)) && length(installed) == 1L && is.na(installed))) {
    stop("installed must be one version string, package_version, NA or NULL", call. = FALSE)
  }
  if (inherits(installed, "numeric_version") && length(installed) != 1L) stop("installed must be one version", call. = FALSE)
  if (length(installed) == 1 && is.na(installed)) {
    installed <- tryCatch(utils::packageVersion("admiral"), error = function(e) NULL)
  }
  if (is.null(installed)) {
    return(structure(
      character(),
      note = "admiral is not installed; rendering is static, absence only blocks execution"
    ))
  }
  inst <- if (is.character(installed)) tryCatch(package_version(installed), error = function(e) stop("installed must be a valid version string", call. = FALSE)) else installed
  req <- admiral_required_layers(ir)
  if (is.null(req)) return(character())
  if (inst < req$version) {
    return(sprintf(
      "admiral %s or newer is required by layer(s) %s, but admiral %s is installed; upgrade admiral to run this program",
      as.character(req$version),
      paste(req$layers, collapse = ", "),
      as.character(inst)
    ))
  }
  character()
}
