#' Classify spec variables into layer IR
#'
#' @description Translates each spec variable's free-text derivation into a
#'   variable IR using the selected backend: `"rules"` runs the built-in
#'   deterministic, zero-dependency keyword classifier (baseline and
#'   fallback); `"llm"` runs the structured-extraction pipeline via
#'   [classify_variables_llm()] (requires an ellmer `chat`).
#' @title Classify spec variables
#' @param spec Spec data frame compatible with [read_spec_df()].
#' @param dataset Dataset name to classify (e.g. `"ADSL"`).
#' @param backend One of `"rules"` or `"llm"`.
#' @param chat ellmer chat object; required when `backend = "llm"`, ignored
#'   otherwise.
#' @return List of `aa_variable_ir` objects, one per spec variable.
#' @export
classify_variables <- function(spec, dataset, backend = c("rules", "llm"), chat = NULL) {
  backend <- match.arg(backend)
  vars <- spec_variables(spec, dataset)
  if (backend == "llm") {
    if (is.null(chat)) {
      stop("backend = 'llm' requires an ellmer chat object, e.g. chat <- ellmer::chat_anthropic()", call. = FALSE)
    }
    return(classify_variables_llm(vars, chat = chat))
  }
  rules_engine(vars)
}

# Unique temp target for imputing a source --DTC on a foreign dataset.
# Two spec variables may impute the SAME source DTC with different modes
# (e.g. TRTSDTM wants EXSTDTC 'first', TRTEDTM wants it 'last'); a bare
# <stem>DTM target would collide on the source dataset. The name embeds the
# consuming variable so each imputation lands in its own column, and it ends
# in DTM/DT so the impute_dtc layer's `new_vars_prefix` round-trips to the
# exact same column name (target == column actually created by admiral).
temp_target <- function(dtc, for_variable, mode = c("first", "last"),
                        output_class = c("dtm", "dt")) {
  mode <- match.arg(mode)
  output_class <- match.arg(output_class)
  stem <- gsub("DTC$", "", toupper(dtc))
  suffix <- sub("(DTM|DT)$", "", toupper(for_variable))
  if (nchar(suffix) < 4) suffix <- toupper(for_variable)
  suffix <- substr(suffix, 1, 6)
  paste0(stem, "_", suffix, toupper(output_class))
}

rules_engine <- function(vars) {
  lapply(seq_len(nrow(vars)), function(i) {
    row <- vars[i, ]
    text <- tolower(paste(row$origin, row$derivation))
    steps <- list()
    rationale <- character()

    if (grepl("categor|age group|categories", text)) {
      out <- new_variable_ir(
        dataset = row$dataset, variable = row$variable, steps = list(),
        spec_origin = row$derivation, needs_human = TRUE,
        rationale = "rule: categorisation breakpoints require human decision"
      )
      return(out)
    }

    rf_match <- regmatches(text, regexpr("rfstdtc|rfendtc", text))
    if (length(rf_match) > 0 && nzchar(rf_match[1]) && grepl("(DTM|DT)$", row$variable)) {
      dtc_var <- toupper(rf_match[1])
      steps <- list(new_step("impute_dtc", list(
        target = row$variable, dtc = dtc_var,
        output_class = if (grepl("DTM$", row$variable)) "dtm" else "dt", highest_imputation = "M",
        date_imputation = if (identical(dtc_var, "RFSTDTC")) "first" else "last"
      )))
      rationale <- paste0("rule: impute DM ", dtc_var, " directly (pilot ADSL convention)")
      return(new_variable_ir(
        dataset = row$dataset, variable = row$variable, steps = steps,
        spec_origin = row$derivation, confidence = 1,
        needs_human = FALSE, rationale = rationale
      ))
    }

    if (length(rf_match) && nzchar(rf_match[1]) && !grepl("DTC$", row$variable)) {
      return(new_variable_ir(row$dataset, row$variable, spec_origin = row$derivation,
        needs_human = TRUE, rationale = "rule: nonstandard date target requires human mapping to DT/DTM"))
    }

    srcvar <- regmatches(row$derivation, regexpr("^[A-Z][A-Z0-9]*\\.[A-Z][A-Z0-9]*$", row$derivation))
    if (length(srcvar) > 0 && nzchar(srcvar[1])) {
      from_var <- sub("^.*\\.", "", srcvar[1])
      steps <- list(new_step("assign", list(target = row$variable, from = from_var)))
      return(new_variable_ir(
        dataset = row$dataset, variable = row$variable, steps = steps,
        spec_origin = row$derivation, confidence = 1,
        needs_human = FALSE,
        rationale = paste0("rule: predecessor copy from ", srcvar[1])
      ))
    }

    # This exact explanatory clause states equivalence, not an extra derivation.
    copy_text <- sub(", i[.]e[.], no difference between actual and randomized treatment in this study[.]$", "", row$derivation)
    selfdef <- regmatches(copy_text, regexpr("^[A-Z][A-Z0-9_]*=[A-Z][A-Z0-9_]*$", copy_text))
    if (length(selfdef) > 0 && nzchar(selfdef[1])) {
      parts <- strsplit(selfdef[1], "=", fixed = TRUE)[[1]]
      if (identical(parts[1], row$variable) && !identical(parts[2], row$variable)) {
        steps <- list(new_step("assign", list(target = row$variable, from = parts[2])))
        return(new_variable_ir(
          dataset = row$dataset, variable = row$variable, steps = steps,
          spec_origin = row$derivation, confidence = 1,
          needs_human = FALSE,
          rationale = paste0("rule: self-referential assignment ", selfdef[1])
        ))
      }
    }

    if (grepl("reference range|low if", text) && grepl("normal", text) && grepl("high", text)) {
      rng_nums <- sort(unique(suppressWarnings(as.numeric(
        regmatches(text, gregexpr("[0-9]+([.][0-9]+)?", text))[[1]])
      )))
      rng_nums <- rng_nums[is.finite(rng_nums)]
      if (length(rng_nums) >= 2) {
        steps <- list(new_step("categorize", list(
          target = row$variable, from = "AVAL",
          breaks = c(0, rng_nums, Inf), labels = c("LOW", "NORMAL", "HIGH")
        )))
        rationale <- paste0(
          "rule: numeric reference ranges parsed from spec (",
          paste(rng_nums, collapse = "/"),
          "); global cut on AVAL, parameter-specific scoping needs human refinement"
        )
      }
    } else if (grepl("time to first", text) && grepl("aestdtc", text)) {
      tmp <- temp_target("AESTDTC", row$variable, mode = "first")
      steps <- list(
        new_step("impute_dtc", list(
          on = "ae", target = tmp, dtc = "AESTDTC",
          output_class = "dtm", highest_imputation = "M", date_imputation = "first"
        )),
        new_step("merge_var", list(
          target = tmp, source = tmp, dataset_add = "ae",
          by_vars = c("STUDYID", "USUBJID"), order = tmp, mode = "first"
        )),
        new_step("duration", list(
          target = row$variable, start = "TRTSDTM", end = tmp,
          out_unit = "days", add_one = FALSE, trunc_out = FALSE
        ))
      )
      rationale <- paste0(
        "rule: impute AESTDTC to datetime on ae, merge earliest per subject, ",
        "duration in days from TRTSDTM (derive_vars_duration accepts POSIXct DTM endpoints)"
      )
    } else if (grepl("lookup", text)) {
      by_var <- if (!is.na(row$source_variable) && nzchar(row$source_variable)) {
        row$source_variable
      } else {
        "VSTESTCD"
      }
      steps <- list(new_step("lookup_join", list(
        target = row$variable, source = row$variable,
        dataset_lookup = "vslk", by_vars = by_var
      )))
      rationale <- paste0("rule: lookup join on ", by_var, " via lookup dataset vslk")
    } else if (grepl("ablfl|baseline flag", text) && grepl("last", text) && grepl("before", text)) {
      flag_by <- if (grepl("parameter", text)) c("USUBJID", "PARAMCD") else "USUBJID"
      restrict <- if (grepl("on or before", text)) "ADTM <= TRTSDTM" else "ADTM < TRTSDTM"
      steps <- list(new_step("extreme_flag", list(
        target = row$variable, by_vars = flag_by, order = "ADTM", mode = "last",
        true_value = "Y", restrict_filter = restrict
      )))
      rationale <- paste0(
        "rule: flag last pre-treatment record (", restrict, ") within ",
        paste(flag_by, collapse = "+")
      )
    } else if (grepl("baseline value|aval of the record with ablfl", text)) {
      base_by <- if (grepl("parameter", text)) c("USUBJID", "PARAMCD") else "USUBJID"
      steps <- list(new_step("merge_var", list(
        target = row$variable, source = "AVAL", dataset_add = row$dataset,
        by_vars = base_by, order = "ADTM", mode = "first", filter = "ABLFL == 'Y'"
      )))
      rationale <- paste0(
        "rule: self-merge AVAL of the ABLFL = Y record within ",
        paste(base_by, collapse = "+")
      )
    } else if (grepl("percent change", text)) {
      steps <- list(new_step("compute_var", list(
        target = row$variable, formula = "100 * AVAL / BASE - 100"
      )))
      rationale <- paste0(
        "rule: percent change column-wise; parenthesis-free rewrite of ",
        "100 * (AVAL - BASE) / BASE because compute_var rejects parentheses"
      )
    } else if (grepl("change from baseline|aval - base", text)) {
      steps <- list(new_step("compute_var", list(
        target = row$variable, formula = "AVAL - BASE"
      )))
      rationale <- "rule: column arithmetic change from baseline"
    } else if (grepl("body mass index|bmi", text)) {
      steps <- list(
        new_step("compute_param", list(
          on = "vs",
          paramcd = "BMI", param = "Body Mass Index (kg/m2)", avalu = "kg/m2",
          parameters = c("WEIGHT", "HEIGHT"),
          formula = "AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",
          by_vars = c("STUDYID", "USUBJID"),
          filter = if (grepl("baseline", text)) "VISIT == 'BASELINE'" else NULL
        )),
        new_step("merge_var", list(
          target = row$variable, source = "AVAL", dataset_add = "vs",
          by_vars = c("STUDYID", "USUBJID"), mode = "first",
          filter = "PARAMCD == 'BMI'"
        ))
      )
      rationale <- "rule: BMI formula from WEIGHT/HEIGHT parameters, then merged to ADSL"
    } else if (grepl("impute", text) && grepl("earliest|first", text)) {
      tmp <- temp_target("EXSTDTC", row$variable, mode = "first")
      steps <- list(
        new_step("impute_dtc", list(
          on = "ex", target = tmp, dtc = "EXSTDTC",
          output_class = "dtm", highest_imputation = "M", date_imputation = "first"
        )),
        new_step("merge_var", list(
          target = row$variable, source = tmp, dataset_add = "ex",
          by_vars = c("STUDYID", "USUBJID"), order = tmp, mode = "first",
          filter = if (grepl("exdose", text)) "EXDOSE > 0" else NULL
        ))
      )
      rationale <- "rule: impute source --DTC first, then merge first record by dose filter"
    } else if (grepl("impute", text) && grepl("latest|last", text)) {
      tmp <- temp_target("EXSTDTC", row$variable, mode = "last")
      steps <- list(
        new_step("impute_dtc", list(
          on = "ex", target = tmp, dtc = "EXSTDTC",
          output_class = "dtm", highest_imputation = "M", date_imputation = "last"
        )),
        new_step("merge_var", list(
          target = row$variable, source = tmp, dataset_add = "ex",
          by_vars = c("STUDYID", "USUBJID"), order = tmp, mode = "last",
          filter = if (grepl("exdose", text)) "EXDOSE > 0" else NULL
        ))
      )
      rationale <- "rule: impute source --DTC (last), then merge last record by dose filter"
    } else if (grepl("age in years|years between", text)) {
      steps <- list(new_step("duration", list(
        target = row$variable, start = "BRTHDT", end = "TRTSDT",
        out_unit = "years", add_one = FALSE, trunc_out = TRUE
      )))
      rationale <- "rule: duration in truncated years between birth and treatment start"
    } else if (grepl("codelist", text)) {
      from_var <- sub(".*from ([a-z0-9]+) using.*", "\\1", text)
      if (!grepl("^[a-z0-9]+$", from_var) || from_var == text) from_var <- "RACE"
      from_var <- toupper(from_var)
      steps <- list(new_step("codelist_var", list(
        target = row$variable, from = from_var, decode_to_code = TRUE
      )))
      rationale <- paste0("rule: numeric code via metacore codelist from ", from_var)
    } else if (grepl("copied|directly from", text)) {
      from_var <- row$source_variable
      if (is.na(from_var) || !nzchar(from_var)) from_var <- row$variable
      steps <- list(new_step("assign", list(target = row$variable, from = from_var)))
      rationale <- "rule: direct copy from source variable"
    }

    if (length(steps) == 0) {
      new_variable_ir(
        dataset = row$dataset, variable = row$variable, steps = list(),
        spec_origin = row$derivation, needs_human = TRUE,
        rationale = "rule: no matching pattern, routed to human review"
      )
    } else {
      new_variable_ir(
        dataset = row$dataset, variable = row$variable, steps = steps,
        spec_origin = row$derivation, confidence = 1,
        needs_human = FALSE, rationale = paste(rationale, collapse = "; ")
      )
    }
  })
}
