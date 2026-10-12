# Dual-backend consensus: rules vs LLM, fingerprints compared at full
# canonical semantics; any divergence escalates to needs_human.

trtsdtm_agree_json <- paste0(
  '[{"dataset":"ADSL","variable":"TRTSDTM","steps":[{"layer":"impute_dtc","args":',
  '{"target":"TRTSDTM","dtc":"RFSTDTC","output_class":"dtm","highest_imputation":"M",',
  '"date_imputation":"first"}}],"confidence":0.9,"needs_human":false,',
  '"rationale":"first dose","spec_origin":"first dose"}]'
)

trtsdtm_row <- function() mock_spec_adsl()[5, , drop = FALSE]

mock_chat <- function(reply) list(chat = function(prompt) reply)

test_that("agreement at full semantics adopts the rules IR and reports agree", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  ir <- classify_variables_dual(trtsdtm_row(), "ADSL", chat = mock_chat(trtsdtm_agree_json))
  expect_length(ir, 1)
  expect_false(ir[[1]]$needs_human)
  expect_identical(ir[[1]]$steps[[1]]$layer, "impute_dtc")
  expect_length(validate_ir(ir), 0)
  dual <- attr(ir, "dual")
  expect_identical(dual$class, "agree")
  expect_identical(dual$rules_fp, dual$llm_fp)
  expect_equal(attr(ir, "agreement_rate"), 1)
  expect_length(attr(ir, "llm_candidates"), 0)
  expect_equal(nrow(dual_disagreements(ir)), 0)
})

test_that("semantic disagreement escalates to needs_human and never picks a side", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  disagree_json <- gsub('"date_imputation":"first"', '"date_imputation":"last"',
                        trtsdtm_agree_json, fixed = TRUE)
  ir <- classify_variables_dual(trtsdtm_row(), "ADSL", chat = mock_chat(disagree_json))
  expect_true(ir[[1]]$needs_human)
  expect_length(ir[[1]]$steps, 0)
  expect_match(ir[[1]]$rationale, "dual: backends disagree", fixed = TRUE)
  expect_match(ir[[1]]$rationale, "impute_dtc", fixed = TRUE)
  expect_length(validate_ir(ir), 0)
  dual <- attr(ir, "dual")
  expect_identical(dual$class, "disagree")
  expect_false(identical(dual$rules_fp, dual$llm_fp))
  queue <- dual_disagreements(ir)
  expect_equal(nrow(queue), 1)
  expect_identical(queue$variable, "TRTSDTM")
  expect_true(queue$llm_suggestion)
})

test_that("rules abstains but LLM answers: escalates as rules_abstain with suggestion", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  agegr1_json <- paste0(
    '[{"dataset":"ADSL","variable":"AGEGR1","steps":[{"layer":"assign","args":',
    '{"target":"AGEGR1","literal":"UNKNOWN"}}],"confidence":0.8,"needs_human":false,',
    '"rationale":"constant band","spec_origin":"age group"}]'
  )
  agegr1_row <- mock_spec_adsl()[8, , drop = FALSE]
  stopifnot(isTRUE(rules_engine(agegr1_row)[[1]]$needs_human))
  ir <- classify_variables_dual(agegr1_row, "ADSL", chat = mock_chat(agegr1_json))
  expect_true(ir[[1]]$needs_human)
  dual <- attr(ir, "dual")
  expect_identical(dual$class, "rules_abstain")
  expect_true(dual$llm_suggestion)
  expect_identical(dual$llm_layers, "assign")
  cands <- attr(ir, "llm_candidates")
  expect_identical(names(cands), "AGEGR1")
  expect_s3_class(cands$AGEGR1, "aa_variable_ir")
  expect_identical(cands$AGEGR1$steps[[1]]$layer, "assign")
})

test_that("LLM abstains but rules answers: escalates as llm_abstain, rules not silently taken", {
  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  abstain_json <- paste0(
    '[{"dataset":"ADSL","variable":"STUDYID","steps":[],"confidence":0.2,',
    '"needs_human":true,"rationale":"unsure","spec_origin":"study id"}]'
  )
  studyid_row <- mock_spec_adsl()[1, , drop = FALSE]
  stopifnot(!isTRUE(rules_engine(studyid_row)[[1]]$needs_human))
  ir <- classify_variables_dual(studyid_row, "ADSL", chat = mock_chat(abstain_json))
  expect_true(ir[[1]]$needs_human)
  expect_length(ir[[1]]$steps, 0)
  dual <- attr(ir, "dual")
  expect_identical(dual$class, "llm_abstain")
  expect_false(dual$llm_suggestion)
})

test_that("dual_consensus is logged digest-only and the chain verifies", {
  lf <- tempfile(pattern = "aa_dual_", fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)
  row <- trtsdtm_row()
  ir <- classify_variables_dual(row, "ADSL", chat = mock_chat(trtsdtm_agree_json))

  raw <- readLines(lf)
  expect_length(raw, 1)
  expect_false(grepl(row$derivation[[1]], raw[[1]], fixed = TRUE))
  entry <- jsonlite::fromJSON(raw[[1]])
  expect_identical(entry$event, "dual_consensus")
  expect_equal(as.numeric(entry$details$variables), 1)
  expect_equal(as.numeric(entry$details$agreement_rate), 1)
  expect_match(entry$details$origin, "^origin:[0-9a-f]{16}$")
  expect_null(entry$details$spec_origin)
  expect_null(entry$details$derivation)
  expect_true(verify_log(lf)$ok)
})

test_that("dual_disagreements requires the dual attribute", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_error(dual_disagreements(ir), "classify_variables_dual")
})
