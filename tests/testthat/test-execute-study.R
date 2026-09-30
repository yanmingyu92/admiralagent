# execute_study(): the multi-deliverable executor. One shared environment, one
# order_variables() pass over the WHOLE IR (deliverables interleave; grouping
# them would impose an arbitrary outer order the graph leaves free), one
# failed_outputs accumulator and one run id per study call.
#
# execute_ir() stays covered by test-execute.R and execute_ir_one() by
# test-execute-one.R; both must keep passing unmodified.

study_sources <- function() {
  list(
    dm = data.frame(
      STUDYID = "S1", USUBJID = c("a", "b", "c"),
      RFXSTDTC = c("2020-01-01", "2020-02-01", "2020-03-01"),
      ARM = c("Placebo", "Drug", "Placebo"),
      stringsAsFactors = FALSE
    ),
    tte_base = data.frame(
      STUDYID = "S1", USUBJID = c("a", "b", "c"), stringsAsFactors = FALSE
    ),
    ae_base = data.frame(
      STUDYID = "S1", USUBJID = c("a", "b", "c"), stringsAsFactors = FALSE
    )
  )
}

study_deliverables <- function() list(ADSL = "dm", ADTTE = "tte_base")

# ADTTE::TTE pulls TRTSDTM straight out of the shared environment's ADSL, so the
# cross-deliverable edge is a real data dependency, not a naming convention.
study_ir <- function(from = "RFXSTDTC") {
  list(
    new_variable_ir("ADSL", "TRTSDTM", list(
      new_step("assign", list(target = "TRTSDTM", from = from))
    )),
    new_variable_ir("ADSL", "TRT01P", list(
      new_step("assign", list(target = "TRT01P", from = "ARM"))
    )),
    new_variable_ir("ADTTE", "TTE", list(
      new_step("merge_var", list(
        target = "TTE", source = "TRTSDTM", dataset_add = "ADSL",
        by_vars = c("STUDYID", "USUBJID"), mode = "first"
      ))
    )),
    new_variable_ir("ADTTE", "CNSR", list(
      new_step("assign", list(target = "CNSR", literal = "0"))
    ))
  )
}

run_study <- function(ir = study_ir(), sources = study_sources(),
                      deliverables = study_deliverables(), ...) {
  execute_study(ir, sources = sources, deliverables = deliverables, log_file = NA, ...)
}

status_key <- function(res) {
  stats::setNames(res$status$status, paste(res$status$dataset, res$status$variable, sep = "::"))
}
note_key <- function(res) {
  stats::setNames(res$status$note, paste(res$status$dataset, res$status$variable, sep = "::"))
}

study_records <- function(file) {
  lines <- readLines(file, warn = FALSE)
  recs <- lapply(lines[nzchar(trimws(lines))], jsonlite::fromJSON, simplifyVector = FALSE)
  Filter(function(r) identical(r$event, "execute_variable"), recs)
}

test_that("ADSL and ADTTE build end to end through one execute_study call", {
  skip_if_not_installed("admiral")
  ir <- study_ir()
  expect_length(validate_ir(ir), 0)

  res <- run_study(ir)

  expect_identical(res$status$status, rep("EXECUTED", 4))
  expect_identical(names(res$datasets), c("ADSL", "ADTTE"))
  expect_true(all(c("TRTSDTM", "TRT01P") %in% names(res$datasets$ADSL)))
  expect_true(all(c("TTE", "CNSR") %in% names(res$datasets$ADTTE)))
  # the downstream deliverable read the upstream one out of the shared env
  expect_identical(res$datasets$ADTTE$TTE, res$datasets$ADSL$TRTSDTM)
  expect_identical(res$env$ADSL, res$datasets$ADSL)
  expect_identical(res$env$ADTTE, res$datasets$ADTTE)
  # $adsl is the back-compat alias for the first deliverable
  expect_identical(res$adsl, res$datasets$ADSL)
  expect_identical(names(res), c("datasets", "status", "env", "adsl"))
})

test_that("the whole IR goes through one order_variables() pass, deliverables interleaved", {
  skip_if_not_installed("admiral")
  res <- run_study()

  # ADTTE::TTE runs the moment its ADSL input exists - before the remaining
  # ADSL variables. Grouping by deliverable could not produce this order.
  expect_identical(res$status$variable, c("TRTSDTM", "TTE", "TRT01P", "CNSR"))
  expect_identical(res$status$dataset, c("ADSL", "ADTTE", "ADSL", "ADTTE"))
})

test_that("running the same study twice is byte-identical", {
  skip_if_not_installed("admiral")
  first <- run_study()
  second <- run_study()

  expect_identical(first$status, second$status)
  expect_identical(first$datasets, second$datasets)
  expect_identical(first$adsl, second$adsl)
})

test_that("a failed ADSL derivation makes the ADTTE consumer report the stale input, not a value", {
  sources <- study_sources()
  sources$dm$RFXSTDTC <- NULL # ADSL::TRTSDTM can no longer be derived

  res <- run_study(sources = sources)
  st <- status_key(res)
  notes <- note_key(res)

  expect_identical(st[["ADSL::TRTSDTM"]], "ERROR")
  expect_identical(
    notes[["ADSL::TRTSDTM"]],
    "column 'RFXSTDTC' is missing from source dataset 'ADSL'"
  )
  # THE guarantee: the ADTTE consumer is blocked across the deliverable
  # boundary and says so; it does not merge a half-written or absent column.
  expect_identical(st[["ADTTE::TTE"]], "ERROR")
  expect_identical(
    notes[["ADTTE::TTE"]],
    "upstream derivation failed; stale inputs are not used"
  )
  expect_false("TTE" %in% names(res$datasets$ADTTE))
  expect_false("TRTSDTM" %in% names(res$datasets$ADSL))

  # one accumulator, not one per deliverable: variables that depend on nothing
  # broken still run, in both deliverables
  expect_identical(st[["ADSL::TRT01P"]], "EXECUTED")
  expect_identical(st[["ADTTE::CNSR"]], "EXECUTED")
})

test_that("a failure on ADAE leaves ADSL and ADTTE byte-identical", {
  skip_if_not_installed("admiral")
  clean <- run_study()

  ir <- c(study_ir(), list(new_variable_ir("ADAE", "AEDURN", list(
    new_step("duration", list(
      target = "AEDURN", start = "ASTDT", end = "AENDT", out_unit = "days"
    ))
  ))))
  res <- run_study(ir, deliverables = c(study_deliverables(), list(ADAE = "ae_base")))

  expect_identical(status_key(res)[["ADAE::AEDURN"]], "ERROR")
  expect_identical(res$datasets$ADSL, clean$datasets$ADSL)
  expect_identical(res$datasets$ADTTE, clean$datasets$ADTTE)
  # the failing deliverable itself rolled back to its untouched base
  expect_identical(res$datasets$ADAE, study_sources()$ae_base)
})

test_that("every audit record of one execute_study call shares one run id", {
  skip_if_not_installed("admiral")
  lf <- tempfile(fileext = ".jsonl")

  res <- execute_study(study_ir(), sources = study_sources(),
                       deliverables = study_deliverables(), log_file = lf)

  recs <- study_records(lf)
  expect_length(recs, nrow(res$status))
  expect_length(unique(vapply(recs, function(r) r$details$run_id, character(1))), 1L)
  # the records cover both deliverables, in execution order
  expect_identical(vapply(recs, function(r) r$details$dataset, character(1)), res$status$dataset)
  expect_identical(vapply(recs, function(r) r$details$variable, character(1)), res$status$variable)
  expect_true(verify_log(lf)$ok)

  # a second study is a second run id appended to the same chain
  execute_study(study_ir(), sources = study_sources(),
                deliverables = study_deliverables(), log_file = lf)
  expect_length(
    unique(vapply(study_records(lf), function(r) r$details$run_id, character(1))), 2L
  )
  expect_true(verify_log(lf)$ok)
})

test_that("the narrowed rollback copies only what a variable touches and restores all of it", {
  ex0 <- data.frame(
    USUBJID = c("a", "b"), EXSTDTC = c("2020-01-01", "2020-02-01"),
    stringsAsFactors = FALSE
  )
  base <- data.frame(USUBJID = c("a", "b"), stringsAsFactors = FALSE)
  spectator <- data.frame(NEVER_TOUCHED = 1)
  env <- new.env(parent = baseenv())
  env$ADSL <- base
  env$ex <- ex0
  env$other <- spectator

  # step 1 writes a temp column on `ex`; step 2 fails on missing ADSL inputs
  v <- new_variable_ir("ADSL", "AGE", list(
    new_step("assign", list(target = "TMPFLAG", literal = "Y", on = "ex")),
    new_step("duration", list(
      target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years"
    ))
  ))
  expect_setequal(variable_touched_objects(v), c("ADSL", "ex"))

  res <- execute_ir_one(v, env, character(), TRUE, NULL)

  expect_identical(res$rows$status, "ERROR")
  expect_identical(env$ADSL, base)
  expect_identical(env$ex, ex0) # the foreign object step 1 wrote rolled back too
  expect_identical(env$other, spectator) # never copied, never written back
})

test_that("an object a step removes from the work copy is not removed from the shared env", {
  skip_if_not_installed("dplyr")
  # list2env() copied in but never deleted, so a removal inside a step never
  # reached the caller's env. The narrowed commit must keep that exactly:
  # `ex` is a touched object, yet it is gone from the work copy at commit time.
  registerS3method(
    "mutate", "aa_study_ghost",
    function(.data, ...) {
      if (exists("ex", envir = parent.frame(), inherits = FALSE)) {
        rm(list = "ex", envir = parent.frame())
      }
      class(.data) <- "data.frame"
      dplyr::mutate(.data, ...)
    },
    envir = asNamespace("dplyr")
  )

  base <- structure(
    data.frame(USUBJID = c("a", "b"), stringsAsFactors = FALSE),
    class = c("aa_study_ghost", "data.frame")
  )
  ex0 <- data.frame(USUBJID = c("a", "b"), stringsAsFactors = FALSE)
  env <- new.env(parent = baseenv())
  env$ADSL <- base
  env$ex <- ex0

  # step 1 writes TMPX onto `ex`; step 2 runs on ADSL and deletes `ex` from the
  # work copy before the commit
  v <- new_variable_ir("ADSL", "X", list(
    new_step("assign", list(target = "TMPX", literal = "Y", on = "ex")),
    new_step("assign", list(target = "X", from = "USUBJID"))
  ))
  expect_setequal(variable_touched_objects(v), c("ADSL", "ex"))

  res <- execute_ir_one(v, env, character(), TRUE, NULL)

  expect_identical(res$rows$status, "EXECUTED")
  expect_true("X" %in% names(env$ADSL))
  # `ex` survives in the caller's env, carrying its pre-step value: a deleted
  # object is not committed and not deleted either
  expect_true(exists("ex", envir = env, inherits = FALSE))
  expect_identical(env$ex, ex0)
})

test_that("every IR dataset needs a declared base and no source may shadow one", {
  ir <- study_ir()
  src <- study_sources()

  expect_error(execute_study(ir, sources = src, deliverables = list(ADSL = "dm")), "ADTTE")
  expect_error(
    execute_study(ir, sources = src, deliverables = list(ADSL = "dm", ADTTE = "nope")),
    "not an element of sources"
  )
  expect_error(
    execute_study(ir, sources = c(src, list(ADTTE = src$tte_base)),
                  deliverables = study_deliverables()),
    "shadow"
  )
  expect_error(
    execute_study(ir, sources = c(src, list(exprs = src$dm)),
                  deliverables = study_deliverables()),
    "shadow"
  )
  # a source may carry a deliverable's name when it IS that deliverable's base
  skip_if_not_installed("admiral")
  ok <- execute_study(ir, sources = list(dm = src$dm, ADTTE = src$tte_base),
                      deliverables = list(ADSL = "dm", ADTTE = "ADTTE"), log_file = NA)
  expect_identical(unname(status_key(ok)[["ADTTE::TTE"]]), "EXECUTED")
})

test_that("a single-deliverable execute_study reproduces execute_ir", {
  base <- data.frame(USUBJID = c("a", "b"), ARM = c("A", "B"), stringsAsFactors = FALSE)
  ir <- list(new_variable_ir("ADSL", "TRT01P", list(
    new_step("assign", list(target = "TRT01P", from = "ARM"))
  )))

  one <- execute_ir(ir, sources = list(base = base), log_file = NA)
  # deliverables defaults to the lower-cased dataset name, as execute_ir allows
  study <- execute_study(ir, sources = list(adsl = base), log_file = NA)

  expect_identical(study$adsl, one$adsl)
  expect_identical(study$datasets$ADSL, one$adsl)
  expect_identical(study$status$variable, one$status$variable)
  expect_identical(study$status$status, one$status$status)
  expect_identical(study$status$note, one$status$note)
})
