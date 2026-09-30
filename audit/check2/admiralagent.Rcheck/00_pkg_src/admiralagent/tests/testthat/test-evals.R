test_that("evals corpus loads with at least 18 cases and all JSON parses", {
  cases <- load_evals()
  expect_type(cases, "list")
  expect_gte(length(cases), 18)
  ids <- vapply(cases, function(c) as.character(c$id), character(1))
  expect_identical(anyDuplicated(ids), 0L)
  expect_true(all(nzchar(ids)))
})

test_that("every eval case has the required top-level fields", {
  cases <- load_evals()
  fields <- c("id", "dataset", "spec_row", "expected_layers", "expected_needs_human")
  for (f in fields) {
    expect_true(
      all(vapply(cases, function(c) !is.null(c[[f]]), logical(1))),
      label = paste0("field: ", f)
    )
  }
})

test_that("every eval spec_row carries the required spec columns", {
  cases <- load_evals()
  required <- c("variable", "label", "type", "origin", "derivation")
  for (c in cases) {
    for (f in required) {
      val <- c$spec_row[[f]]
      expect_true(
        !is.null(val) && length(val) == 1 && nzchar(as.character(val)),
        label = paste0(c$id, ": ", f)
      )
    }
  }
})

test_that("rules backend reproduces the corpus with accuracy 1.0 in every dataset", {
  cases <- load_evals()
  datasets <- unique(vapply(cases, function(c) as.character(c$dataset), character(1)))
  for (ds in datasets) {
    res <- suppressMessages(run_evals(backend = "rules", dataset = ds))
    expect_identical(evals_accuracy(res), 1)
    expect_true(all(res$ok), label = paste0("dataset: ", ds))
  }
})

test_that("run_evals returns the documented columns and filters by dataset", {
  cases <- load_evals()
  n_adsl <- sum(vapply(cases, function(c) identical(as.character(c$dataset), "ADSL"), logical(1)))
  res <- suppressMessages(run_evals(backend = "rules", dataset = "ADSL"))
  expect_s3_class(res, "data.frame")
  expect_named(res, c("id", "variable", "expected", "got", "ok"))
  expect_identical(nrow(res), n_adsl)
})

test_that("evals_accuracy returns a single numeric in [0, 1]", {
  res <- suppressMessages(run_evals(backend = "rules", dataset = "ADSL"))
  acc <- evals_accuracy(res)
  expect_type(acc, "double")
  expect_length(acc, 1L)
  expect_gte(acc, 0)
  expect_lte(acc, 1)
})

test_that("llm backend refuses to run without a chat object (zero network usage)", {
  expect_error(run_evals(backend = "llm"), "chat")
})
