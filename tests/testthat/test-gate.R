# Approval gate tests.
#
# POSITIONING: a gate is an approval RECORD with an identified signer, a
# moment, a reason and a scope. It is not a claim that a derivation is correct,
# and nothing here substitutes for output-data double programming. These tests
# pin the mechanics of recording and blocking, nothing about correctness.

gate_lines <- function(file) {
  lines <- readLines(file, warn = FALSE)
  lines[nzchar(trimws(lines))]
}

gate_events <- function(file, event) {
  recs <- lapply(gate_lines(file), jsonlite::fromJSON, simplifyVector = FALSE)
  Filter(function(r) identical(r$event, event), recs)
}

# one executable variable and one that abstained, so the abstention channel is
# exercised on an IR that still renders real code
gate_test_ir <- function() {
  list(
    new_variable_ir("ADSL", "SITEID", list(
      new_step("assign", list(target = "SITEID", literal = "S1"))
    )),
    new_variable_ir("ADSL", "AGEGR1", list(
      new_step("assign", list(target = "AGEGR1", literal = "PENDING"))
    ), needs_human = TRUE, rationale = "cut points not stated in the spec")
  )
}

write_gate_artifact <- function(ir, ...) {
  dir <- tempfile()
  dir.create(dir)
  written <- write_program_artifact(ir, dir = dir, ...)
  list(dir = dir, code = file.path(dir, written[1]), sidecar = file.path(dir, written[2]))
}

rewrite_sidecar <- function(path, sc) {
  jsonlite::write_json(sc, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
}

test_that("a sidecar with needs_human flipped from TRUE to FALSE is rejected on reload", {
  art <- write_gate_artifact(gate_test_ir(), require_gate = FALSE)
  expect_true(is.list(read_artifact(art$sidecar)$ir))

  sc <- jsonlite::fromJSON(art$sidecar, simplifyVector = FALSE)
  flagged <- which(vapply(sc$ir, function(v) isTRUE(v$needs_human), logical(1)))
  expect_length(flagged, 1L)
  sc$ir[[flagged]]$needs_human <- FALSE
  rewrite_sidecar(art$sidecar, sc)

  expect_error(read_artifact(art$sidecar), "hash drift")
})

test_that("flipping needs_human and re-sealing the sidecar hash is still rejected", {
  # the sidecar is fully editable, so an attacker recomputes ir_hash to match
  # the flipped IR. The rendered code does not follow: the abstention block is
  # still in the .R file, and that mismatch is the backstop.
  art <- write_gate_artifact(gate_test_ir(), require_gate = FALSE)
  sc <- jsonlite::fromJSON(art$sidecar, simplifyVector = FALSE)
  flagged <- which(vapply(sc$ir, function(v) isTRUE(v$needs_human), logical(1)))
  sc$ir[[flagged]]$needs_human <- FALSE

  forged <- gate_test_ir()
  forged[[2]]$needs_human <- FALSE
  sc$ir_hash <- artifact_hash(forged)
  rewrite_sidecar(art$sidecar, sc)

  expect_error(read_artifact(art$sidecar), "abstention drift")
})

test_that("a hand-edited rendered .R is rejected on reload", {
  art <- write_gate_artifact(gate_test_ir(), require_gate = FALSE)
  code <- readLines(art$code, warn = FALSE)
  writeLines(c(code, "ADSL$SITEID <- \"TAMPERED\""), art$code)

  expect_error(read_artifact(art$sidecar), "digest drift")
})

test_that("a renamed or mismatched artifact file name is rejected on reload", {
  art <- write_gate_artifact(gate_test_ir(), require_gate = FALSE)

  # both files renamed together: the sidecar still names the original artifact
  renamed_code <- file.path(art$dir, "adsl__program__deadbeef.R")
  renamed_sc <- paste0(renamed_code, ".json")
  expect_true(file.rename(art$code, renamed_code))
  expect_true(file.rename(art$sidecar, renamed_sc))
  expect_error(read_artifact(renamed_sc), "name drift")

  # and a sidecar whose IR simply does not hash to the name it carries
  art2 <- write_gate_artifact(gate_test_ir(), require_gate = FALSE)
  sc <- jsonlite::fromJSON(art2$sidecar, simplifyVector = FALSE)
  sc$ir_hash <- NULL
  sc$artifact <- "adsl__program__00000000.R"
  moved <- file.path(art2$dir, paste0(sc$artifact, ".json"))
  rewrite_sidecar(moved, sc)
  expect_error(read_artifact(moved), "hash drift")
})

test_that("a valid gate records signer, timestamp, reason and scope recoverably", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  ir <- gate_test_ir()
  gate <- sign_gate(
    signer = "Dr A. Reviewer <a.reviewer@example.org>, Stats Programming Lead",
    reason = "spec cross-checked against SAP section 9.2",
    scope = gate_scope(ir)
  )
  expect_s3_class(gate, "aa_gate")
  expect_identical(gate$decision, "approve")
  expect_true(nzchar(gate$gate_id))

  # recoverable from the log
  recovered <- read_gates(lf)
  expect_length(recovered, 1L)
  expect_identical(recovered[[1]]$signer, gate$signer)
  expect_identical(recovered[[1]]$reason, gate$reason)
  expect_identical(recovered[[1]]$time, gate$time)
  expect_identical(recovered[[1]]$scope, gate$scope)
  expect_identical(recovered[[1]]$gate_id, gate$gate_id)

  # recoverable from the artifact it approved, and reproduced in the code
  art <- write_gate_artifact(ir, gate = gate, require_gate = TRUE)
  back <- read_artifact(art$sidecar)
  expect_identical(back$gate$gate_id, gate$gate_id)
  expect_identical(back$gate$signer, gate$signer)
  expect_identical(back$gate$time, gate$time)
  code <- paste(readLines(art$code, warn = FALSE), collapse = "\n")
  expect_match(code, gate$gate_id, fixed = TRUE)
  expect_match(code, "a.reviewer@example.org", fixed = TRUE)
  expect_match(code, "not\n# evidence that any derivation is correct", fixed = TRUE)

  # editing the signer in the sidecar copy no longer matches the gate id
  sc <- jsonlite::fromJSON(art$sidecar, simplifyVector = FALSE)
  sc$gate$signer <- "Someone Else"
  rewrite_sidecar(art$sidecar, sc)
  expect_error(read_artifact(art$sidecar), "gate_id does not match")
})

test_that("write_program_artifact is blocked when a required gate is absent", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf, admiralagent.require_gate = TRUE)
  on.exit(options(admiralagent.log_file = NULL, admiralagent.require_gate = NULL), add = TRUE)
  on.exit(options(old), add = TRUE)

  ir <- gate_test_ir()
  dir <- tempfile()
  dir.create(dir)
  expect_error(write_program_artifact(ir, dir = dir), "requires an approval gate")
  expect_length(list.files(dir, pattern = "[.]R$"), 0L)
  # the refusal is itself on the record
  blocked <- gate_events(file.path(dir, "admiralagent_log.jsonl"), "gate_blocked")
  expect_length(blocked, 1L)
  expect_identical(blocked[[1]]$details$action, "write_program_artifact()")

  # a gate signed for other content does not carry over
  other <- sign_gate("B. Lead", "approved the previous cut", gate_scope(ir[1]), file = lf)
  expect_error(write_program_artifact(ir, dir = dir, gate = other), "does not cover")

  # a rejection blocks too, and names who refused
  no <- sign_gate("C. QA", "derivation disputed", gate_scope(ir), decision = "reject", file = lf)
  expect_error(write_program_artifact(ir, dir = dir, gate = no), "rejected by C. QA")

  # the covering approval unblocks
  yes <- sign_gate("C. QA", "resolved with the statistician", gate_scope(ir), file = lf)
  written <- write_program_artifact(ir, dir = dir, gate = yes)
  expect_length(written, 2L)
  expect_true(file.exists(file.path(dir, written[1])))

  # the shipped default also enforces: with the option cleared, an ungated
  # write is still refused, and only an explicit opt-out argument allows one
  options(admiralagent.require_gate = NULL)
  expect_error(write_program_artifact(ir, dir = tempfile()), "requires an approval gate")
  expect_length(
    suppressMessages(write_program_artifact(ir, dir = tempfile(), require_gate = FALSE)), 2L
  )
})

test_that("needs_human is clearable only through a gate", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  ir <- gate_test_ir()
  expect_error(gate_clear_needs_human(ir, NULL), "requires an approval gate")
  expect_error(gate_clear_needs_human(ir, list(signer = "X")), "invalid approval gate")

  wrong <- sign_gate("D. Stat", "approved the whole program", gate_scope(ir))
  expect_error(gate_clear_needs_human(ir, wrong), "does not cover")

  gate <- sign_gate("D. Stat", "cut points agreed with the sponsor",
                    scope = "variable:ADSL:AGEGR1")
  cleared <- gate_clear_needs_human(ir, gate)
  expect_false(cleared[[2]]$needs_human)
  expect_true(ir[[2]]$needs_human)  # the input IR is not mutated
  expect_length(validate_ir(cleared), 0L)

  # who cleared what is recoverable
  rec <- gate_events(lf, "needs_human_cleared")
  expect_length(rec, 1L)
  expect_identical(rec[[1]]$details$signer, "D. Stat")
  expect_identical(rec[[1]]$details$gate_id, gate$gate_id)
  expect_identical(rec[[1]]$details$reason, "cut points agreed with the sponsor")
  expect_identical(rec[[1]]$details$variables[[1]], "AGEGR1")
  expect_identical(rec[[1]]$details$hash_before, artifact_hash(ir))
  expect_identical(rec[[1]]$details$hash_after, artifact_hash(cleared))

  # clearing a flag that was never raised is refused rather than silently no-op
  expect_error(gate_clear_needs_human(cleared, gate), "flagged for human review")
})

test_that("gate records verify as part of the existing hash chain", {
  lf <- tempfile(fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)

  ir <- gate_test_ir()
  gate <- sign_gate("E. Signer", "checked", gate_scope(ir))
  execute_ir(ir, sources = list(base = data.frame(USUBJID = c("a", "b"))))
  write_gate_artifact(ir, gate = gate)
  log_run("unit_event", list(i = 1))

  res <- verify_log(lf)
  expect_true(res$ok)
  expect_gte(res$records, 4L)
  events <- vapply(
    lapply(gate_lines(lf), jsonlite::fromJSON, simplifyVector = FALSE),
    function(r) r$event, character(1)
  )
  expect_true(all(c("gate", "execute_variable", "unit_event") %in% events))

  # editing the gate record in place breaks the chain like any other record
  lines <- gate_lines(lf)
  i <- which(events == "gate")[[1]]
  lines[i] <- sub("E. Signer", "F. Forger", lines[i], fixed = TRUE)
  forged <- tempfile(fileext = ".jsonl")
  writeLines(lines, forged)
  broken <- verify_log(forged)
  expect_false(broken$ok)
  expect_identical(broken$broken_line, i)
  expect_identical(broken$broken_event, "gate")
})

test_that("a gate cannot be signed where it could not be recorded", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  expect_error(sign_gate("G. Ghost", "no trail", "*"), "logging is switched off")
})

test_that("REGRESSION GUARD: the pinned rules-backend artifact hash is unchanged", {
  expect_identical(
    artifact_hash(classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")),
    "84a18650"
  )
  # an ungated program renders byte-identically to how it rendered before gates
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_identical(render_program(ir), render_program(ir, gate = NULL))
})
