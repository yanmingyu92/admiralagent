# ==============================================================================
# FIRST-EVER real-spec end-to-end run:
#   pilot1 define.xml spec text -> classify (rules) -> validate -> render ->
#   execute against pilot SDTM -> accuracy vs pilot1 submitted adsl.xpt oracle
#
# Run from the repository job root:
#   Rscript admiralagent/demo/demo_define_real.R
# ==============================================================================
for (f in list.files(file.path("admiralagent", "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}
library(admiral)
library(dplyr)
library(rlang)
library(pharmaversesdtm)
data("dm"); data("ex"); data("vs"); data("ae")

p1_define <- file.path("cdisc_data", "pilot1", "m5", "datasets",
                       "rconsortiumpilot1", "analysis", "adam", "datasets", "define.xml")
p1_adsl_xpt <- file.path("cdisc_data", "pilot1", "m5", "datasets",
                         "rconsortiumpilot1", "analysis", "adam", "datasets", "adsl.xpt")
if (!file.exists(p1_define)) stop("pilot1 define.xml not found: ", p1_define)

cat("################ PART 1: read_define(pilot1 define.xml) ################\n")
spec <- read_define(p1_define)
adsl_spec <- spec[spec$dataset == "ADSL", ]
cat(sprintf("datasets in define: %d | total variables: %d\n",
            length(unique(spec$dataset)), nrow(spec)))
cat(sprintf("ADSL: %d variables | %d with derivation text | %d with codelist_oid\n",
            nrow(adsl_spec),
            sum(!is.na(adsl_spec$derivation) & nzchar(trimws(adsl_spec$derivation))),
            sum(!is.na(adsl_spec$codelist_oid))))
cover <- data.frame(
  origin = names(table(adsl_spec$origin)),
  n_vars = as.integer(table(adsl_spec$origin)),
  n_with_derivation = as.integer(table(
    adsl_spec$origin[!is.na(adsl_spec$derivation) & nzchar(trimws(adsl_spec$derivation))]
  )),
  stringsAsFactors = FALSE
)
cat("\n=== ADSL derivation coverage by origin ===\n")
print(cover, row.names = FALSE)
cat("\nSample derivations (first 8):\n")
for (i in seq_len(min(8, nrow(adsl_spec)))) {
  cat(sprintf("  %-9s %s\n", adsl_spec$variable[[i]],
              substr(adsl_spec$derivation[[i]], 1, 90)))
}

cat("\n################ PART 2: classify (rules) + gate + dependency ################\n")
ir <- classify_variables(spec, "ADSL", backend = "rules")
gate <- validate_ir(ir)
cat(sprintf("IR gate problems: %d %s\n", length(gate),
            if (length(gate)) paste(gate, collapse = " | ") else "(PASS)"))
nh <- sum(vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
cat(sprintf("classified: %d | needs_human: %d\n", length(ir) - nh, nh))
dep <- ir_dependency_report(ir, known_columns = names(dm))
cat(sprintf("dependency report rows (unresolved inputs): %d\n", nrow(dep)))
if (nrow(dep) > 0) print(dep, row.names = FALSE)

cat("\n################ PART 3: execute against pilot SDTM ################\n")
vs_bds <- vs |> dplyr::mutate(AVAL = VSSTRESN, PARAMCD = VSTESTCD)
cat("[demo] vs adapted to BDS shape (AVAL/PARAMCD); dm is the ADSL base\n")

# codelists straight from the define CodeLists (stretch); RACE/RACEN/ARM carry
# numeric<->decode pairs in this submission define
define_codelists <- function(path, wanted = c("RACEN", "RACE", "ARM")) {
  if (!requireNamespace("xml2", quietly = TRUE)) return(list())
  doc <- xml2::read_xml(path)
  cls <- xml2::xml_find_all(doc, "//*[local-name()='CodeList']")
  out <- list()
  for (cl in cls) {
    nm <- xml2::xml_attr(cl, "Name")
    if (!nm %in% wanted || is.na(nm)) next
    items <- xml2::xml_find_all(cl, "./*[local-name()='CodeListItem']")
    if (length(items) == 0) next
    coded <- xml2::xml_attr(items, "CodedValue")
    decode <- vapply(items, function(it) {
      tt <- xml2::xml_find_first(
        it, "./*[local-name()='Decode']/*[local-name()='TranslatedText']"
      )
      if (inherits(tt, "xml_missing")) NA_character_ else trimws(xml2::xml_text(tt))
    }, character(1))
    numeric_typed <- xml2::xml_attr(cl, "DataType") %in% c("integer", "float")
    num <- if (numeric_typed) suppressWarnings(as.numeric(coded)) else suppressWarnings(as.numeric(decode))
    lab <- if (numeric_typed) decode else coded
    keep <- !is.na(num) & !is.na(lab)
    if (any(keep)) out[[nm]] <- data.frame(code = num[keep], decode = lab[keep],
                                           stringsAsFactors = FALSE)
  }
  out
}
codelists <- tryCatch(define_codelists(p1_define), error = function(e) {
  message("define CodeList extraction failed (", conditionMessage(e),
          "); falling back to codelist_from_data('RACE', dm)")
  list()
})
if (length(codelists) == 0) {
  codelists <- list(RACE = codelist_from_data("RACE", dm))
  cat("[demo] codelists: RACE from dm (sequential codes, NOT the define codes)\n")
} else {
  cat(sprintf("[demo] codelists from define: %s\n", paste(names(codelists), collapse = ", ")))
}
spec_mc <- adsl_spec
spec_mc$codelist <- sub("^CL\\.", "", spec_mc$codelist_oid)
mc <- tryCatch(mock_metacore(spec_mc, codelists = codelists),
               error = function(e) NULL)

res <- execute_ir(
  ir,
  sources = list(base = dm, dm = dm, ex = ex, vs = vs_bds, ae = ae, mc = mc)
)
cat("\n=== Execution status (all 49 ADSL spec variables) ===\n")
status_view <- res$status
status_view$note <- ifelse(nzchar(status_view$note),
                           substr(status_view$note, 1, 80), "")
print(status_view, row.names = FALSE)
cat(sprintf("\nEXECUTED=%d ERROR=%d REVIEW=%d\n",
            sum(res$status$status == "EXECUTED"),
            sum(res$status$status == "ERROR"),
            sum(res$status$status == "REVIEW")))

val <- run_validation(res$adsl, ir, quiet = TRUE)
cat(sprintf("Validation gate on executed ADSL: PASS=%d FAIL=%d MANUAL=%d\n",
            sum(val$status == "PASS"), sum(val$status == "FAIL"),
            sum(val$status == "MANUAL")))

cat("\n################ PART 4: oracle accuracy vs pilot1 submitted adsl.xpt ####\n")
if (!file.exists(p1_adsl_xpt)) {
  cat("pilot1 adsl.xpt not found - skipping oracle comparison\n")
} else {
  p1 <- haven::read_xpt(p1_adsl_xpt)
  cat(sprintf("oracle: %d subjects x %d variables\n", nrow(p1), ncol(p1)))

  compare_var <- function(ours, oracle, var, spec_type) {
    if (!var %in% names(ours)) {
      return(list(match = NA, na_agree = NA, n = 0, note = "not in generated ADSL"))
    }
    if (!var %in% names(oracle)) {
      return(list(match = NA, na_agree = NA, n = 0, note = "not in oracle"))
    }
    if (identical(var, "USUBJID")) {
      a <- ours$USUBJID; b <- oracle$USUBJID
      return(list(match = mean(a %in% b), na_agree = 1, n = length(a),
                  note = "set overlap (join key)"))
    }
    m <- merge(ours[, c("USUBJID", var), drop = FALSE],
               oracle[, c("USUBJID", var), drop = FALSE],
               by = "USUBJID", suffixes = c(".g", ".o"))
    a <- m[[paste0(var, ".g")]]
    b <- m[[paste0(var, ".o")]]
    if (spec_type %in% c("integer", "float")) {
      a <- suppressWarnings(as.numeric(a)); b <- suppressWarnings(as.numeric(b))
      both <- !is.na(a) & !is.na(b)
      return(list(
        match = mean(both & abs(a - b) < 0.5),
        na_agree = mean(is.na(a) == is.na(b)),
        n = nrow(m),
        note = sprintf("num tol 0.5 | mean|diff|=%.3f",
                       if (any(both)) mean(abs(a[both] - b[both])) else NA)
      ))
    }
    if (spec_type == "datetime") {
      a <- as.Date(a); b <- as.Date(b)
    }
    eq <- !is.na(a) & !is.na(b) & a == b
    list(match = mean(eq), na_agree = mean(is.na(a) == is.na(b)),
         n = nrow(m), note = if (spec_type == "datetime") "date as.Date" else "char exact")
  }

  status_map <- setNames(res$status$status, res$status$variable)
  rows <- lapply(seq_len(nrow(adsl_spec)), function(i) {
    v <- adsl_spec$variable[[i]]
    r <- compare_var(res$adsl, p1, v, adsl_spec$type[[i]])
    data.frame(
      variable = v,
      type = adsl_spec$type[[i]],
      exec = ifelse(is.na(status_map[[v]]), NA, status_map[[v]]),
      in_generated = v %in% names(res$adsl),
      oracle_match_pct = ifelse(is.na(r$match), NA, round(100 * r$match, 1)),
      na_agree_pct = ifelse(is.na(r$na_agree), NA, round(100 * r$na_agree, 1)),
      n_compare = r$n,
      note = r$note,
      stringsAsFactors = FALSE
    )
  })
  matrix_df <- do.call(rbind, rows)
  cat("\n=== Accuracy matrix: generated ADSL vs pilot1 adsl.xpt (USUBJID join) ===\n")
  print(matrix_df, row.names = FALSE)

  compared <- matrix_df[!is.na(matrix_df$oracle_match_pct), ]
  cat(sprintf(
    "\nMatrix summary: %d/%d variables comparable | %d at 100%% | %d below 90%%\n",
    nrow(compared), nrow(matrix_df),
    sum(compared$oracle_match_pct == 100, na.rm = TRUE),
    sum(compared$oracle_match_pct < 90, na.rm = TRUE)
  ))

  outdir <- file.path("admiralagent", "demo", "gen")
  if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)
  outcsv <- file.path(outdir, "define_real_matrix.csv")
  utils::write.csv(matrix_df, outcsv, row.names = FALSE)
  cat("Written:", outcsv, "\n")
}

cat("\n################ PART 5: FINDINGS (vocabulary roadmap feed) #############\n")
for (i in seq_len(nrow(res$status))) {
  if (res$status$status[[i]] == "ERROR") {
    cat(sprintf("FINDING-ERROR %s: %s\n", res$status$variable[[i]],
                substr(gsub("[\r\n]+", " ", res$status$note[[i]]), 1, 140)))
  }
}
nh_idx <- which(vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
cat(sprintf("\nFINDINGS: %d of %d ADSL derivation texts the rules engine cannot express.\n",
            length(nh_idx), length(ir)))
cat("Top 10 (verbatim spec text) -> vocabulary roadmap:\n")
for (k in seq_len(min(10, length(nh_idx)))) {
  v <- ir[[nh_idx[[k]]]]
  cat(sprintf("  %2d. %-9s \"%s\"\n", k, v$variable, substr(v$spec_origin, 1, 110)))
}
