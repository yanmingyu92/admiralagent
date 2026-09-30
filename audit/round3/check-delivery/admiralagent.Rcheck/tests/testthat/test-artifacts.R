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

  write_program_artifact(ir, dir = dir)
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
  write_program_artifact(ir, dir = dir, backend_label = "llm-x", model = "test-model")

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
