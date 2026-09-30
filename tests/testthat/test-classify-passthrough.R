# classify_variables() -> classify_variables_llm() passthrough (audit finding A10).
# In dev-source mode (ADMIRALAGENT_DEV_SOURCE=1) helper.R sources R/*.R into a
# shared env, so we shim the binding in environment(classify_variables)
# directly and restore it on exit. Under test_check() that environment is the
# locked installed namespace, so we rebind through local_mocked_bindings
# instead (same idiom as test-vocab-new.R).
with_llm_shim <- function(mock, code) {
  env <- environment(classify_variables)
  if (bindingIsLocked("classify_variables_llm", env)) {
    local_mocked_bindings(classify_variables_llm = mock, .package = "admiralagent")
    return(force(code))
  }
  old <- get("classify_variables_llm", envir = env)
  assign("classify_variables_llm", mock, envir = env)
  on.exit(assign("classify_variables_llm", old, envir = env), add = TRUE)
  force(code)
}

capture_mock <- function(record) {
  function(vars, chat, max_attempts = 2, batch_size = 4,
           samples = 1, consensus = c("majority", "first"),
           prompt_variant = c("full", "neutral", "minimal")) {
    record$vars <- vars
    record$chat <- chat
    record$samples <- samples
    record$consensus <- consensus
    record$prompt_variant <- prompt_variant
    list()
  }
}

test_that("classify_variables() threads samples/consensus/prompt_variant to the llm backend", {
  # Arrange
  spec <- mock_spec_adsl()
  dummy_chat <- structure(list(), class = "aa_dummy_chat")
  record <- new.env(parent = emptyenv())

  # Act
  with_llm_shim(capture_mock(record), {
    classify_variables(
      spec, "ADSL",
      backend = "llm", chat = dummy_chat,
      samples = 3, consensus = "first", prompt_variant = "neutral"
    )
  })

  # Assert: the mock received exactly the supplied values
  expect_identical(record$samples, 3)
  expect_identical(record$consensus, "first")
  expect_identical(record$prompt_variant, "neutral")
  expect_identical(record$chat, dummy_chat)
  expect_identical(record$vars, spec_variables(spec, "ADSL"))
})

test_that("classify_variables() llm defaults match classify_variables_llm()'s own defaults", {
  # Arrange
  spec <- mock_spec_adsl()
  dummy_chat <- structure(list(), class = "aa_dummy_chat")
  record <- new.env(parent = emptyenv())

  # Act: no samples/consensus/prompt_variant supplied by the caller
  with_llm_shim(capture_mock(record), {
    classify_variables(spec, "ADSL", backend = "llm", chat = dummy_chat)
  })

  # Assert: defaults arrive identical to classify_variables_llm()'s signature
  expect_identical(record$samples, 1)
  expect_identical(record$consensus, c("majority", "first"))
  expect_identical(record$prompt_variant, c("full", "neutral", "minimal"))
})

test_that("with_llm_shim restores the real classify_variables_llm binding", {
  env <- environment(classify_variables)
  before <- get("classify_variables_llm", envir = env)
  with_llm_shim(function(...) list(), invisible(NULL))
  expect_identical(get("classify_variables_llm", envir = env), before)
})

test_that("rules backend output is unchanged and ignores the new llm-only args", {
  # Arrange
  spec <- mock_spec_adsl()

  # Act
  pre_change_equivalent <- rules_engine(spec_variables(spec, "ADSL"))
  with_defaults <- classify_variables(spec, "ADSL", backend = "rules")
  with_explicit <- classify_variables(
    spec, "ADSL",
    backend = "rules",
    samples = 5, consensus = "first", prompt_variant = "minimal"
  )

  # Assert: identical to the pre-change code path, defaults or not
  expect_identical(with_defaults, pre_change_equivalent)
  expect_identical(with_explicit, pre_change_equivalent)
  expect_identical(artifact_hash(with_explicit), artifact_hash(pre_change_equivalent))
})

test_that("backend = 'llm' with chat = NULL still stops with the existing message", {
  expect_error(
    classify_variables(mock_spec_adsl(), "ADSL", backend = "llm"),
    "backend = 'llm' requires an ellmer chat object",
    fixed = TRUE
  )
})
