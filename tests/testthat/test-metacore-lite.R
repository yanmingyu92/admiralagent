racen_spec <- function() {
  read_spec_df(data.frame(
    dataset = "ADSL",
    variable = "RACEN",
    label = "Race (N)",
    type = "integer",
    origin = "Derived",
    derivation = "Numeric race code derived from RACE using the RACE codelist",
    stringsAsFactors = FALSE
  ))
}

test_that("codelist_from_data builds code/decode from observed values", {
  df <- data.frame(RACE = c("WHITE", "ASIAN", "WHITE", NA, "BLACK"), stringsAsFactors = FALSE)
  cl <- codelist_from_data("RACE", df)
  expect_named(cl, c("code", "decode"))
  expect_identical(cl$decode, c("ASIAN", "BLACK", "WHITE"))
  expect_identical(cl$code, 1:3)
  expect_error(codelist_from_data("NOPE", df), "RACE|NOPE|containing")
})

test_that("codelist_from_data errors on bad var/data", {
  expect_error(codelist_from_data("", data.frame(a = 1)), "var")
  expect_error(codelist_from_data("a", NULL), "data.frame")
})

test_that("mock_metacore returns NULL with warning when metacore is missing", {
  if (requireNamespace("metacore", quietly = TRUE)) {
    skip("metacore installed; NULL fallback branch not reachable")
  }
  spec <- racen_spec()
  expect_warning(
    res <- mock_metacore(spec, codelists = list(RACE = data.frame(code = 1:2, decode = c("A", "B")))),
    "metacore"
  )
  expect_null(res)
})

test_that("mock_metacore validates codelists arg", {
  expect_error(
    mock_metacore(racen_spec(), codelists = list(RACE = data.frame(code = 1:2))),
    "code/decode"
  )
})

test_that("mock_metacore warns when a codelist variable has no codelist", {
  expect_warning(mock_metacore(racen_spec(), codelists = list(OTHER = data.frame(
    code = 1:2, decode = c("A", "B")
  ))), "RACEN")
})

test_that("create_var_from_codelist on mock_metacore matches hand-built mapping", {
  skip_if_not_installed("metacore")
  skip_if_not_installed("metatools")
  skip_if_not_installed("pharmaversesdtm")
  suppressMessages(library(pharmaversesdtm))
  e <- new.env(parent = globalenv())
  data("dm", envir = e)

  cl <- codelist_from_data("RACE", e$dm)
  mc <- mock_metacore(racen_spec(), codelists = list(RACE = cl))
  expect_s3_class(mc, "Metacore")

  out <- metatools::create_var_from_codelist(
    e$dm, metacore = mc, input_var = RACE, out_var = RACEN, decode_to_code = TRUE
  )
  expected <- match(e$dm$RACE, cl$decode)
  expect_true("RACEN" %in% names(out))
  expect_identical(as.integer(out$RACEN), as.integer(expected))
  expect_true(all(!is.na(out$RACEN)))
})

test_that("mock_metacore links codelist via spec codelist column too", {
  skip_if_not_installed("metacore")
  spec <- racen_spec()
  spec$codelist <- "RACE"
  spec$derivation <- "Numeric race code"  # no codelist mention in text
  mc <- mock_metacore(spec, codelists = list(RACE = data.frame(
    code = 1:2, decode = c("A", "B")
  )))
  expect_s3_class(mc, "Metacore")
  vs <- as.data.frame(mc$value_spec)
  expect_identical(as.character(vs$code_id), "RACE")
})

test_that("mock_metacore returns full object for multi-dataset specs", {
  skip_if_not_installed("metacore")
  spec <- read_spec_df(data.frame(
    dataset = c("ADSL", "ADVS"),
    variable = c("RACEN", "PARAMCD"),
    label = "x", type = "text", origin = "Derived",
    derivation = c("race code", "copied"),
    stringsAsFactors = FALSE
  ))
  mc <- mock_metacore(spec)
  expect_s3_class(mc, "Metacore")
  sub <- suppressWarnings(suppressMessages(metacore::select_dataset(mc, "ADVS")))
  expect_s3_class(sub, "Metacore")
  expect_identical(as.character(as.data.frame(sub$ds_vars)$variable), "PARAMCD")
})
