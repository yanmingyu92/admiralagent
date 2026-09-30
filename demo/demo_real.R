for (f in list.files(file.path("admiralagent", "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}
library(admiral)
library(dplyr)
library(rlang)
library(pharmaversesdtm)
data("dm"); data("ex"); data("vs")

spec <- mock_spec_adsl()
ir <- classify_variables(spec, "ADSL", backend = "rules")
stopifnot(length(validate_ir(ir)) == 0)

exec_env <- new.env(parent = globalenv())
exec_env$ADSL <- dm
exec_env$dm <- dm
exec_env$ex <- ex
exec_env$vs <- vs |>
  dplyr::mutate(AVAL = VSSTRESN, PARAMCD = VSTESTCD)
cat("[demo glue] vs adapted to BDS shape (AVAL/PARAMCD); the spec assumes BDS-style VS input\n\n")

cat("=== Execute generated blocks against pharmaversesdtm pilot data ===\n")
results <- data.frame(variable = character(), status = character(), note = character(),
                      stringsAsFactors = FALSE)
for (v in ir) {
  if (isTRUE(v$needs_human)) {
    results <- rbind(results, data.frame(variable = v$variable, status = "REVIEW",
                                         note = "needs human decision", stringsAsFactors = FALSE))
    next
  }
  block <- render_variable(v)
  res <- tryCatch({
    eval(parse(text = block), envir = exec_env)
    "EXECUTED"
  }, error = function(e) paste0("ERROR: ", conditionMessage(e)))
  note <- if (startsWith(res, "ERROR")) substr(res, 7, 120) else ""
  results <- rbind(results, data.frame(variable = v$variable, status = res, note = note,
                                       stringsAsFactors = FALSE))
}
print(results, row.names = FALSE)

cat("\n=== Deterministic validation gate on executed ADSL ===\n")
val <- run_validation(exec_env$ADSL, ir, quiet = TRUE)
print(val, row.names = FALSE)
cat(sprintf("\nSummary: PASS=%d FAIL=%d MANUAL=%d\n",
            sum(val$status == "PASS"), sum(val$status == "FAIL"), sum(val$status == "MANUAL")))

show_cols <- intersect(c("USUBJID", "TRT01P", "TRTSDTM", "TRTEDTM", "BMIBL"), names(exec_env$ADSL))
cat("\n=== Derived values (first 6 subjects) ===\n")
print(head(exec_env$ADSL[show_cols]), row.names = FALSE)

cat("\n=== Reviewer loop: BMIBL failed the gate (HEIGHT not collected at BASELINE) ===\n")
cat("Statistician edits the IR (never the generated code):\n")
cat("  HEIGHT/WEIGHT both measured at SCREENING 1 -> restrict filter to SCREENING 1\n\n")
idx <- which(vapply(ir, function(x) x$variable == "BMIBL", logical(1)))
ir2 <- ir
ir2[[idx]]$steps[[1]]$args$filter <- "VISIT == 'SCREENING 1'"
stopifnot(length(validate_ir(ir2)) == 0)
exec_env$ADSL$BMIBL <- NULL
exec_env$vs <- exec_env$vs[exec_env$vs$PARAMCD != "BMI" | is.na(exec_env$vs$PARAMCD), ]
res <- tryCatch({
  eval(parse(text = render_variable(ir2[[idx]])), envir = exec_env)
  "EXECUTED"
}, error = function(e) paste0("ERROR: ", conditionMessage(e)))
cat("Re-execution with revised IR:", res, "\n\n")

val2 <- run_validation(exec_env$ADSL, ir2, quiet = TRUE)
cat("=== BMIBL validation after IR revision ===\n")
print(val2[val2$variable == "BMIBL", ], row.names = FALSE)
cat("\nFinal BMIBL values:\n")
print(head(exec_env$ADSL[, c("USUBJID", "BMIBL")]), row.names = FALSE)
