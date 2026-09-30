exprs_chr <- function(x) paste(x, collapse = ", ")

q_chr <- function(x) vapply(x, function(value) as.character(jsonlite::toJSON(enc2utf8(value), auto_unbox = TRUE)), character(1), USE.NAMES = FALSE)

arg_line <- function(name, value, quoted = FALSE) {
  if (is.null(value) || length(value) == 0 || all(is.na(value))) return(NULL)
  val <- if (quoted) q_chr(value) else as.character(value)
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
#'   `args`, `required`, `rank`, `checks`, `inputs`, and `render`.
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
          q_chr(args$literal)
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
      render = function(args, dataset) {
        parts <- list(
          paste0("dataset_add = ", args$dataset_add),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          if (!is.null(args$order)) paste0("order = exprs(", exprs_chr(args$order), ")"),
          paste0("mode = ", q_chr(args$mode)),
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
        time_imputation = "character, 'first' or 'last' (dtm only, optional)"
      ),
      required = c("target", "dtc", "output_class", "highest_imputation", "date_imputation"),
      rank = 2,
      checks = c("imputation_flag", "not_all_na"),
      admiral_min = "1.5.0",
      render = function(args, dataset) {
        prefix <- sub("(DTM|DT)$", "", args$target)
        parts <- list(
          paste0("new_vars_prefix = ", q_chr(prefix)),
          paste0("dtc = ", args$dtc),
          paste0("highest_imputation = ", q_chr(args$highest_imputation)),
          paste0("date_imputation = ", q_chr(args$date_imputation))
        )
        if (identical(args$output_class, "dtm") && !is.null(args$time_imputation)) {
          parts <- c(parts, list(paste0("time_imputation = ", q_chr(args$time_imputation))))
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
      render = function(args, dataset) {
        add_one <- if (is.null(args$add_one)) FALSE else isTRUE(args$add_one)
        trunc_out <- if (is.null(args$trunc_out)) identical(args$out_unit, "years") else isTRUE(args$trunc_out)
        parts <- list(
          paste0("new_var = ", args$target),
          paste0("start_date = ", args$start),
          paste0("end_date = ", args$end),
          paste0("out_unit = ", q_chr(args$out_unit)),
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
      render = function(args, dataset) {
        parts <- list(
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          paste0("parameters = c(", exprs_chr(vapply(args$parameters, q_chr, character(1))), ")"),
          paste0(
            "set_values_to = exprs(AVAL = ", args$formula,
            ", PARAMCD = ", q_chr(args$paramcd),
            ", PARAM = ", q_chr(args$param),
            if (!is.null(args$avalu)) paste0(", AVALU = ", q_chr(args$avalu)) else "",
            ")"
          ),
          if (!is.null(args$filter)) paste0("filter = ", args$filter),
          if (!is.null(args$constant_parameters)) {
            paste0("constant_parameters = c(", exprs_chr(vapply(args$constant_parameters, q_chr, character(1))), ")")
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
      render = function(args, dataset) {
        av <- if (is.null(args$analysis_var)) "AVAL" else args$analysis_var
        parts <- list(
          paste0("dataset_add = ", dataset),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          paste0(
            "set_values_to = exprs(PARAMCD = ", q_chr(args$paramcd),
            ", PARAM = ", q_chr(args$param), ", ",
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
      render = function(args, dataset) {
        tv <- if (is.null(args$true_value)) "Y" else args$true_value
        parts <- list(
          paste0("new_var = ", args$target),
          paste0("by_vars = exprs(", exprs_chr(args$by_vars), ")"),
          paste0("order = exprs(", exprs_chr(args$order), ")"),
          paste0("mode = ", q_chr(args$mode)),
          paste0("true_value = ", q_chr(tv))
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
            "), mode = ", q_chr(args$mode),
            ", true_value = ", q_chr(tv), "),\n",
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
      render = function(args, dataset) {
        right <- if (is.null(args$right)) TRUE else isTRUE(args$right)
        include_lowest <- if (is.null(args$include_lowest)) TRUE else isTRUE(args$include_lowest)
        breaks <- paste(vapply(args$breaks, function(x) format(x, trim = TRUE, scientific = FALSE, digits = 17), character(1)), collapse = ", ")
        labels <- paste(vapply(args$labels, q_chr, character(1)), collapse = ", ")
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
  lapply(registry, function(layer) {
    layer$args$on <- "character, dataset object name for this step (optional)"
    layer
  })
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
  if (length(installed) == 1 && is.na(installed)) {
    installed <- tryCatch(utils::packageVersion("admiral"), error = function(e) NULL)
  }
  if (is.null(installed)) {
    return(structure(
      character(),
      note = "admiral is not installed; rendering is static, absence only blocks execution"
    ))
  }
  inst <- if (is.character(installed)) package_version(installed) else installed
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
