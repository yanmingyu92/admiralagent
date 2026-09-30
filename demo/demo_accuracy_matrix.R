for (f in list.files(file.path("admiralagent", "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}
library(admiral)
library(dplyr)
library(rlang)
library(pharmaversesdtm)
library(pharmaverseadam)
data("dm"); data("ex"); data("vs")
data("adsl", package = "pharmaverseadam")

cat("################ PART 1: spec source matrix ################\n")
spec_sources <- list(
  p21_mock = system.file("extdata", "p21_mock.xlsx", package = "metacore"),
  mock_spec = system.file("extdata", "mock_spec.xlsx", package = "metacore"),
  sdtm_pilot = system.file("extdata", "SDTM_spec_CDISC_pilot.xlsx", package = "metacore"),
  pilot1_define = file.path("cdisc_data", "pilot1", "m5", "datasets",
                            "rconsortiumpilot1", "analysis", "adam", "datasets", "define.xml")
)
cover_rows <- list()
for (nm in names(spec_sources)) {
  spec <- tryCatch(
    if (grepl("\\.xml$", spec_sources[[nm]])) read_define(spec_sources[[nm]]) else read_spec(spec_sources[[nm]]),
    error = function(e) NULL
  )
  if (is.null(spec)) {
    cover_rows[[nm]] <- data.frame(source = nm, datasets = NA, variables = NA,
                                   classified = NA, needs_human = NA, note = "parse failed")
    next
  }
  ds_list <- intersect(unique(spec$dataset), c("ADSL", "adsl"))
  if (length(ds_list) == 0) {
    cover_rows[[nm]] <- data.frame(source = nm, datasets = paste(unique(spec$dataset), collapse = ","),
                                   variables = nrow(spec), classified = NA, needs_human = NA,
                                   note = "no ADSL")
    next
  }
  ir <- tryCatch(classify_variables(spec, ds_list[1], backend = "rules"), error = function(e) NULL)
  if (is.null(ir)) {
    cover_rows[[nm]] <- data.frame(source = nm, datasets = ds_list[1], variables = nrow(spec),
                                   classified = NA, needs_human = NA, note = "classify error")
    next
  }
  nh <- sum(vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
  cover_rows[[nm]] <- data.frame(
    source = nm, datasets = ds_list[1], variables = length(ir),
    classified = length(ir) - nh, needs_human = nh,
    note = if (length(validate_ir(ir)) == 0) "IR gate PASS" else "IR gate FAIL"
  )
}
cat("\n=== Spec source coverage (rules backend) ===\n")
print(do.call(rbind, cover_rows), row.names = FALSE)

cat("\n################ PART 2: execution + accuracy matrix ################\n")
spec <- mock_spec_adsl()
ir <- classify_variables(spec, "ADSL", backend = "rules")
stopifnot(length(validate_ir(ir)) == 0)

exec_env <- new.env(parent = globalenv())
exec_env$ADSL <- dm
exec_env$dm <- dm
exec_env$ex <- ex
exec_env$vs <- vs |> dplyr::mutate(AVAL = VSSTRESN, PARAMCD = VSTESTCD)

exec_status <- list()
for (v in ir) {
  vn <- v$variable
  if (isTRUE(v$needs_human)) {
    exec_status[[vn]] <- "REVIEW"
    next
  }
  res <- tryCatch({
    eval(parse(text = render_variable(v)), envir = exec_env)
    "EXECUTED"
  }, error = function(e) paste0("ERROR"))
  exec_status[[vn]] <- res
}

bmi_idx <- which(vapply(ir, function(x) x$variable == "BMIBL", logical(1)))
ir2 <- ir
ir2[[bmi_idx]]$steps[[1]]$args$filter <- "VISIT == 'SCREENING 1'"
exec_env$ADSL$BMIBL <- NULL
exec_env$vs <- exec_env$vs[exec_env$vs$PARAMCD != "BMI" | is.na(exec_env$vs$PARAMCD), ]
bmi_res <- tryCatch({
  eval(parse(text = render_variable(ir2[[bmi_idx]])), envir = exec_env)
  "EXECUTED(revised)"
}, error = function(e) "ERROR")
exec_status[["BMIBL"]] <- bmi_res

pilot1_adsl <- haven::read_xpt(file.path(
  "cdisc_data", "pilot1", "m5", "datasets", "rconsortiumpilot1",
  "analysis", "adam", "datasets", "adsl.xpt"
))

compare_col <- function(ours, oracle, var, join_by = "USUBJID", type = c("date", "char", "num")) {
  type <- match.arg(type)
  if (!var %in% names(ours)) return(list(value_match = NA, na_agree = NA, n = 0,
                                         note = "not in generated ADSL"))
  if (!var %in% names(oracle)) return(list(value_match = NA, na_agree = NA, n = 0,
                                           note = "not in oracle"))
  if (identical(var, join_by)) {
    a <- ours[[var]]; b <- oracle[[var]]
    return(list(value_match = mean(a %in% b), na_agree = 1, n = length(a), note = "set overlap"))
  }
  m <- merge(ours[, c(join_by, var), drop = FALSE],
             oracle[, c(join_by, var), drop = FALSE], by = join_by, suffixes = c(".o1", ".o2"))
  a <- m[[paste0(var, ".o1")]]
  b <- m[[paste0(var, ".o2")]]
  if (type == "date") {
    a <- as.Date(a); b <- as.Date(b)
  } else if (type == "num") {
    a <- as.numeric(a); b <- as.numeric(b)
    both <- !is.na(a) & !is.na(b)
    return(list(
      value_match = mean(both & abs(a - b) < 0.5),
      na_agree = mean(is.na(a) == is.na(b)),
      n = nrow(m),
      note = sprintf("tol 0.5 | mean|diff|=%.3f", mean(abs(a[both] - b[both])))
    ))
  }
  eq <- !is.na(a) & !is.na(b) & a == b
  list(value_match = mean(eq), na_agree = mean(is.na(a) == is.na(b)), n = nrow(m), note = "")
}

ours <- exec_env$ADSL
vars_spec <- list(
  list(var = "STUDYID", type = "char"),
  list(var = "USUBJID", type = "char"),
  list(var = "TRT01P", type = "char"),
  list(var = "TRTSDTM", type = "date"),
  list(var = "TRTEDTM", type = "date"),
  list(var = "AGE", type = "num"),
  list(var = "BMIBL", type = "num")
)
rows <- list()
for (vs in vars_spec) {
  v <- vs$var
  st <- exec_status[[v]]
  r_adam <- compare_col(ours, adsl, v, type = vs$type)
  r_p1 <- compare_col(ours, pilot1_adsl, v, type = vs$type)
  rows[[v]] <- data.frame(
    variable = v,
    exec = st,
    adam_match = ifelse(is.na(r_adam$value_match), NA, sprintf("%.1f%%", 100 * r_adam$value_match)),
    adam_na_agree = ifelse(is.na(r_adam$na_agree), NA, sprintf("%.1f%%", 100 * r_adam$na_agree)),
    adam_n = r_adam$n,
    pilot1_match = ifelse(is.na(r_p1$value_match), NA, sprintf("%.1f%%", 100 * r_p1$value_match)),
    pilot1_n = r_p1$n,
    note = paste(r_adam$note, r_p1$note)[1],
    stringsAsFactors = FALSE
  )
}
rows[["AGE"]] <- data.frame(
  variable = "AGE", exec = exec_status[["AGE"]],
  adam_match = rows[["AGE"]]$adam_match, adam_na_agree = rows[["AGE"]]$adam_na_agree,
  adam_n = rows[["AGE"]]$adam_n,
  pilot1_match = rows[["AGE"]]$pilot1_match, pilot1_n = rows[["AGE"]]$pilot1_n,
  note = "derivation blocked (BRTHDT/TRTSDT gap); compared dm-native AGE"
)
rows[["AGEGR1"]] <- data.frame(variable = "AGEGR1", exec = exec_status[["AGEGR1"]],
                               adam_match = NA, adam_na_agree = NA, adam_n = NA,
                               pilot1_match = NA, pilot1_n = NA,
                               note = "needs human (breakpoints)")
rows[["RACEN"]] <- data.frame(variable = "RACEN", exec = exec_status[["RACEN"]],
                              adam_match = NA, adam_na_agree = NA, adam_n = NA,
                              pilot1_match = NA, pilot1_n = NA, note = "needs real metacore spec")

acc <- do.call(rbind, rows)
cat("\n=== Accuracy matrix: generated ADSL vs published oracles ===\n")
cat("oracle 1: pharmaverseadam::adsl (306 subj) | oracle 2: pilot1 submitted adsl.xpt (254 subj)\n\n")
print(acc, row.names = FALSE)

outdir <- file.path("admiralagent", "demo", "gen")
if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)
utils::write.csv(acc, file.path(outdir, "accuracy_matrix.csv"), row.names = FALSE)
cat("\nWritten:", file.path(outdir, "accuracy_matrix.csv"), "\n")

val <- run_validation(ours, ir2, quiet = TRUE)
cat("\n=== Validation gate summary ===\n")
cat(sprintf("PASS=%d FAIL=%d MANUAL=%d\n",
            sum(val$status == "PASS"), sum(val$status == "FAIL"), sum(val$status == "MANUAL")))
