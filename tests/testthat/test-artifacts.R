test_that("artifacts are deterministic and carry sidecars", {
  dir <- file.path(tempdir(), "aa-artifacts")
  unlink(dir, recursive = TRUE)
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")

  files1 <- write_artifact(ir, dir = dir)
  files2 <- write_artifact(ir, dir = dir)
  expect_identical(sort(files1), sort(files2))

  expect_true(file.exists(file.path(dir, paste0("adsl__trtsdtm__", artifact_hash(ir), ".R"))))
  sidecar <- file.path(dir, paste0("adsl__trtsdtm__", artifact_hash(ir), ".R.json"))
  sc <- jsonlite::fromJSON(sidecar)
  expect_identical(sc$artifact, paste0("adsl__trtsdtm__", artifact_hash(ir), ".R"))
  expect_identical(sc$backend, "rules")
  expect_true(nzchar(sc$disclaimer))
  expect_equal(sc$ir$variable, "TRTSDTM")

  unlink(dir, recursive = TRUE)
})

test_that("program artifact writes script, sidecar and audit log", {
  dir <- file.path(tempdir(), "aa-program")
  unlink(dir, recursive = TRUE)
  log <- file.path(dir, "log.jsonl")
  old <- options(admiralagent.log = NULL)
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")

  suppressMessages(write_program_artifact(ir, dir = dir, require_gate = FALSE))
  prog_files <- list.files(dir, pattern = "program.*[.]R$")
  expect_length(prog_files, 1)
  sc <- jsonlite::fromJSON(file.path(dir, paste0(prog_files, ".json")))
  expect_identical(sc$backend, "rules")
  code <- readLines(file.path(dir, prog_files))
  expect_true(any(grepl("DISCLAIMER", code)))
  expect_true(any(grepl("derive_vars_dtm", code)))

  unlink(dir, recursive = TRUE)
})

test_that("log_run appends JSONL entries", {
  lf <- file.path(tempdir(), "aa-log.jsonl")
  unlink(lf)
  log_run("test_event", list(a = 1), file = lf)
  log_run("test_event2", list(a = 2), file = lf)
  lines <- readLines(lf)
  expect_length(lines, 2)
  parsed <- jsonlite::fromJSON(lines[1])
  expect_identical(parsed$event, "test_event")
  unlink(lf)
})

test_that("read_artifact round-trips IR with metadata and normalization", {
  dir <- file.path(tempdir(), "aa-roundtrip")
  unlink(dir, recursive = TRUE)
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  suppressMessages(write_program_artifact(ir, dir = dir, backend_label = "llm-x",
                                          model = "test-model", require_gate = FALSE))

  prog <- list.files(dir, pattern = "program.*[.]R$", full.names = TRUE)
  art <- read_artifact(file.path(dirname(prog), paste0(basename(prog), ".json")))
  expect_identical(art$backend, "llm-x")
  expect_identical(art$model, "test-model")
  expect_true(is.list(art$ir))
  expect_length(validate_ir(art$ir), 0)

  trts <- art$ir[[which(vapply(art$ir, function(v) v$variable, character(1)) == "TRTSDTM")]]
  expect_identical(trts$steps[[1]]$args$dtc, "RFSTDTC")
  bmi <- art$ir[[which(vapply(art$ir, function(v) v$variable, character(1)) == "BMIBL")]]
  expect_identical(bmi$steps[[1]]$args$on, "vs")
  expect_identical(bmi$steps[[2]]$args$by_vars, c("STUDYID", "USUBJID"))
  regen <- render_program(art$ir)
  expect_true(grepl("derive_vars_dtm", regen))
  unlink(dir, recursive = TRUE)
})

# ---------------------------------------------------------------------------
# Gate enforcement posture.
#
# See the DECISION block in R/artifacts.R: enforcement is ON by default, so an
# ungated write requires an explicit opt-out - the `require_gate = FALSE`
# argument on the call, or `options(admiralagent.require_gate = FALSE)` for
# the session. These tests pin BOTH halves - that the shipped default really
# blocks an ungated write (and a covering gate unblocks it) and that an
# ungated artifact, written through the explicit opt-out, says so in the code,
# the sidecar, the log and on reload.
#
# The two write_program_artifact() calls above deliberately use the opt-out
# argument: the ungated path is still a supported path and must stay tested.
# ---------------------------------------------------------------------------

a5_ir <- function() classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")

a5_events <- function(file, event) {
  lines <- readLines(file, warn = FALSE)
  recs <- lapply(lines[nzchar(trimws(lines))], jsonlite::fromJSON, simplifyVector = FALSE)
  Filter(function(r) identical(r$event, event), recs)
}

test_that("the shipped enforcement default is on and reports where it came from", {
  old <- options(admiralagent.require_gate = NULL)
  on.exit(options(old), add = TRUE)

  # the shipped posture: gating is mandatory out of the box
  expect_true(AA_GATE_REQUIRED_DEFAULT)
  expect_true(gate_required())
  expect_identical(gate_policy()$source, "default")

  # the option can switch enforcement off for a session, and says the option
  # did it - opting out never masquerades as the shipped default
  options(admiralagent.require_gate = FALSE)
  expect_false(gate_required())
  expect_identical(gate_policy()$source, "option")

  options(admiralagent.require_gate = TRUE)
  expect_true(gate_required())
  expect_identical(gate_policy()$source, "option")

  # an explicit argument wins over the option, in both directions
  expect_false(gate_policy(FALSE)$enforced)
  expect_identical(gate_policy(FALSE)$source, "argument")
  expect_true(gate_policy(TRUE)$enforced)
  expect_identical(gate_policy(TRUE)$source, "argument")
  expect_error(gate_policy("yes"), "TRUE or FALSE")
  expect_error(gate_required(NA), "TRUE or FALSE")
})

test_that("the shipped default blocks an ungated write and a covering gate unblocks it", {
  lf <- tempfile(fileext = ".jsonl")
  dir <- tempfile()
  dir.create(dir)
  old <- options(admiralagent.log_file = lf, admiralagent.require_gate = NULL)
  on.exit(options(old), add = TRUE)

  ir <- a5_ir()
  # the original requirement, under NO option and NO argument: gate absence
  # blocks, and the refusal is itself on the record
  expect_error(write_program_artifact(ir, dir = dir), "requires an approval gate")
  expect_length(list.files(dir, pattern = "[.]R$"), 0L)
  blocked <- a5_events(file.path(dir, "admiralagent_log.jsonl"), "gate_blocked")
  expect_length(blocked, 1L)

  # a covering approval unblocks under the same shipped default
  gate <- sign_gate("H. Approver, Stats Lead", "spec cross-checked",
                    gate_scope(ir), file = lf)
  written <- write_program_artifact(ir, dir = dir, gate = gate)
  expect_length(written, 2L)
  sc <- jsonlite::fromJSON(file.path(dir, written[2]), simplifyVector = FALSE)
  expect_true(sc$gate_enforced)
  expect_identical(sc$release_grade, "gated")
  # and the audit record names the shipped default as the policy source
  rec <- a5_events(file.path(dir, "admiralagent_log.jsonl"), "write_program")
  expect_identical(rec[[1]]$details$gate_policy_source, "default")
  expect_true(rec[[1]]$details$gate_enforced)

  unlink(dir, recursive = TRUE)
})

test_that("an ungated program artifact is self-identifying in code, sidecar, log and on reload", {
  dir <- tempfile()
  dir.create(dir)
  old <- options(admiralagent.require_gate = NULL)
  on.exit(options(old), add = TRUE)

  # the ARGUMENT is the opt-out here, so this also pins that the argument
  # alone reaches the ungated path while the shipped default stays untouched
  written <- suppressMessages(
    write_program_artifact(a5_ir(), dir = dir, require_gate = FALSE)
  )

  # 1. the .R file itself - the artifact that actually circulates
  code <- paste(readLines(file.path(dir, written[1]), warn = FALSE), collapse = "\n")
  expect_match(code, "UNGATED DRAFT", fixed = TRUE)
  expect_match(code, "ungated-draft", fixed = TRUE)
  expect_match(code, "DISCLAIMER", fixed = TRUE)   # the pre-existing header survives
  expect_type(parse(text = code, encoding = "UTF-8"), "expression")

  # 2. the sidecar
  sc <- jsonlite::fromJSON(file.path(dir, written[2]), simplifyVector = FALSE)
  expect_identical(sc$release_grade, "ungated-draft")
  expect_false(sc$gate_enforced)
  expect_null(sc$gate)

  # 3. the audit record
  rec <- a5_events(file.path(dir, "admiralagent_log.jsonl"), "write_program")
  expect_length(rec, 1L)
  expect_identical(rec[[1]]$details$release_grade, "ungated-draft")
  expect_false(rec[[1]]$details$gate_enforced)
  expect_identical(rec[[1]]$details$gate_policy_source, "argument")
  expect_null(rec[[1]]$details$gate_id)

  # 4. on reload
  back <- read_artifact(file.path(dir, written[2]))
  expect_identical(back$release_grade, "ungated-draft")
  expect_false(back$release_ready)
  expect_false(back$gate_enforced)
  expect_null(back$gate)

  unlink(dir, recursive = TRUE)
})

test_that("a gated program artifact is release-grade and records the signer", {
  lf <- tempfile(fileext = ".jsonl")
  dir <- tempfile()
  dir.create(dir)
  old <- options(admiralagent.log_file = lf, admiralagent.require_gate = TRUE)
  on.exit(options(old), add = TRUE)

  ir <- a5_ir()
  # with enforcement on, the ungated write is refused with a clear message
  expect_error(write_program_artifact(ir, dir = dir), "requires an approval gate")
  expect_length(list.files(dir, pattern = "[.]R$"), 0L)

  gate <- sign_gate("H. Approver <h.approver@example.org>, Stats Lead",
                    "spec cross-checked against SAP section 9.2",
                    gate_scope(ir), file = lf)
  written <- write_program_artifact(ir, dir = dir, gate = gate)

  code <- paste(readLines(file.path(dir, written[1]), warn = FALSE), collapse = "\n")
  expect_false(grepl("UNGATED DRAFT", code, fixed = TRUE))
  expect_match(code, gate$gate_id, fixed = TRUE)

  sc <- jsonlite::fromJSON(file.path(dir, written[2]), simplifyVector = FALSE)
  expect_identical(sc$release_grade, "gated")
  expect_true(sc$gate_enforced)

  rec <- a5_events(file.path(dir, "admiralagent_log.jsonl"), "write_program")
  expect_identical(rec[[1]]$details$release_grade, "gated")
  expect_true(rec[[1]]$details$gate_enforced)
  expect_identical(rec[[1]]$details$gate_id, gate$gate_id)

  back <- read_artifact(file.path(dir, written[2]))
  expect_identical(back$release_grade, "gated")
  expect_true(back$release_ready)
  expect_true(back$gate_enforced)
  expect_identical(back$gate$signer, "H. Approver <h.approver@example.org>, Stats Lead")
  expect_identical(back$gate$reason, "spec cross-checked against SAP section 9.2")

  unlink(dir, recursive = TRUE)
})

test_that("a sidecar cannot relabel an unapproved artifact as release-grade", {
  dir <- tempfile()
  dir.create(dir)
  written <- suppressMessages(
    write_program_artifact(a5_ir(), dir = dir, require_gate = FALSE)
  )
  p <- file.path(dir, written[2])

  sc <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  sc$release_grade <- "gated"
  jsonlite::write_json(sc, p, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
  expect_error(read_artifact(p), "release grade drift")

  unlink(dir, recursive = TRUE)
})

test_that("the first ungated write of a session is announced exactly once", {
  had <- gate_notice_env$notified
  gate_notice_env$notified <- NULL
  on.exit(gate_notice_env$notified <- had, add = TRUE)
  old <- options(admiralagent.require_gate = NULL)
  on.exit(options(old), add = TRUE)

  ir <- a5_ir()
  expect_message(
    write_program_artifact(ir, dir = tempfile(), require_gate = FALSE),
    "gating is NOT enforced"
  )
  # once per session, not once per write: a notice on every write is noise, and
  # noise is how a control stops being read
  expect_length(
    capture_messages(write_program_artifact(ir, dir = tempfile(), require_gate = FALSE)),
    0L
  )
})

test_that("REGRESSION GUARD: release grading changed no input to artifact_hash()", {
  expect_identical(
    artifact_hash(classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")),
    "6aea851a"
  )
})
