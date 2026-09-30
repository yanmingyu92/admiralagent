pilot1_define <- file.path("..", "..", "..", "cdisc_data", "pilot1", "m5",
                           "datasets", "rconsortiumpilot1", "analysis", "adam",
                           "datasets", "define.xml")
pilot2_define <- file.path("..", "..", "..", "cdisc_data", "pilot2", "m5",
                           "datasets", "rconsortiumpilot2", "analysis", "adam",
                           "datasets", "define.xml")

test_that("parse_define extracts per-variable metadata incl. derivations (pilot1)", {
  skip_if_not_installed("xml2")
  if (!file.exists(pilot1_define)) skip("pilot1 define.xml not cloned")
  spec <- parse_define(pilot1_define)
  expect_true(is.data.frame(spec))
  expect_true(all(c("dataset", "variable", "label", "type", "length", "origin",
                    "derivation", "codelist_oid") %in% names(spec)))
  expect_true("ADSL" %in% spec$dataset)
  adsl <- spec[spec$dataset == "ADSL", ]
  expect_gte(nrow(adsl), 40)
  expect_lte(nrow(adsl), 60)
  n_text <- sum(!is.na(adsl$derivation) & nzchar(trimws(adsl$derivation)))
  message(sprintf("[define] pilot1 ADSL: %d variables, %d with derivation text", nrow(adsl), n_text))
  expect_gte(n_text, 10)
  expect_equal(sum(duplicated(paste(spec$dataset, spec$variable))), 0)
  expect_gte(sum(!is.na(adsl$label)), 0.9 * nrow(adsl))
  expect_gte(sum(!is.na(adsl$type)), 0.9 * nrow(adsl))
  expect_gte(sum(!is.na(adsl$codelist_oid)), 1)
})

test_that("parse_define captures direct-copy and computation MethodDef styles (ADAE)", {
  skip_if_not_installed("xml2")
  if (!file.exists(pilot1_define)) skip("pilot1 define.xml not cloned")
  spec <- parse_define(pilot1_define)
  adae <- spec[spec$dataset == "ADAE", ]
  aeacn <- adae$derivation[adae$variable == "AEACN"]
  expect_length(aeacn, 1)
  expect_match(trimws(aeacn), "^AE\\.AEACN$")
  adurn <- adae$derivation[adae$variable == "ADURN"]
  expect_length(adurn, 1)
  expect_match(trimws(adurn), "ADURN=AENDT-ASTDT\\+1")
})

test_that("parse_define works on the pilot2 define", {
  skip_if_not_installed("xml2")
  if (!file.exists(pilot2_define)) skip("pilot2 define.xml not cloned")
  spec <- parse_define(pilot2_define)
  expect_true("ADSL" %in% spec$dataset)
  adsl <- spec[spec$dataset == "ADSL", ]
  expect_gte(nrow(adsl), 40)
  n_text <- sum(!is.na(adsl$derivation) & nzchar(trimws(adsl$derivation)))
  message(sprintf("[define] pilot2 ADSL: %d variables, %d with derivation text", nrow(adsl), n_text))
  expect_gte(n_text, 10)
  expect_equal(sum(duplicated(paste(spec$dataset, spec$variable))), 0)
})

test_that("parse_define fails informatively on bad input", {
  skip_if_not_installed("xml2")
  expect_error(parse_define("no_such_file_define.xml"), "not found")
  tmp <- tempfile(fileext = ".xml")
  writeLines(c("<ODM ODMversion=\"1.3\">", "  <ItemGroupDef", "</ODM>"), tmp)
  expect_error(parse_define(tmp), "cannot parse define file as XML")
  tmp2 <- tempfile(fileext = ".xml")
  writeLines("<root><a>not a define</a></root>", tmp2)
  expect_error(parse_define(tmp2), "no ItemDef elements found")
})

test_that("read_define uses the direct parser and falls back cleanly on corrupt XML", {
  skip_if_not_installed("xml2")
  if (!file.exists(pilot1_define)) skip("pilot1 define.xml not cloned")
  spec <- read_define(pilot1_define)
  expect_equal(spec, parse_define(pilot1_define))
  adsl <- spec[spec$dataset == "ADSL", ]
  expect_gte(nrow(adsl), 40)
  expect_gte(sum(!is.na(adsl$derivation) & nzchar(trimws(adsl$derivation))), 10)

  tmp <- tempfile(fileext = ".xml")
  writeLines(c("<ODM ODMversion=\"1.3\">", "  <ItemGroupDef", "</ODM>"), tmp)
  # direct parser refuses, fallback is attempted (message), metacore also refuses:
  # the result must be an informative error, never a crash or garbage data.frame
  if (requireNamespace("metacore", quietly = TRUE)) {
    expect_message(
      err <- tryCatch(read_define(tmp), error = function(e) e),
      "falling back"
    )
    expect_s3_class(err, "simpleError")
    expect_match(conditionMessage(err), "define_to_metacore\\(\\) failed")
  } else {
    expect_error(read_define(tmp), "read_define|metacore")
  }
})

test_that("rules classify of the real pilot1 ADSL spec never errors and gates cleanly", {
  skip_if_not_installed("xml2")
  if (!file.exists(pilot1_define)) skip("pilot1 define.xml not cloned")
  spec <- read_define(pilot1_define)
  adsl <- spec[spec$dataset == "ADSL", ]

  ir <- classify_variables(spec, "ADSL", backend = "rules")
  expect_length(ir, nrow(adsl))

  problems <- validate_ir(ir)
  known_patterns <- paste0(
    "^(\\[[^]]*\\] (missing `dataset`|missing `variable`|has no steps|",
    "unknown layer|all steps run on foreign datasets|assign\\.from)|",
    "\\[[^]]* step [0-9]+\\] (missing required arg|layer|arg|formula|compute_var))"
  )
  unexpected <- problems[!grepl(known_patterns, problems)]
  expect_length(unexpected, 0)

  nh <- sum(vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
  empty_deriv <- sum(is.na(adsl$derivation) | !nzchar(trimws(adsl$derivation)))
  message(sprintf(
    "[classify] real pilot1 ADSL: %d vars | %d classified | %d needs_human | %d empty derivation | %d gate problems",
    length(ir), length(ir) - nh, nh, empty_deriv, length(problems)
  ))

  # variables with empty derivation AND origin CRF/predecessor must classify as
  # assign or needs_human - never as an executed error/guess
  empty_idx <- which(is.na(adsl$derivation) | !nzchar(trimws(adsl$derivation)))
  for (i in empty_idx) {
    if (!toupper(adsl$origin[[i]]) %in% c("CRF", "PREDECESSOR")) next
    vir <- ir[[which(vapply(ir, function(v) identical(v$variable, adsl$variable[[i]]), logical(1)))]]
    if (isTRUE(vir$needs_human)) next
    expect_true(all(vapply(vir$steps, function(s) identical(s$layer, "assign"), logical(1))))
  }
})
