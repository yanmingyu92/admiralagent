# Unit tests for the per-variable executor extracted from execute_ir().
# execute_ir() itself stays covered by test-execute.R; here we drive
# execute_ir_one() directly against an environment we seed ourselves.

# Mirrors exactly how execute_ir() seeds its execution environment, so a
# direct execute_ir_one() call starts from the same state the loop would.
seed_exec_env <- function(target, sources) {
  env <- new.env(parent = baseenv())
  env[[target]] <- sources$base
  for (nm in names(sources)) {
    if (!identical(nm, "base")) assign(nm, sources[[nm]], envir = env)
  }
  if (requireNamespace("rlang", quietly = TRUE)) env$exprs <- rlang::exprs
  if (requireNamespace("admiral", quietly = TRUE)) env$params <- admiral::params
  env
}

assign_ir <- function(target = "STUDYID", literal = "ABC") {
  new_variable_ir("ADSL", "STUDYID", list(
    new_step("assign", list(target = target, literal = literal))
  ))
}

duration_ir <- function() {
  new_variable_ir("ADSL", "AGE", list(
    new_step("duration", list(
      target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years"
    ))
  ))
}

dated_base <- function() {
  data.frame(
    USUBJID = c("a", "b"),
    BRTHDT = as.Date(c("1970-01-01", "1980-06-15")),
    TRTSDT = as.Date(c("2020-01-01", "2020-01-01")),
    stringsAsFactors = FALSE
  )
}

test_that("execute_ir_one on a seeded env matches the single-variable execute_ir call", {
  base <- data.frame(USUBJID = c("a", "b"), STALE = c(1, 2), stringsAsFactors = FALSE)
  v <- assign_ir()

  wrapped <- execute_ir(list(v), sources = list(base = base))
  env <- seed_exec_env("ADSL", list(base = base))
  direct <- execute_ir_one(v, env, character(), TRUE)

  expect_equal(direct$rows, wrapped$status)
  expect_identical(direct$rows$status, "EXECUTED")
  expect_identical(direct$failed_outputs, character())
  # same resulting target dataset, column order included
  expect_identical(names(env$ADSL), names(wrapped$adsl))
  expect_equal(env$ADSL, wrapped$adsl)
})

test_that("execute_ir_one mutates the passed-in env on success", {
  base <- data.frame(USUBJID = c("a", "b"), stringsAsFactors = FALSE)
  env <- seed_exec_env("ADSL", list(base = base))
  before <- env$ADSL
  expect_false("STUDYID" %in% names(env$ADSL))

  res <- execute_ir_one(assign_ir(), env, character(), TRUE)

  expect_identical(res$rows$status, "EXECUTED")
  expect_true("STUDYID" %in% names(env$ADSL))
  expect_identical(env$ADSL$STUDYID, rep("ABC", 2))
  # the caller's environment object is updated in place, not replaced
  expect_identical(names(before), names(base))
})

test_that("execute_ir_one rolls the env back on failure and grows failed_outputs", {
  base <- data.frame(USUBJID = c("a", "b"), stringsAsFactors = FALSE)
  env <- seed_exec_env("ADSL", list(base = base))
  # step 1 succeeds (writes TMPFLAG on the work copy), step 2 fails on the
  # missing BRTHDT/TRTSDT inputs: nothing may reach env
  v <- new_variable_ir("ADSL", "AGE", list(
    new_step("assign", list(target = "TMPFLAG", literal = "Y")),
    new_step("duration", list(
      target = "AGE", start = "BRTHDT", end = "TRTSDT", out_unit = "years"
    ))
  ))
  expect_setequal(
    variable_product_keys(v),
    c("ADSL::column::TMPFLAG", "ADSL::column::AGE")
  )

  res <- execute_ir_one(v, env, "ADSL::column::ZZZ", TRUE)

  expect_identical(res$rows$status, "ERROR")
  expect_true(nzchar(res$rows$note))
  # transactional rollback: neither the failed target nor the earlier step's
  # column is visible in the caller's environment
  expect_identical(env$ADSL, base)
  expect_false("TMPFLAG" %in% names(env$ADSL))
  expect_false("AGE" %in% names(env$ADSL))
  # failed_outputs keeps what it was given and gains this variable's products
  expect_setequal(
    res$failed_outputs,
    c("ADSL::column::ZZZ", "ADSL::column::TMPFLAG", "ADSL::column::AGE")
  )
})

test_that("execute_ir_one blocks a variable whose input is in failed_outputs", {
  base <- dated_base()
  env <- seed_exec_env("ADSL", list(base = base))
  v <- duration_ir()
  expect_true("ADSL::column::BRTHDT" %in% variable_input_keys(v))

  res <- execute_ir_one(v, env, "ADSL::column::BRTHDT", TRUE)

  expect_identical(res$rows$status, "ERROR")
  expect_identical(res$rows$note, "upstream derivation failed; stale inputs are not used")
  # nothing was evaluated: the env is untouched even though the inputs exist
  # and the derivation would otherwise have succeeded
  expect_identical(env$ADSL, base)
  expect_setequal(
    res$failed_outputs,
    c("ADSL::column::BRTHDT", "ADSL::column::AGE")
  )
})

test_that("execute_ir_one reports REVIEW without touching the env", {
  base <- data.frame(USUBJID = "a", stringsAsFactors = FALSE)
  env <- seed_exec_env("ADSL", list(base = base))
  v <- new_variable_ir("ADSL", "AGEGR1", list(), needs_human = TRUE,
                       rationale = "no rule matched")

  res <- execute_ir_one(v, env, character(), TRUE)

  expect_identical(res$rows$status, "REVIEW")
  expect_identical(res$rows$note, "needs human decision")
  expect_identical(res$rows$variable, "AGEGR1")
  expect_identical(res$failed_outputs, character())
  expect_identical(env$ADSL, base)
})

test_that("execute_ir_one keeps the idempotency guard: re-running drops prior outputs", {
  skip_if_not_installed("admiral")
  base <- dated_base()
  base$AGE <- c(-1, -1) # stale output from an earlier run
  v <- duration_ir()
  expect_identical(step_output_columns(v$steps[[1]]), "AGE")

  env <- seed_exec_env("ADSL", list(base = base))
  first <- execute_ir_one(v, env, character(), TRUE)
  expect_identical(first$rows$status, "EXECUTED")
  after_first <- env$ADSL
  # the guard dropped the stale column and the step re-appended it
  expect_identical(sum(names(after_first) == "AGE"), 1L)
  expect_false(any(after_first$AGE == -1))

  second <- execute_ir_one(v, env, character(), TRUE)
  expect_identical(second$rows, first$rows)
  expect_identical(names(env$ADSL), names(after_first))
  expect_equal(env$ADSL, after_first)

  # and identical to what the execute_ir() wrapper produces on the same input
  wrapped <- execute_ir(list(v), sources = list(base = base))
  expect_identical(names(wrapped$adsl), names(after_first))
  expect_equal(wrapped$adsl, after_first)
})

test_that("execute_ir_one prints nothing and honours quiet = FALSE", {
  base <- data.frame(USUBJID = c("a", "b"), stringsAsFactors = FALSE)
  env_quiet <- seed_exec_env("ADSL", list(base = base))
  env_loud <- seed_exec_env("ADSL", list(base = base))

  quiet_res <- execute_ir_one(assign_ir(), env_quiet, character(), TRUE)
  # status printing stays a concern of execute_ir(), not of the per-variable step
  loud_res <- expect_silent(execute_ir_one(assign_ir(), env_loud, character(), FALSE))

  expect_identical(loud_res$rows, quiet_res$rows)
  expect_equal(env_loud$ADSL, env_quiet$ADSL)
})
