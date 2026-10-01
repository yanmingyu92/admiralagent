# assign_conditional layer: conditional row-level assignment for
# "Y if <condition>" population flags (stage 1 of
# .agents/conditional-layer-assessment.md). The condition arg rides the same
# predicate whitelist as filter/restrict_filter; value args are rendered
# exclusively through quote_literal().

mk_cond <- function(variable = "ITTFL", condition = "ARMCD != ''",
                    true_value = "Y", else_value = "N", dataset = "ADSL") {
  args <- list(target = variable, condition = condition, true_value = true_value)
  if (!is.null(else_value)) args$else_value <- else_value
  new_variable_ir(dataset, variable, list(new_step("assign_conditional", args)))
}

test_that("assign_conditional renders case_when with quoted literals and CHECK comment", {
  code <- aa_layers()$assign_conditional$render(
    list(target = "ITTFL", condition = "ARMCD != ''", true_value = "Y", else_value = "N"),
    "adsl"
  )
  expect_identical(code, paste0(
    "adsl <- adsl |>\n",
    "  dplyr::mutate(ITTFL = dplyr::case_when(\n",
    "    ARMCD != '' ~ \"Y\",\n",
    "    TRUE ~ \"N\"\n",
    "  ))\n",
    "# CHECK: human must confirm the condition semantics and the else branch (NA vs \"\") before use"
  ))
})

test_that("omitted else_value renders as NA_character_ via the registry default", {
  code <- aa_layers()$assign_conditional$render(
    list(target = "DSRAEFL", condition = "DCDECOD == 'ADVERSE EVENT'", true_value = "Y"),
    "adsl"
  )
  expect_true(grepl("TRUE ~ NA_character_", code, fixed = TRUE))
})

test_that("value args never reach generated code unquoted (injection payload)", {
  payload <- "Y\"); system(\"echo blocked\") #"
  v <- mk_cond(condition = "AGE >= 18", true_value = payload, else_value = NULL)
  expect_length(validate_ir(list(v)), 0)
  code <- render_variable(v)
  expect_false(grepl("system(\"echo", code, fixed = TRUE))
  out <- execute_ir(list(v), list(base = data.frame(AGE = c(17, 30))), quiet = TRUE)
  expect_identical(out$adsl$ITTFL, c(NA_character_, payload))
})

test_that("condition goes through the predicate token whitelist", {
  expect_length(validate_ir(list(mk_cond())), 0)
  expect_length(validate_ir(list(mk_cond(variable = "SAFFL", condition = "ITTFL == 'Y' & DCDECOD == 'COMPLETED'"))), 0)
  for (bad in c("!is.na(TRTSDT)", "TRTSDT != NA", "age > 18", "X = 1; Y = 2",
                "system('echo blocked')", "A$B", "X[[1]]", "`X` > 1")) {
    problems <- validate_ir(list(mk_cond(condition = bad)))
    expect_true(length(problems) > 0, info = bad)
    expect_true(any(grepl("token whitelist", problems, fixed = TRUE)), info = bad)
  }
})

test_that("condition must not reference its own target", {
  v <- mk_cond(variable = "EOSSTT", condition = "EOSSTT == 'COMPLETED'",
               true_value = "COMPLETED", else_value = "DISCONTINUED")
  expect_match(paste(validate_ir(list(v)), collapse = "\n"),
               "condition must not reference its own target", fixed = TRUE)
})

test_that("required args are enforced", {
  no_cond <- new_variable_ir("ADSL", "X", list(new_step("assign_conditional", list(target = "X", true_value = "Y"))))
  expect_match(paste(validate_ir(list(no_cond)), collapse = "\n"),
               "missing required arg 'condition'", fixed = TRUE)
  no_true <- new_variable_ir("ADSL", "X", list(new_step("assign_conditional", list(target = "X", condition = "AGE > 18"))))
  expect_match(paste(validate_ir(list(no_true)), collapse = "\n"),
               "missing required arg 'true_value'", fixed = TRUE)
})

test_that("condition columns create dependency ordering edges", {
  eosstt <- new_variable_ir("ADSL", "EOSSTT", list(new_step("assign_conditional", list(target = "EOSSTT", condition = "DCDECOD == 'COMPLETED'", true_value = "COMPLETED", else_value = "DISCONTINUED"))))
  dcdecod <- new_variable_ir("ADSL", "DCDECOD", list(new_step("merge_var", list(target = "DCDECOD", source = "DSDECOD", dataset_add = "ds", by_vars = c("STUDYID", "USUBJID"), mode = "first", filter = "DSCAT == 'DISPOSITION EVENT'"))))
  ordered <- order_variables(list(eosstt, dcdecod))
  expect_identical(vapply(ordered, function(v) v$variable, character(1)),
                   c("DCDECOD", "EOSSTT"))
  expect_length(validate_ir(list(eosstt, dcdecod)), 0)
})

test_that("unresolved condition columns surface in ir_dependency_report", {
  rep <- ir_dependency_report(list(mk_cond(variable = "EOSSTT", condition = "DCDECOD == 'COMPLETED'", true_value = "COMPLETED")))
  expect_true("DCDECOD" %in% rep$input)
})

test_that("condition is exposed as a structured predicate with PARAMCD tracking", {
  s <- new_step("assign_conditional", list(target = "X", condition = "PARAMCD == 'HEIGHT' & AVAL > 100", true_value = "Y"))
  preds <- step_predicates(s)
  expect_identical(names(preds), "condition")
  expect_identical(predicate_names(preds$condition$ast), c("PARAMCD", "AVAL"))
  refs <- step_refs(new_variable_ir("ADVS", "X", list(s)), s)
  expect_true(any(refs$kind == "parameter" & refs$input == "HEIGHT"))
})

test_that("condition whitespace variants are one derivation at the fingerprint level", {
  a <- mk_cond(condition = "ARMCD != ''")
  b <- mk_cond(condition = "ARMCD!=''")
  expect_identical(ir_fingerprint(a, "full"), ir_fingerprint(b, "full"))
})

test_that("end-to-end: validate -> render -> execute a Y-if-condition flag", {
  step <- new_step("assign_conditional", list(target = "ITTFL", condition = "ARMCD != ''", true_value = "Y", else_value = "N"))
  v <- new_variable_ir("ADSL", "ITTFL", list(step), spec_origin = "Y if ARMCD ne ' '. N otherwise", confidence = 1)
  expect_length(validate_ir(list(v)), 0)
  code <- render_variable(v)
  expect_match(code, "dplyr::case_when", fixed = TRUE)
  expect_match(code, "# CHECK:", fixed = TRUE)
  out <- execute_ir(list(v), list(base = data.frame(ARMCD = c("Pbo", "", "Xan_Lo"))), quiet = TRUE)
  expect_identical(out$adsl$ITTFL, c("Y", "N", "Y"))
})
