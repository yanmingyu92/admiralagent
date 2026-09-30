valid_ir_json <- paste0(
  '[{"dataset":"ADSL","variable":"TRTSDTM","steps":[{"layer":"merge_var","args":',
  '{"target":"TRTSDTM","source":"EXSTDTM","dataset_add":"ex","by_vars":["STUDYID","USUBJID"],',
  '"order":["EXSTDTM"],"mode":"first"}}],"confidence":0.9,"needs_human":false,',
  '"rationale":"first dose","spec_origin":"first dose date"}]'
)

test_that("classify_variables_llm retries after unparseable reply then succeeds", {
  replies <- list("```\nnot json at all\n```", valid_ir_json)
  i <- 0
  mock_chat <- list(chat = function(prompt) {
    i <<- i + 1
    replies[[i]]
  })
  vars <- mock_spec_adsl()[1:5, ]
  ir <- classify_variables_llm(vars, chat = mock_chat, max_attempts = 2, batch_size = 10)
  expect_length(ir, 1)
  expect_s3_class(ir[[1]], "aa_variable_ir")
  expect_identical(ir[[1]]$variable, "TRTSDTM")
  expect_identical(ir[[1]]$steps[[1]]$layer, "merge_var")
  expect_length(validate_ir(ir), 0)
})

test_that("classify_variables_llm fails loudly after exhausting attempts", {
  mock_chat <- list(chat = function(prompt) "still not json")
  expect_error(
    classify_variables_llm(mock_spec_adsl()[1:2, ], chat = mock_chat, max_attempts = 2,
                           batch_size = 10),
    "failed IR validation"
  )
})

test_that("classify_variables_llm feeds validation errors back for repair", {
  bad_then_good <- list(
    gsub('"mode":"first"', '"mode":"whenever"', valid_ir_json),
    valid_ir_json
  )
  calls <- character()
  i <- 0
  mock_chat <- list(chat = function(prompt) {
    i <<- i + 1
    calls[i] <<- prompt
    bad_then_good[[i]]
  })
  ir <- classify_variables_llm(mock_spec_adsl()[1:3, ], chat = mock_chat, max_attempts = 2,
                               batch_size = 10)
  expect_true(grepl("failed IR validation", calls[2], fixed = TRUE))
  expect_length(ir, 1)
})

test_that("LLM step-level `on` is absorbed into args and vectors are unlisted", {
  json_with_on <- paste0(
    '[{"dataset":"ADSL","variable":"TRTSDTM","steps":[',
    '{"layer":"impute_dtc","on":"ex","args":{"target":"EXSTDTM","dtc":"EXSTDTC",',
    '"output_class":"dtm","highest_imputation":"M","date_imputation":"first"}},',
    '{"layer":"merge_var","args":{"target":"TRTSDTM","source":"EXSTDTM","dataset_add":"ex",',
    '"by_vars":["STUDYID","USUBJID"],"order":["EXSTDTM"],"mode":"first"}}],',
    '"confidence":0.9,"needs_human":false,"rationale":"ok","spec_origin":"first dose"}]'
  )
  mock_chat <- list(chat = function(prompt) json_with_on)
  ir <- classify_variables_llm(mock_spec_adsl()[1:2, ], chat = mock_chat, max_attempts = 1,
                               batch_size = 10)
  expect_length(validate_ir(ir), 0)
  expect_identical(ir[[1]]$steps[[1]]$args$on, "ex")
  expect_identical(ir[[1]]$steps[[2]]$args$by_vars, c("STUDYID", "USUBJID"))
  code <- render_variable(ir[[1]])
  expect_true(grepl("ex <- ex |>", code, fixed = TRUE))
  expect_true(grepl("exprs(STUDYID, USUBJID)", code, fixed = TRUE))
})

test_that("assign-from-BDS reply is rejected and the feedback names merge_var", {
  bad <- paste0(
    '[{"dataset":"ADSL","variable":"BMIBL","steps":[',
    '{"layer":"compute_param","args":{"paramcd":"BMI","param":"BMI",',
    '"parameters":["WEIGHT","HEIGHT"],"formula":"AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",',
    '"by_vars":["STUDYID","USUBJID"],"on":"vs"}},',
    '{"layer":"assign","args":{"target":"BMIBL","from":"AVAL"}}],',
    '"confidence":0.7,"needs_human":false,"rationale":"bad","spec_origin":"bmi"}]'
  )
  good <- paste0(
    '[{"dataset":"ADSL","variable":"BMIBL","steps":[',
    '{"layer":"compute_param","args":{"paramcd":"BMI","param":"BMI",',
    '"parameters":["WEIGHT","HEIGHT"],"formula":"AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2",',
    '"by_vars":["STUDYID","USUBJID"],"on":"vs"}},',
    '{"layer":"merge_var","args":{"target":"BMIBL","source":"AVAL","dataset_add":"vs",',
    '"by_vars":["STUDYID","USUBJID"],"order":["AVAL"],"mode":"first",',
    '"filter":"PARAMCD == \'BMI\'"}}],',
    '"confidence":0.9,"needs_human":false,"rationale":"ok","spec_origin":"bmi"}]'
  )
  replies <- list(bad, good)
  calls <- character()
  i <- 0
  mock_chat <- list(chat = function(prompt) {
    i <<- i + 1
    calls[i] <<- prompt
    replies[[i]]
  })
  ir <- classify_variables_llm(mock_spec_adsl()[10, , drop = FALSE], chat = mock_chat,
                               max_attempts = 2, batch_size = 10)
  expect_true(grepl("merge_var", calls[2]))
  expect_identical(ir[[1]]$steps[[2]]$layer, "merge_var")
  expect_length(validate_ir(ir), 0)
})

json_merge_last <- gsub('"mode":"first"', '"mode":"last"', valid_ir_json, fixed = TRUE)

json_impute_merge <- paste0(
  '[{"dataset":"ADSL","variable":"TRTSDTM","steps":[',
  '{"layer":"impute_dtc","args":{"target":"EXSTDTM","dtc":"EXSTDTC","on":"ex",',
  '"output_class":"dtm","highest_imputation":"M","date_imputation":"first"}},',
  '{"layer":"merge_var","args":{"target":"TRTSDTM","source":"EXSTDTM","dataset_add":"ex",',
  '"by_vars":["STUDYID","USUBJID"],"order":["EXSTDTM"],"mode":"first"}}],',
  '"confidence":0.9,"needs_human":false,"rationale":"impute then merge","spec_origin":"first dose"}]'
)

json_impute <- paste0(
  '[{"dataset":"ADSL","variable":"TRTSDTM","steps":[',
  '{"layer":"impute_dtc","args":{"target":"TRTSDTM","dtc":"RFSTDTC",',
  '"output_class":"dtm","highest_imputation":"M","date_imputation":"first"}}],',
  '"confidence":0.7,"needs_human":false,"rationale":"impute dm","spec_origin":"first dose"}]'
)

consensus_mock_chat <- function(replies) {
  i <- 0
  list(chat = function(prompt) {
    i <<- i + 1
    if (i > length(replies)) stop("consensus mock chat: no reply queued for call ", i)
    reply <- replies[[i]]
    if (is.function(reply)) reply() else reply
  })
}

trtsdtm_row <- function() mock_spec_adsl()[5, , drop = FALSE]

test_that("samples > 1 majority vote picks the majority signature", {
  chat <- consensus_mock_chat(list(valid_ir_json, json_merge_last, json_impute_merge))
  ir <- classify_variables_llm(trtsdtm_row(), chat = chat, max_attempts = 1,
                               batch_size = 10, samples = 3)
  expect_length(ir, 1)
  expect_length(validate_ir(ir), 0)
  expect_identical(ir[[1]]$steps[[1]]$layer, "merge_var")
  expect_identical(ir[[1]]$steps[[1]]$args$mode, "first")
  cd <- attr(ir, "consensus")
  expect_s3_class(cd, "data.frame")
  expect_identical(cd$variable, "TRTSDTM")
  expect_identical(cd$chosen, "merge_var")
  expect_match(cd$signature_votes, "merge_var:2", fixed = TRUE)
  expect_match(cd$signature_votes, "impute_dtc->merge_var:1", fixed = TRUE)
  expect_false(cd$unanimous)
})

test_that("full disagreement across samples routes the variable to needs_human", {
  chat <- consensus_mock_chat(list(valid_ir_json, json_impute_merge, json_impute))
  ir <- classify_variables_llm(trtsdtm_row(), chat = chat, max_attempts = 1,
                               batch_size = 10, samples = 3)
  expect_true(ir[[1]]$needs_human)
  expect_length(ir[[1]]$steps, 0)
  expect_match(ir[[1]]$rationale, "consensus")
  expect_match(ir[[1]]$rationale, "disagreement across 3 samples", fixed = TRUE)
  expect_equal(ir[[1]]$confidence, 0.7 * 0.5)
  expect_length(validate_ir(ir), 0)
  cd <- attr(ir, "consensus")
  expect_identical(cd$chosen, "needs_human")
  expect_false(cd$unanimous)
})

test_that("samples = 1 keeps the single-run pipeline and attaches no consensus attribute", {
  ir <- classify_variables_llm(trtsdtm_row(), chat = consensus_mock_chat(list(valid_ir_json)),
                               max_attempts = 1, batch_size = 10, samples = 1)
  expect_null(attr(ir, "consensus"))
  ir_default <- classify_variables_llm(trtsdtm_row(), chat = consensus_mock_chat(list(valid_ir_json)),
                                       max_attempts = 1, batch_size = 10)
  expect_null(attr(ir_default, "consensus"))
})

test_that("a sample that fails entirely is excluded and the remaining samples vote", {
  chat <- consensus_mock_chat(list(
    valid_ir_json,
    function() stop("api down"),
    valid_ir_json
  ))
  ir <- classify_variables_llm(trtsdtm_row(), chat = chat, max_attempts = 1,
                               batch_size = 10, samples = 3)
  expect_identical(ir[[1]]$steps[[1]]$layer, "merge_var")
  expect_length(validate_ir(ir), 0)
  cd <- attr(ir, "consensus")
  expect_identical(cd$chosen, "merge_var")
  expect_identical(cd$signature_votes, "merge_var:2")
  expect_true(cd$unanimous)
})

test_that("multi-sample run fails loudly when every sample fails", {
  chat <- list(chat = function(prompt) stop("api down"))
  expect_error(
    classify_variables_llm(trtsdtm_row(), chat = chat, max_attempts = 1,
                           batch_size = 10, samples = 2),
    "backend = 'rules'"
  )
})

test_that("consensus = 'first' takes the earliest sample without voting", {
  chat <- consensus_mock_chat(list(json_impute, valid_ir_json, valid_ir_json))
  ir <- classify_variables_llm(trtsdtm_row(), chat = chat, max_attempts = 1,
                               batch_size = 10, samples = 3, consensus = "first")
  expect_identical(ir[[1]]$steps[[1]]$layer, "impute_dtc")
  expect_length(validate_ir(ir), 0)
  cd <- attr(ir, "consensus")
  expect_identical(cd$chosen, "impute_dtc")
  expect_false(cd$unanimous)
})

test_that("consensus logging is off by default and honours the log_file option", {
  before <- list.files(tempdir())
  classify_variables_llm(trtsdtm_row(), chat = consensus_mock_chat(list(valid_ir_json, valid_ir_json)),
                         max_attempts = 1, batch_size = 10, samples = 2)
  expect_identical(sort(list.files(tempdir())), sort(before))

  lf <- tempfile(pattern = "aa_consensus_", fileext = ".jsonl")
  old <- options(admiralagent.log_file = lf)
  on.exit(options(old), add = TRUE)
  classify_variables_llm(trtsdtm_row(), chat = consensus_mock_chat(list(valid_ir_json, valid_ir_json)),
                         max_attempts = 1, batch_size = 10, samples = 2)
  expect_true(file.exists(lf))
  lines <- readLines(lf)
  expect_length(lines, 1)
  entry <- jsonlite::fromJSON(lines[[1]])
  expect_identical(entry$event, "llm_consensus")
  expect_equal(as.numeric(entry$details$samples), 2)
  expect_equal(as.numeric(entry$details$variables), 1)
  expect_equal(as.numeric(entry$details$agreement_rate), 1)
})
