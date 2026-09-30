# Run manifest tests.
#
# POSITIONING: a manifest pins the CONDITIONS of a run - R version, the package
# versions the rendered code binds against, the operator, a digest of the source
# data, the model parameters, and whether gating was enforced. It asserts
# nothing about whether the derivations were correct.
#
# It is one more event on the SAME hash-chained audit log, so everything the
# chain already guarantees applies to it unchanged. These tests pin the
# recording, the join to the execution records, the loudness of the package
# version fallback, and the absence of patient data.

manifest_lines <- function(file) {
  lines <- readLines(file, warn = FALSE)
  lines[nzchar(trimws(lines))]
}

manifest_events <- function(file, event) {
  recs <- lapply(manifest_lines(file), jsonlite::fromJSON, simplifyVector = FALSE)
  Filter(function(r) identical(r$event, event), recs)
}

manifest_ir <- function() {
  list(new_variable_ir("ADSL", "SITEID", list(
    new_step("assign", list(target = "SITEID", literal = "S1"))
  )))
}

# a base with a value that must never appear anywhere in the manifest
manifest_sources <- function(value = "SECRET-SUBJ-0001") {
  list(base = data.frame(
    USUBJID = c(value, "SUBJ-0002"),
    ARM = c("Placebo", "Xanomeline High Dose"),
    stringsAsFactors = FALSE
  ))
}

test_that("a manifest record captures the execution environment, operator, source digest and gating flag", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf, admiralagent.require_gate = NULL)
  on.exit(options(old), add = TRUE)

  ir <- manifest_ir()
  details <- log_run_manifest(
    run_id = "run-unit-1", ir = ir, sources = manifest_sources(),
    operator = "Dr A. Programmer <a.programmer@example.org>, Stats Programming",
    backend = "llm", model = "unit-model-1", prompt = "classify these variables",
    seed = 42, temperature = 0
  )

  recs <- manifest_events(lf, "run_manifest")
  expect_length(recs, 1L)
  d <- recs[[1]]$details
  expect_identical(d$manifest_schema, "admiralagent-manifest-1")

  # R version and platform
  expect_identical(d$r_version, R.version.string)
  expect_identical(d$r_release, paste(R.version$major, R.version$minor, sep = "."))
  expect_identical(d$platform, R.version$platform)

  # the four packages checked at render time but never before recorded
  expect_identical(
    sort(names(d$packages)), sort(c("admiral", "metatools", "dplyr", "rlang"))
  )
  for (p in c("admiral", "metatools", "dplyr", "rlang")) {
    expect_identical(
      d$packages[[p]],
      tryCatch(as.character(utils::packageVersion(p)), error = function(e) NULL)
    )
  }

  # operator identity, and where it came from - a login name is not a signature
  expect_identical(d$operator, "Dr A. Programmer <a.programmer@example.org>, Stats Programming")
  expect_identical(d$operator_source, "declared")

  # source-data snapshot: a digest and a shape, addressable per source
  expect_length(d$source_data, 1L)
  expect_identical(d$source_data[[1]]$source, "base")
  expect_identical(d$source_data[[1]]$rows, 2L)
  expect_identical(d$source_data[[1]]$cols, 2L)
  expect_match(d$source_data[[1]]$digest, "^xxhash64:[0-9a-f]+$")
  expect_match(d$source_data_digest, "^sources:[0-9a-f]{16}$")
  # a different snapshot of the same schema digests differently
  other <- log_run_manifest("run-unit-2", sources = manifest_sources("SUBJ-9999"), file = lf)
  expect_false(identical(other$source_data_digest, d$source_data_digest))

  # model parameters: the repo recorded none of these before
  expect_identical(d$backend, "llm")
  expect_identical(d$model, "unit-model-1")
  # JSON narrows a whole double back to an integer on the way out, so compare
  # by value: what matters is that the parameters are on the record at all
  expect_equal(d$seed, 42)
  expect_equal(d$temperature, 0)
  expect_identical(details$seed, 42)
  expect_match(d$prompt_digest, "^prompt:[0-9a-f]{16}$")

  # the IR is present as a hash, never as content
  expect_identical(d$ir_hash, artifact_hash(ir))

  # gating: nothing was passed or set, so the shipped default (enforce ON)
  # applied, and the manifest says so
  expect_true(d$gate_enforced)
  expect_identical(details$gate_enforced, TRUE)
})

test_that("the gating-enforced flag distinguishes a gated run from an ungated one", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(admiralagent.require_gate = NULL), add = TRUE)
  on.exit(options(old), add = TRUE)

  ir <- manifest_ir()

  # the shipped default is ON, so an unqualified run is recorded as enforced
  options(admiralagent.require_gate = NULL)
  log_run_manifest("run-default", ir = ir, file = lf)

  # opting out by option records an ungated run; the manifest reads the SAME
  # resolution the write path uses, so it states the policy that applied
  options(admiralagent.require_gate = FALSE)
  log_run_manifest("run-ungated", ir = ir, file = lf)

  options(admiralagent.require_gate = TRUE)
  gate <- sign_gate("Q. Lead", "spec cross-checked", gate_scope(ir), file = lf)
  log_run_manifest("run-gated", ir = ir, gate = gate, file = lf)

  # and an explicit argument overrides the option in both directions
  log_run_manifest("run-forced-off", ir = ir, require_gate = FALSE, file = lf)

  by_id <- function(id) read_manifests(lf, run_id = id)[[1]]
  expect_true(by_id("run-default")$gate_enforced)
  expect_false(by_id("run-ungated")$gate_enforced)
  expect_true(by_id("run-gated")$gate_enforced)
  expect_identical(by_id("run-gated")$gate_id, gate$gate_id)
  expect_false(by_id("run-forced-off")$gate_enforced)
  # an ungated run carries no gate id to be mistaken for an approval
  expect_true(is.null(by_id("run-ungated")$gate_id) || is.na(by_id("run-ungated")$gate_id))

  expect_error(log_run_manifest("run-bad", require_gate = "yes", file = lf), "TRUE or FALSE")
})

test_that("a manifest verifies as part of the existing chain alongside gate and execution records", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  ir <- manifest_ir()
  gate <- sign_gate("R. Signer", "checked", gate_scope(ir))
  execute_ir(ir, sources = manifest_sources())
  log_run_manifest(log_run_ids(lf)[[1]], ir = ir, sources = manifest_sources(), gate = gate)

  res <- verify_log(lf)
  expect_true(res$ok)
  events <- vapply(
    lapply(manifest_lines(lf), jsonlite::fromJSON, simplifyVector = FALSE),
    function(r) r$event, character(1)
  )
  expect_true(all(c("gate", "execute_variable", "run_manifest") %in% events))

  # the manifest is not a parallel record store: one chain, one file
  expect_length(list.files(dirname(lf), pattern = paste0("^", basename(lf), "$")), 1L)

  # the schema is unchanged, digest still last, so verification recovers bytes
  m <- manifest_events(lf, "run_manifest")[[1]]
  expect_identical(
    names(m),
    c("schema", "seq", "time", "package_version", "event", "details", "prev", "mode", "digest")
  )
  expect_identical(m$schema, "admiralagent-audit-1")

  # editing the manifest record in place breaks the chain like any other record
  lines <- manifest_lines(lf)
  i <- which(events == "run_manifest")[[1]]
  lines[i] <- sub(R.version$platform, "forged-platform", lines[i], fixed = TRUE)
  forged <- tempfile(fileext = ".jsonl")
  writeLines(lines, forged)
  broken <- verify_log(forged)
  expect_false(broken$ok)
  expect_identical(broken$broken_line, i)
  expect_identical(broken$broken_event, "run_manifest")
})

test_that("a manifest cannot be recorded where it could not be recovered", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  expect_error(log_run_manifest("run-ghost"), "logging is switched off")
  expect_error(log_run_manifest("", file = tempfile()), "run_id must be one non-empty string")
})

test_that("the manifest run_id matches the execution records of the same run", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  # execute_ir() emits the manifest itself, so no hand-written
  # log_run_manifest() call is needed (or wanted) here: the manifest is present
  # BECAUSE the run happened. Writing one by hand as well would make this test
  # assert that a doubled emission is correct, and would mask a real double-emit
  # bug in execute_ir(). See test-manifest-auto.R for the automatic contract.
  ir <- manifest_ir()
  execute_ir(ir, sources = manifest_sources())
  ids <- log_run_ids(lf)
  expect_length(ids, 1L)

  exec <- manifest_events(lf, "execute_variable")
  man <- read_manifests(lf)
  expect_length(man, 1L)
  expect_identical(man[[1]]$run_id, ids[[1]])
  expect_true(all(vapply(exec, function(r) identical(r$details$run_id, man[[1]]$run_id), logical(1))))

  # a second run gets its own id, and the manifests stay distinguishable
  execute_ir(ir, sources = manifest_sources())
  ids2 <- log_run_ids(lf)
  expect_length(ids2, 2L)
  expect_length(read_manifests(lf, run_id = ids2[[2]]), 1L)
  expect_length(read_manifests(lf, run_id = ids2[[1]]), 1L)
  expect_false(identical(ids2[[1]], ids2[[2]]))
  expect_true(verify_log(lf)$ok)
})

test_that("the pkg_ver() fallback is recorded rather than silent, and is loud on demand", {
  # the VALUE is deliberately unchanged: pkg_ver() feeds artifact_hash(), so
  # moving it would rename every artifact and every pinned golden
  expect_identical(pkg_ver(), pkg_ver_info()$version)

  installed <- pkg_ver_info(installed = "9.9.9")
  expect_identical(installed$version, "9.9.9")
  expect_identical(installed$source, "installed")
  expect_true(installed$reliable)

  # the fallback path still yields the same string, but now says it guessed
  fb <- pkg_ver_info(installed = NULL)
  expect_identical(fb$version, "0.1.0")
  expect_identical(fb$source, "fallback")
  expect_false(fb$reliable)

  # ... and a regulated run can make the guess a hard error instead
  old <- options(admiralagent.strict_package_version = TRUE)
  on.exit(options(old), add = TRUE)
  expect_error(pkg_ver_info(installed = NULL), "collapses distinct source trees")
  expect_identical(pkg_ver_info(installed = "9.9.9")$version, "9.9.9")
  options(old)

  # and the provenance reaches the manifest, so a historical run is
  # self-identifying as "version known" or "version guessed"
  lf <- tempfile(fileext = ".jsonl")
  d <- log_run_manifest("run-ver", file = lf)
  expect_true(d$package_version_source %in% c("installed", "fallback"))
  expect_identical(d$package_version, pkg_ver())
  expect_identical(d$package_version_reliable, identical(d$package_version_source, "installed"))
  expect_identical(read_manifests(lf)[[1]]$package_version_source, d$package_version_source)
})

test_that("no patient data leaks into the manifest", {
  lf <- tempfile(fileext = ".jsonl")
  secret <- "SECRET-SUBJ-0001"
  arm <- "Xanomeline High Dose"
  log_run_manifest(
    "run-privacy", ir = manifest_ir(), sources = manifest_sources(secret),
    prompt = paste("derive SITEID for", secret), file = lf
  )

  raw <- paste(manifest_lines(lf), collapse = "\n")
  # the subject id and the treatment value are absent from the record entirely
  expect_false(grepl(secret, raw, fixed = TRUE))
  expect_false(grepl(arm, raw, fixed = TRUE))
  # free text is digested, not echoed (A13's precedent)
  d <- read_manifests(lf)[[1]]
  expect_match(d$prompt_digest, "^prompt:[0-9a-f]{16}$")
  expect_false(grepl(secret, d$prompt_digest, fixed = TRUE))
  # what IS recorded is schema level: shape, column names, a digest
  expect_identical(unlist(d$source_data[[1]]$columns), c("USUBJID", "ARM"))
  expect_match(d$source_data[[1]]$digest, "^xxhash64:[0-9a-f]+$")
})

test_that("REGRESSION GUARD: the pinned rules-backend artifact hash is unchanged", {
  # Nothing in the manifest work touches an input to artifact_hash():
  # canonical_ir()'s seven whitelisted fields are untouched, pkg_ver() returns
  # the same string, and the manifest travels in the log record's details.
  expect_identical(
    artifact_hash(classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")),
    "84a18650"
  )
})
