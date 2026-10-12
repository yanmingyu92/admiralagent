# routing_plan(): topological waves derived from spec lineage, with the two
# fail-closed lanes (cycle-blocked, human-routed) visible as NA waves.

test_that("mock spec: BMIBL lands in wave 1 behind its key columns", {
  plan <- routing_plan(classify_variables(mock_spec_adsl(), "ADSL", backend = "rules"))
  expect_s3_class(plan, "data.frame")
  expect_equal(nrow(plan), 10)
  bmi <- plan[plan$variable == "BMIBL", ]
  expect_equal(bmi$wave, 1)
  expect_identical(bmi$depends_on, "STUDYID,USUBJID")
  expect_equal(plan$wave[plan$variable == "STUDYID"], 0)
  # needs_human variables route to the human lane, never to a wave.
  expect_true(is.na(plan$wave[plan$variable == "AGEGR1"]))
  expect_true(plan$needs_human[plan$variable == "AGEGR1"])
  expect_length(attr(plan, "blocked"), 0)
})

test_that("assign chains order into consecutive waves", {
  ir <- list(
    new_variable_ir("ADSL", "C", list(new_step("assign", list(target = "C", from = "B")))),
    new_variable_ir("ADSL", "A", list(new_step("assign", list(target = "A", from = "BASE")))),
    new_variable_ir("ADSL", "B", list(new_step("assign", list(target = "B", from = "A"))))
  )
  expect_length(validate_ir(ir), 0)
  plan <- routing_plan(ir, known_columns = "BASE")
  expect_equal(plan$wave[plan$variable == "A"], 0)
  expect_equal(plan$wave[plan$variable == "B"], 1)
  expect_equal(plan$wave[plan$variable == "C"], 2)
  expect_identical(plan$depends_on[plan$variable == "C"], "B")
})

test_that("cycles are blocked and stay out of every wave", {
  cyc <- list(
    new_variable_ir("ADSL", "AAA", list(new_step("assign", list(target = "AAA", from = "BBB")))),
    new_variable_ir("ADSL", "BBB", list(new_step("assign", list(target = "BBB", from = "AAA"))))
  )
  expect_match(validate_ir(cyc), "cyclic", all = FALSE)
  plan <- routing_plan(cyc)
  expect_true(all(is.na(plan$wave)))
  expect_identical(sort(attr(plan, "blocked")), c("AAA", "BBB"))
})

test_that("the dual-consensus output routes like any other IR", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  agree_json <- paste0(
    '[{"dataset":"ADSL","variable":"TRTSDTM","steps":[{"layer":"impute_dtc","args":',
    '{"target":"TRTSDTM","dtc":"RFSTDTC","output_class":"dtm","highest_imputation":"M",',
    '"date_imputation":"first"}}],"confidence":0.9,"needs_human":false,',
    '"rationale":"first dose","spec_origin":"first dose"}]'
  )
  ir <- classify_variables_dual(mock_spec_adsl()[5, , drop = FALSE], "ADSL",
                                chat = list(chat = function(prompt) agree_json))
  plan <- routing_plan(ir)
  expect_equal(nrow(plan), 1)
  expect_equal(plan$wave, 0)
  expect_identical(plan$layers, "impute_dtc")
})
