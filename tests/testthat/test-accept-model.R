# Model acceptance gate: prespecified thresholds, fail-closed decision,
# digest-only audit record. The stub candidate abstains on every variable,
# which is deterministic: exactly the corpus's expected_needs_human cases
# score as correct, and only those cases agree with the rules baseline.

# Reply built from the prompt itself: one abstention per requested variable,
# so any batch composition aligns. Reusable across unlimited calls.
abstain_chat <- function() {
  list(chat = function(prompt) {
    hits <- regmatches(prompt, gregexpr('"variable"\\s*:\\s*"[^"]+"', prompt))[[1]]
    names <- unique(sub('.*"([^"]+)"\\s*$', "\\1", hits))
    recs <- lapply(names, function(nm) {
      list(dataset = "ADSL", variable = nm, steps = list(), confidence = 0.1,
           needs_human = TRUE, rationale = "stub abstains", spec_origin = "x")
    })
    as.character(jsonlite::toJSON(recs, auto_unbox = TRUE))
  })
}

test_that("thresholds must be prespecified (no hidden defaults)", {
  expect_error(accept_model(abstain_chat()), "prespecified")
  expect_error(accept_model(abstain_chat(), min_eval_accuracy = 0.4), "prespecified")
  expect_error(accept_model(abstain_chat(), min_eval_accuracy = 2, min_full_agreement = 0.4), "\\[0, 1\\]")
})

test_that("a fully abstaining candidate passes low thresholds and fails strict ones", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  res <- accept_model(abstain_chat(), min_eval_accuracy = 0.3, min_full_agreement = 0.3)
  expect_s3_class(res, "aa_model_acceptance")
  expect_true(res$accepted)
  expect_length(res$reasons, 0)
  expect_equal(res$metrics$eval_accuracy, 7 / 20, tolerance = 1e-6)
  expect_equal(res$metrics$full_agreement, 7 / 20, tolerance = 1e-6)

  strict <- accept_model(abstain_chat(), min_eval_accuracy = 0.9, min_full_agreement = 0.4)
  expect_false(strict$accepted)
  expect_match(strict$reasons, "eval accuracy", all = FALSE)

  strict2 <- accept_model(abstain_chat(), min_eval_accuracy = 0.4, min_full_agreement = 0.9)
  expect_false(strict2$accepted)
  expect_match(strict2$reasons, "full-semantics agreement", all = FALSE)
})

test_that("pipeline errors reject the candidate instead of crashing", {
  broken <- list(chat = function(prompt) stop("provider unreachable"))
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  res <- accept_model(broken, min_eval_accuracy = 0.3, min_full_agreement = 0.3)
  expect_false(res$accepted)
  expect_match(res$reasons, "pipeline error: .*provider unreachable")
  expect_true(is.na(res$metrics$eval_accuracy))
})

test_that("the acceptance decision is logged digest-only and the chain verifies", {
  lf <- tempfile(pattern = "aa_accept_", fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)
  accept_model(abstain_chat(), min_eval_accuracy = 0.3, min_full_agreement = 0.3,
               model_label = "stub-model")
  raw <- readLines(lf)
  entry <- jsonlite::fromJSON(raw[[length(raw)]])
  expect_identical(entry$event, "model_acceptance")
  expect_true(entry$details$accepted)
  expect_identical(entry$details$model, "stub-model")
  expect_match(entry$details$corpus, "^corpus:[0-9a-f]{16}$")
  expect_null(entry$details$spec_origin)
  expect_true(verify_log(lf)$ok)
})

test_that("print method shows the verdict and prespecified thresholds", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  res <- accept_model(abstain_chat(), min_eval_accuracy = 0.9, min_full_agreement = 0.4)
  out <- capture.output(print(res))
  expect_true(any(grepl("REJECTED", out)))
  expect_true(any(grepl("min 0.900", out)))
  expect_true(any(grepl("not correctness", out)))
})
