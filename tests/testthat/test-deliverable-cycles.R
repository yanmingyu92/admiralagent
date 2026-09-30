# validate_ir() is fail-closed on deliverable-level cycles: deliverable_graph()
# projects the variable graph onto v$dataset nodes, and a cycle between
# deliverables means no build order exists at all. Unlike a variable-level
# cycle - which order_variables() still resolves via rank fallback into a
# well-formed program - this is an unconditional problem.

cyc_producer <- function(dataset, target, from) {
  new_variable_ir(dataset, target, list(new_step("assign", list(target = target, from = from))))
}

cyc_merge <- function(dataset, variable, source, dataset_add) {
  new_variable_ir(dataset, variable, list(new_step("merge_var", list(
    target = variable, source = source, dataset_add = dataset_add,
    by_vars = c("STUDYID", "USUBJID"), mode = "first"
  ))))
}

# ADSL produces TRTSDTM, ADTTE merges it; ADTTE produces CNSR, ADSL merges it.
# Each variable-level edge is acyclic; only the dataset projection closes.
adsl_adtte_cycle_ir <- function() {
  list(
    cyc_producer("ADSL", "TRTSDTM", "RFXSTDTC"),
    cyc_merge("ADTTE", "STARTDTM", "TRTSDTM", "ADSL"),
    cyc_producer("ADTTE", "CNSR", "EVNTDESC"),
    cyc_merge("ADSL", "LSTCNSR", "CNSR", "ADTTE")
  )
}

# Two ADSL variables consuming each other's target: the variable graph cycles,
# the deliverable graph does not (self edges are dropped).
variable_cycle_ir <- function() {
  list(
    cyc_producer("ADSL", "AAGE", "BAGE"),
    cyc_producer("ADSL", "BAGE", "AAGE")
  )
}

VARIABLE_CYCLE_MESSAGE <- "cyclic dependencies: revise derivation inputs before execution"

test_that("validate_ir rejects a genuine ADSL<->ADTTE deliverable cycle", {
  ir <- adsl_adtte_cycle_ir()

  expect_equal(deliverable_graph(ir)$cycles, list(c("ADSL", "ADTTE")))
  expect_false(is_valid_ir(ir))

  problems <- validate_ir(ir)
  cycle_problem <- grep("cyclic deliverable dependencies", problems, value = TRUE)
  expect_length(cycle_problem, 1L)
  expect_match(cycle_problem, "ADSL -> ADTTE", fixed = TRUE)
})

test_that("the deliverable cycle message is distinguishable from the variable one", {
  deliverable_problems <- validate_ir(adsl_adtte_cycle_ir())
  variable_problems <- validate_ir(variable_cycle_ir())

  # The variable-level gate fires on its own IR and only there.
  expect_true(VARIABLE_CYCLE_MESSAGE %in% variable_problems)
  expect_false(VARIABLE_CYCLE_MESSAGE %in% deliverable_problems)

  # ... and the deliverable gate fires only on the deliverable cycle.
  expect_false(any(grepl("cyclic deliverable dependencies", variable_problems)))
  expect_equal(deliverable_graph(variable_cycle_ir())$cycles, list())

  deliverable_message <- grep("cyclic deliverable dependencies", deliverable_problems, value = TRUE)
  expect_false(identical(deliverable_message, VARIABLE_CYCLE_MESSAGE))
  # The deliverable message names the datasets; the variable one names nothing.
  expect_match(deliverable_message, "ADSL", fixed = TRUE)
  expect_match(deliverable_message, "ADTTE", fixed = TRUE)
  expect_false(grepl("ADSL", VARIABLE_CYCLE_MESSAGE, fixed = TRUE))
})

test_that("cycle members are listed deterministically regardless of IR order", {
  forward <- grep("cyclic deliverable", validate_ir(adsl_adtte_cycle_ir()), value = TRUE)
  reversed <- grep("cyclic deliverable", validate_ir(rev(adsl_adtte_cycle_ir())), value = TRUE)

  expect_equal(forward, reversed)
})

test_that("the deliverable check is fail-closed for render_program and execution", {
  ir <- adsl_adtte_cycle_ir()

  expect_error(assert_valid_ir(ir), "cyclic deliverable dependencies")
  expect_error(render_program(ir), "cyclic deliverable dependencies")
})

test_that("a malformed IR still returns shape problems and does not error", {
  # deliverable_graph() stops on malformed input, so validate_ir() must keep
  # running validate_ir_shape() first; otherwise this turns into a hard error.
  malformed <- list(list(dataset = "ADSL", variable = "AGE"))
  expect_error(deliverable_graph(malformed), "aa_variable_ir")

  problems <- expect_no_error(validate_ir(malformed))
  expect_gt(length(problems), 0L)
  expect_match(problems[[1]], "aa_variable_ir")
  expect_false(any(grepl("cyclic deliverable dependencies", problems)))

  expect_no_error(validate_ir("not an ir"))
  expect_no_error(validate_ir(list()))
})

test_that("REGRESSION: single-dataset mock specs stay cycle-free and valid", {
  for (dataset in c("ADSL", "ADVS", "ADTTE")) {
    spec <- switch(dataset, ADSL = mock_spec_adsl(), ADVS = mock_spec_advs(), ADTTE = mock_spec_adtte())
    ir <- classify_variables(spec, dataset, backend = "rules")

    expect_equal(deliverable_graph(ir)$cycles, list())
    expect_length(validate_ir(ir), 0L)
  }
})

test_that("REGRESSION: pinned ADSL goldens are unchanged by the new gate", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")

  expect_equal(artifact_hash(ir), "6aea851a")
  expect_equal(
    vapply(order_variables(ir), function(v) v$variable, character(1)),
    c("TRTSDTM", "TRTEDTM", "AGE", "RACEN", "STUDYID", "USUBJID", "BMIBL", "SUBJID", "TRT01P", "AGEGR1")
  )
  expect_length(validate_ir(ir), 0L)
})
