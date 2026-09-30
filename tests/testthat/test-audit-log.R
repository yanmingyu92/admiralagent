# Audit trail tests: hash-chained log_run() records (21 CFR Part 11 s11.10(e)),
# logging on by default, one record per executed variable, and redaction of the
# error channel so admiral/dplyr assertion values never reach a note, the log,
# or the console.

log_lines <- function(file) {
  lines <- readLines(file, warn = FALSE)
  lines[nzchar(trimws(lines))]
}

log_records <- function(file, event = NULL) {
  recs <- lapply(log_lines(file), jsonlite::fromJSON, simplifyVector = FALSE)
  if (is.null(event)) recs else Filter(function(r) identical(r$event, event), recs)
}

# writes tampered lines to a fresh file (no head sidecar travels with them)
tampered <- function(lines) {
  path <- tempfile(fileext = ".jsonl")
  writeLines(lines, path)
  path
}

assign_ir_one <- function(target = "STUDYID") {
  list(new_variable_ir("ADSL", target, list(
    new_step("assign", list(target = target, literal = "ABC"))
  )))
}

test_that("an untouched chain verifies and reports no broken link", {
  lf <- tempfile(fileext = ".jsonl")
  for (i in 1:4) log_run("unit_event", list(i = i), file = lf)

  res <- verify_log(lf)
  expect_true(res$ok)
  expect_identical(res$records, 4L)
  expect_true(is.na(res$broken_line))
  expect_identical(res$reason, "")

  first <- log_records(lf)[[1]]
  expect_identical(first$prev, strrep("0", 64))
  expect_identical(first$seq, 1L)
  expect_identical(first$mode, "sha256")
  expect_true(nzchar(first$digest))
  # each record seals the one before it
  expect_identical(log_records(lf)[[2]]$prev, first$digest)
})

test_that("editing a log line breaks the chain and the verifier names it", {
  lf <- tempfile(fileext = ".jsonl")
  for (i in 1:4) log_run("unit_event", list(i = i), file = lf)
  lines <- log_lines(lf)

  edited <- lines
  edited[2] <- sub('"i":2', '"i":99', edited[2], fixed = TRUE)
  expect_false(identical(edited[2], lines[2]))

  res <- verify_log(tampered(edited))
  expect_false(res$ok)
  expect_identical(res$broken_line, 2L)
  expect_identical(res$broken_event, "unit_event")
  expect_match(res$reason, "edited")
})

test_that("deleting a log line breaks the chain and the verifier names it", {
  lf <- tempfile(fileext = ".jsonl")
  for (i in 1:4) log_run("unit_event", list(i = i), file = lf)
  lines <- log_lines(lf)

  res <- verify_log(tampered(lines[-2]))
  expect_false(res$ok)
  expect_identical(res$broken_line, 2L)
  expect_match(res$reason, "deleted|reordered")

  # deleting the first record is caught too
  head_gone <- verify_log(tampered(lines[-1]))
  expect_false(head_gone$ok)
  expect_identical(head_gone$broken_line, 1L)
})

test_that("reordering log lines breaks the chain and the verifier names it", {
  lf <- tempfile(fileext = ".jsonl")
  for (i in 1:4) log_run("unit_event", list(i = i), file = lf)
  lines <- log_lines(lf)

  res <- verify_log(tampered(lines[c(1, 3, 2, 4)]))
  expect_false(res$ok)
  expect_identical(res$broken_line, 2L)
  expect_match(res$reason, "reordered")
})

test_that("records removed from the end are caught by the head pointer", {
  lf <- tempfile(fileext = ".jsonl")
  for (i in 1:4) log_run("unit_event", list(i = i), file = lf)
  lines <- log_lines(lf)

  truncated <- tempfile(fileext = ".jsonl")
  writeLines(lines[1:3], truncated)
  file.copy(paste0(lf, ".head"), paste0(truncated, ".head"))

  res <- verify_log(truncated)
  expect_false(res$ok)
  expect_identical(res$broken_line, 4L)
  expect_match(res$reason, "removed from the end")
})

test_that("an HMAC key seals the chain and a missing key never downgrades silently", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_key = "unit-test-key")
  on.exit(options(old), add = TRUE)

  log_run("keyed_event", list(i = 1), file = lf)
  log_run("keyed_event", list(i = 2), file = lf)
  expect_identical(log_records(lf)[[1]]$mode, "hmac-sha256")
  expect_true(verify_log(lf)$ok)

  # the wrong key, or no key at all, is reported rather than accepted
  wrong <- verify_log(lf, key = "other-key")
  expect_false(wrong$ok)
  expect_identical(wrong$broken_line, 1L)
  unkeyed <- verify_log(lf, key = NULL)
  expect_false(unkeyed$ok)
  expect_match(unkeyed$reason, "no key is configured")

  # an unkeyed record appended into a keyed log is a downgrade, not a pass
  plain <- tempfile(fileext = ".jsonl")
  options(admiralagent.log_key = NULL)
  log_run("plain_event", list(i = 1), file = plain)
  options(admiralagent.log_key = "unit-test-key")
  res <- verify_log(plain)
  expect_false(res$ok)
  expect_match(res$reason, "downgrade")
})

test_that("execute_ir writes exactly one audit record per variable", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  res <- execute_ir(ir, sources = list(base = data.frame(
    USUBJID = c("a", "b"), ARM = c("A", "B"), stringsAsFactors = FALSE
  )))

  recs <- log_records(lf, "execute_variable")
  expect_length(recs, nrow(res$status))
  expect_identical(
    vapply(recs, function(r) r$details$variable, character(1)),
    res$status$variable
  )
  expect_identical(
    vapply(recs, function(r) r$details$status, character(1)),
    res$status$status
  )
  # REVIEW variables are logged too: every variable leaves a trace
  expect_true("REVIEW" %in% vapply(recs, function(r) r$details$status, character(1)))
  # all records of one call share a run id, and the chain still verifies
  expect_length(unique(vapply(recs, function(r) r$details$run_id, character(1))), 1L)
  expect_true(verify_log(lf)$ok)

  # a second run appends, it does not restart the chain
  execute_ir(ir, sources = list(base = data.frame(USUBJID = "a", ARM = "A")))
  expect_true(verify_log(lf)$ok)
  expect_length(unique(vapply(
    log_records(lf, "execute_variable"), function(r) r$details$run_id, character(1)
  )), 2L)
})

test_that("logging is on by default with no option and no env var set", {
  old <- options(admiralagent.log_file = NULL)
  old_env <- Sys.getenv("ADMIRALAGENT_LOG_FILE", unset = NA)
  Sys.unsetenv("ADMIRALAGENT_LOG_FILE")
  on.exit({
    options(old)
    if (!is.na(old_env)) Sys.setenv(ADMIRALAGENT_LOG_FILE = old_env)
  }, add = TRUE)

  lf <- aa_log_file()
  expect_identical(lf, file.path(tempdir(), "admiralagent_audit.jsonl"))
  before <- if (file.exists(lf)) length(log_lines(lf)) else 0L

  res <- execute_ir(assign_ir_one(), sources = list(base = data.frame(USUBJID = c("a", "b"))))
  expect_identical(res$status$status, "EXECUTED")

  # TWO records for this one-variable run, and exactly two: the `execute_variable`
  # record for STUDYID, then the `run_manifest` record execute_ir() now emits
  # in-line for the run (one per RUN, not one per variable - see
  # test-manifest-auto.R). The manifest lands after the execution records, so the
  # positional read below still finds the execution record first.
  expect_length(log_lines(lf), before + 2L)
  last <- log_records(lf)[[before + 1L]]
  expect_identical(last$event, "execute_variable")
  expect_identical(last$details$variable, "STUDYID")
  expect_identical(log_records(lf)[[before + 2L]]$event, "run_manifest")
  expect_true(verify_log(lf)$ok)

  # opting out is explicit, and only then is nothing written - neither the
  # execution record nor the manifest
  execute_ir(assign_ir_one(), sources = list(base = data.frame(USUBJID = "a")), log_file = NA)
  expect_length(log_lines(lf), before + 2L)
})

test_that("a data value in an execution error reaches neither note, log nor console", {
  skip_if_not_installed("dplyr")
  secret <- "SECRET-VALUE-42"
  # synthetic admiral-style assertion: a classed condition whose message echoes
  # the offending data value, raised from inside the rendered dplyr::mutate call
  registerS3method(
    "mutate", "aa_audit_boom",
    function(.data, ...) {
      stop(structure(
        class = c("admiral_assert_error", "error", "condition"),
        list(
          message = paste0("`RFSTDTC` must be a valid date, but element 2 is `", secret, "`."),
          call = NULL
        )
      ))
    },
    envir = asNamespace("dplyr")
  )

  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  base <- structure(
    data.frame(USUBJID = c("a", "b"), stringsAsFactors = FALSE),
    class = c("aa_audit_boom", "data.frame")
  )
  msgs <- NULL
  printed <- capture.output(
    msgs <- capture.output(
      res <- execute_ir(assign_ir_one(), sources = list(base = base), quiet = FALSE),
      type = "message"
    )
  )
  console <- paste(c(printed, msgs), collapse = "\n")

  expect_identical(res$status$status, "ERROR")
  # the value is gone from every channel
  expect_false(grepl(secret, res$status$note, fixed = TRUE))
  expect_false(grepl(secret, console, fixed = TRUE))
  expect_false(any(grepl(secret, log_lines(lf), fixed = TRUE)))
  # what a debugger needs survives: condition class and failing admiral call
  expect_match(res$status$note, "admiral_assert_error", fixed = TRUE)
  expect_match(res$status$note, "dplyr::mutate()", fixed = TRUE)
  expect_match(res$status$note, "layer assign", fixed = TRUE)
  expect_match(console, "admiral_assert_error", fixed = TRUE)
  logged <- log_records(lf, "execute_variable")[[1]]
  expect_identical(logged$details$note, res$status$note)
  expect_identical(logged$details$status, "ERROR")

  # detail is opt-in and out-of-band only
  expect_null(aa_last_error_detail())
  opt <- options(admiralagent.error_detail = TRUE)
  execute_ir(assign_ir_one(), sources = list(base = base), log_file = NA)
  detail <- aa_last_error_detail()
  options(opt)
  expect_true(grepl(secret, detail$message, fixed = TRUE))
  expect_false(any(grepl(secret, log_lines(lf), fixed = TRUE)))
})

test_that("redaction does not swallow admiralagent's own execution errors", {
  v <- new_variable_ir("ADSL", "AGE", list(new_step("duration", list(
    target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years"
  ))))
  res <- execute_ir(list(v), sources = list(base = data.frame(USUBJID = "a")), log_file = NA)
  expect_identical(res$status$status, "ERROR")
  expect_identical(res$status$note, "column 'BRTHDT' is missing from source dataset 'ADSL'")
})

test_that("REGRESSION GUARD: the pinned rules-backend artifact hash is unchanged", {
  expect_identical(
    artifact_hash(classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")),
    "6aea851a"
  )
})
