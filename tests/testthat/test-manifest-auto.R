# AUTOMATIC run manifest.
#
# POSITIONING: test-manifest.R pins what a manifest CONTAINS. This file pins
# that one gets WRITTEN without anyone remembering to write it.
#
# The manifest exists to stop "same IR, different machine, different result, and
# nothing records it". That sentence stays true for as long as the manifest is a
# three-step operator ritual (execute -> log_run_ids() -> log_run_manifest()):
# a replay record someone must remember to produce is, for audit purposes,
# closer to absent than present - the same failure shape as the approval gate
# back when it defaulted to off. `execute_ir()` and `execute_study()` mint `run_id`
# internally, so they are the only place that can emit a manifest which JOINS
# the run it describes, and they now do it in-line.
#
# The contract pinned here:
#   1. an operator who does NOTHING still gets a manifest;
#   2. exactly one per RUN - not one per variable, not one per deliverable;
#   3. it carries the run's own `run_id`, so manifest and executions join;
#   4. `log_file = NA` suppresses it, because that is the existing off switch;
#   5. it is one more record on the SAME hash-chained log, which still verifies;
#   6. it still contains no patient data.

auto_lines <- function(file) {
  lines <- readLines(file, warn = FALSE)
  lines[nzchar(trimws(lines))]
}

auto_records <- function(file, event = NULL) {
  recs <- lapply(auto_lines(file), jsonlite::fromJSON, simplifyVector = FALSE)
  if (is.null(event)) recs else Filter(function(r) identical(r$event, event), recs)
}

auto_events <- function(file) {
  vapply(auto_records(file), function(r) r$event, character(1))
}

# Several variables, so "one manifest" cannot pass by accident on a one-variable
# IR: one-per-run and one-per-variable would be indistinguishable there.
auto_ir <- function() {
  list(
    new_variable_ir("ADSL", "STUDYID", list(
      new_step("assign", list(target = "STUDYID", literal = "AA-001"))
    )),
    new_variable_ir("ADSL", "SITEID", list(
      new_step("assign", list(target = "SITEID", literal = "S1"))
    )),
    new_variable_ir("ADSL", "TRT01P", list(
      new_step("assign", list(target = "TRT01P", literal = "Placebo"))
    ))
  )
}

# a base carrying values that must never reach the log
auto_sources <- function(value = "SECRET-SUBJ-0001") {
  list(base = data.frame(
    USUBJID = c(value, "SUBJ-0002"),
    ARM = c("Placebo", "Xanomeline High Dose"),
    stringsAsFactors = FALSE
  ))
}

# Two deliverables, so "one manifest per study" cannot pass by accident either.
auto_study_ir <- function() {
  list(
    new_variable_ir("ADSL", "STUDYID", list(
      new_step("assign", list(target = "STUDYID", literal = "AA-001"))
    )),
    new_variable_ir("ADSL", "SITEID", list(
      new_step("assign", list(target = "SITEID", literal = "S1"))
    )),
    new_variable_ir("ADTTE", "CNSR", list(
      new_step("assign", list(target = "CNSR", literal = "0"))
    )),
    new_variable_ir("ADTTE", "PARAMCD", list(
      new_step("assign", list(target = "PARAMCD", literal = "OS"))
    ))
  )
}

auto_study_sources <- function(value = "SECRET-SUBJ-0001") {
  list(
    dm = data.frame(
      USUBJID = c(value, "SUBJ-0002"),
      ARM = c("Placebo", "Xanomeline High Dose"),
      stringsAsFactors = FALSE
    ),
    tte_base = data.frame(USUBJID = c(value, "SUBJ-0002"), stringsAsFactors = FALSE)
  )
}

auto_study_deliverables <- function() list(ADSL = "dm", ADTTE = "tte_base")

test_that("a plain execute_ir() call writes exactly one manifest, with no operator action", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  ir <- auto_ir()
  # nothing but the execution call - no log_run_ids(), no log_run_manifest()
  res <- execute_ir(ir, sources = auto_sources())

  man <- read_manifests(lf)
  expect_length(man, 1L)
  expect_identical(man[[1]]$manifest_schema, "admiralagent-manifest-1")

  # one per RUN, not one per variable: the run covered several variables and
  # still produced a single manifest, while the per-variable records are intact
  expect_gt(nrow(res$status), 1L)
  expect_length(auto_records(lf, "execute_variable"), nrow(res$status))

  # the manifest describes the IR that actually ran, as a hash and nothing more
  expect_identical(man[[1]]$ir_hash, artifact_hash(ir))
  # and the environment facts the run bound against are on the record
  expect_identical(man[[1]]$r_version, R.version.string)
  expect_identical(man[[1]]$platform, R.version$platform)
  # gating policy is recorded either way; the VALUE is owned by the gate default,
  # so pin only that the run is self-identifying as gated or ungated
  expect_true(is.logical(man[[1]]$gate_enforced))
})

test_that("the automatic manifest carries the same run_id as that run's execution records", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  ir <- auto_ir()
  execute_ir(ir, sources = auto_sources())

  ids <- log_run_ids(lf)
  expect_length(ids, 1L)
  man <- read_manifests(lf)
  expect_identical(man[[1]]$run_id, ids[[1]])
  # the join holds for EVERY execution record of the run, not just the first
  exec <- auto_records(lf, "execute_variable")
  expect_true(all(vapply(
    exec, function(r) identical(r$details$run_id, man[[1]]$run_id), logical(1)
  )))

  # a second run mints its own id and its own manifest; the two stay separable
  execute_ir(ir, sources = auto_sources())
  ids2 <- log_run_ids(lf)
  expect_length(ids2, 2L)
  expect_false(identical(ids2[[1]], ids2[[2]]))
  expect_length(read_manifests(lf), 2L)
  expect_length(read_manifests(lf, run_id = ids2[[1]]), 1L)
  expect_length(read_manifests(lf, run_id = ids2[[2]]), 1L)
})

test_that("execute_study() writes one manifest for the whole study, not one per deliverable", {
  lf <- tempfile(fileext = ".jsonl")

  res <- execute_study(
    auto_study_ir(), sources = auto_study_sources(),
    deliverables = auto_study_deliverables(), log_file = lf
  )

  # the study really did build more than one deliverable
  expect_identical(sort(unique(res$status$dataset)), c("ADSL", "ADTTE"))
  expect_identical(names(res$datasets), c("ADSL", "ADTTE"))

  # ... and still produced exactly ONE manifest
  man <- read_manifests(lf)
  expect_length(man, 1L)

  # sharing the study's single run id with every per-variable record of BOTH
  # deliverables
  ids <- log_run_ids(lf)
  expect_length(ids, 1L)
  expect_identical(man[[1]]$run_id, ids[[1]])
  exec <- auto_records(lf, "execute_variable")
  expect_length(exec, nrow(res$status))
  expect_true(all(vapply(
    exec, function(r) identical(r$details$run_id, man[[1]]$run_id), logical(1)
  )))

  # the manifest saw both deliverables' bases, as digests and shapes
  expect_identical(
    sort(vapply(man[[1]]$source_data, function(s) s$source, character(1))),
    c("dm", "tte_base")
  )
})

test_that("log_file = NA writes no manifest, because it writes nothing at all", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  execute_ir(auto_ir(), sources = auto_sources(), log_file = NA)
  expect_false(file.exists(lf))

  execute_study(
    auto_study_ir(), sources = auto_study_sources(),
    deliverables = auto_study_deliverables(), log_file = NA
  )
  expect_false(file.exists(lf))

  # the off switch is the ONLY off switch: the default still emits, so the
  # manifest is not quietly opt-in
  execute_ir(auto_ir(), sources = auto_sources())
  expect_length(read_manifests(lf), 1L)
})

test_that("manifest and execution records interleave on one chain that still verifies", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  res <- execute_ir(auto_ir(), sources = auto_sources())
  n <- nrow(res$status)
  execute_ir(auto_ir(), sources = auto_sources())

  expect_true(verify_log(lf)$ok)

  # each run's manifest follows that run's execution records, and the next run
  # appends to the same chain rather than restarting it
  expect_identical(
    auto_events(lf),
    c(rep("execute_variable", n), "run_manifest",
      rep("execute_variable", n), "run_manifest")
  )

  # not a parallel record store: one chain, one file
  expect_length(
    list.files(dirname(lf), pattern = paste0("^", basename(lf), "$")), 1L
  )

  # the audit record schema is untouched, digest still LAST so verification
  # recovers the exact hashed bytes
  m <- auto_records(lf, "run_manifest")[[1]]
  expect_identical(
    names(m),
    c("schema", "seq", "time", "package_version", "event", "details", "prev", "mode", "digest")
  )
  expect_identical(m$schema, "admiralagent-audit-1")
})

test_that("no patient data reaches the automatically emitted manifest", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  secret <- "SECRET-SUBJ-0001"
  arm <- "Xanomeline High Dose"
  execute_ir(auto_ir(), sources = auto_sources(secret))

  # the whole log, manifest included, is free of the source values
  raw <- paste(auto_lines(lf), collapse = "\n")
  expect_false(grepl(secret, raw, fixed = TRUE))
  expect_false(grepl(arm, raw, fixed = TRUE))

  # what IS recorded is schema level: shape, column names, a digest
  d <- read_manifests(lf)[[1]]
  expect_identical(unlist(d$source_data[[1]]$columns), c("USUBJID", "ARM"))
  expect_identical(d$source_data[[1]]$rows, 2L)
  expect_match(d$source_data[[1]]$digest, "^xxhash64:[0-9a-f]+$")
  expect_match(d$source_data_digest, "^sources:[0-9a-f]{16}$")

  # a different value behind the same schema digests differently, so the
  # digest is a real seal on the inputs and not a schema fingerprint
  lf2 <- tempfile(fileext = ".jsonl")
  execute_ir(auto_ir(), sources = auto_sources("SUBJ-9999"), log_file = lf2)
  expect_false(identical(
    read_manifests(lf2)[[1]]$source_data_digest, d$source_data_digest
  ))

  # the study path is no leakier than the single-deliverable path
  lf3 <- tempfile(fileext = ".jsonl")
  execute_study(
    auto_study_ir(), sources = auto_study_sources(secret),
    deliverables = auto_study_deliverables(), log_file = lf3
  )
  expect_false(grepl(secret, paste(auto_lines(lf3), collapse = "\n"), fixed = TRUE))
  expect_false(grepl(arm, paste(auto_lines(lf3), collapse = "\n"), fixed = TRUE))
})

test_that("REGRESSION GUARD: automatic emission changes neither the per-variable record count nor the artifact hash", {
  lf <- tempfile(fileext = ".jsonl")

  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  res <- execute_ir(ir, sources = list(base = data.frame(
    USUBJID = c("a", "b"), ARM = c("A", "B"), stringsAsFactors = FALSE
  )), log_file = lf)

  # still exactly one execute_variable record per variable, REVIEW ones included
  recs <- auto_records(lf, "execute_variable")
  expect_length(recs, nrow(res$status))
  expect_identical(
    vapply(recs, function(r) r$details$variable, character(1)), res$status$variable
  )
  # and exactly one manifest alongside them
  expect_length(auto_records(lf, "run_manifest"), 1L)

  # nothing here feeds canonical_ir()'s seven whitelisted fields
  expect_identical(artifact_hash(ir), "6aea851a")
})
