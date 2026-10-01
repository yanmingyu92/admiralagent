# Agreement harness.
#
# NOTE ON NUMBERS: every agreement rate produced in this file comes from
# deterministic local backends or scripted stub chats. They are synthetic
# harness-validation data - they prove the harness computes what it claims,
# and they are NOT a measurement of real LLM backend agreement. Measuring that
# requires credentials for two different model families; see the skip below.

stub_chat <- function(replies) {
  i <- 0
  list(
    calls = function() i,
    chat = function(prompt) {
      i <<- i + 1
      if (i > length(replies)) stop("stub chat: no reply queued for call ", i)
      replies[[i]]
    }
  )
}

test_that("run_agreement returns a cross-tab at all three fingerprint levels", {
  res <- run_agreement(list(a = "rules", b = "rules"), dataset = "ADSL")

  expect_s3_class(res, "aa_agreement")
  expect_identical(sort(names(res$rates)), sort(c("abstention", "layer_chain", "full")))
  expect_identical(sort(unique(res$per_case$level)), sort(c("abstention", "layer_chain", "full")))
  for (lv in c("abstention", "layer_chain", "full")) {
    expect_true(inherits(res$crosstab[[lv]], "table"), label = lv)
  }
  # Two identical deterministic voters agree everywhere: a self-consistency
  # check on the harness, not a measurement of backend agreement.
  expect_equal(unname(res$rates[["full"]]), 1)
})

test_that("same layer chain with different args is agreement at layer_chain, disagreement at full", {
  # This is the exact defect that made evals_layers_label() overstate: both
  # IRs impute a DTC into TRTSDTM, so the layer chain is identical, but the
  # source column and imputation direction differ entirely.
  a <- list(dataset = "ADSL", variable = "TRTSDTM", needs_human = FALSE, steps = list(
    list(layer = "impute_dtc", args = list(target = "TRTSDTM", dtc = "RFSTDTC",
         output_class = "dtm", highest_imputation = "M", date_imputation = "first"))
  ))
  b <- list(dataset = "ADSL", variable = "TRTSDTM", needs_human = FALSE, steps = list(
    list(layer = "impute_dtc", args = list(target = "TRTSDTM", dtc = "RFENDTC",
         output_class = "dtm", highest_imputation = "M", date_imputation = "last"))
  ))

  expect_identical(ir_fingerprint(a, "layer_chain"), ir_fingerprint(b, "layer_chain"))
  expect_false(identical(ir_fingerprint(a, "full"), ir_fingerprint(b, "full")))
  expect_identical(ir_fingerprint(a, "abstention"), ir_fingerprint(b, "abstention"))

  # And the old label cannot tell them apart at all.
  expect_identical(evals_layers_label(a), evals_layers_label(b))
})

test_that("the corpus itself contains args-blind collisions, so the old label overstated", {
  resolution <- evals_label_resolution()
  expect_gt(resolution$n_full, resolution$n_layer_labels)
  expect_gt(resolution$colliding_cases, 0)
  # Every colliding group is a set of cases the args-blind label scores as
  # identical but which differ semantically.
  for (g in resolution$collisions) expect_gte(length(g), 2)
})

test_that("expected_args make the corpus args-aware and rules still scores 1.0", {
  cases <- load_evals()
  expect_true(all(vapply(cases, function(c) !is.null(c$expected_args), logical(1))))
  for (ds in c("ADSL", "ADVS")) {
    res <- suppressMessages(run_evals(backend = "rules", dataset = ds))
    expect_identical(evals_accuracy(res), 1)
  }
})

test_that("a wrong-args IR now fails the corpus even with the right layer chain", {
  case <- load_evals()[["eval_002"]]
  right <- evals_expected_shape(case)
  expect_true(evals_case_ok(case, right))

  wrong <- right
  wrong$steps[[1]]$args$date_imputation <- "last"
  expect_identical(evals_layers_label(wrong), evals_layers_label(right))
  expect_false(evals_case_ok(case, wrong))
})

test_that("the corpus is classified in batches, not one call per case", {
  cases <- load_evals()
  adsl <- cases[vapply(cases, function(c) identical(as.character(c$dataset), "ADSL"), logical(1))]
  groups <- evals_case_groups(adsl)
  expect_gte(length(adsl), 18)
  # Far fewer calls than cases. Not literally one: the corpus deliberately
  # repeats variables (TRTSDTM, TRTEDTM, BMIBL each appear twice) and
  # align_batch() rejects duplicate keys in a batch, so two groups is the
  # floor here.
  expect_lt(length(groups), 5)
  expect_identical(length(unlist(groups)), length(adsl))
  keys <- vapply(adsl, function(c) as.character(c$spec_row$variable), character(1))
  for (g in groups) expect_identical(anyDuplicated(keys[g]), 0L)
})

test_that("an LLM voter is classified in one stub call per group, not 24", {
  cases <- load_evals()
  adsl <- cases[vapply(cases, function(c) identical(as.character(c$dataset), "ADSL"), logical(1))]
  groups <- evals_case_groups(adsl)

  reply_for <- function(idx) {
    recs <- lapply(idx, function(i) {
      c <- adsl[[i]]
      list(dataset = as.character(c$dataset), variable = as.character(c$spec_row$variable),
           steps = list(), confidence = 0.5, needs_human = TRUE,
           rationale = "stub", spec_origin = as.character(c$spec_row$derivation))
    })
    as.character(jsonlite::toJSON(recs, auto_unbox = TRUE))
  }
  chat <- stub_chat(lapply(groups, reply_for))

  old <- options(admiralagent.log_file = NA)
  on.exit(options(old), add = TRUE)
  ir <- evals_classify(adsl, backend = "llm", chat = chat, prompt_variant = "full")

  expect_length(ir, length(adsl))
  expect_identical(as.integer(chat$calls()), length(groups))
  expect_lt(chat$calls(), 5)
})

test_that("voter prompt variants differ in the convention-asserting clauses", {
  full <- build_system_prompt_variant("full")
  neutral <- build_system_prompt_variant("neutral")
  minimal <- build_system_prompt_variant("minimal")

  expect_identical(full, build_system_prompt())
  # The clause that pre-commits the answer this harness is trying to measure.
  expect_true(grepl("Different arguments are different rules", full, fixed = TRUE))
  expect_false(grepl("Different arguments are different rules", neutral, fixed = TRUE))
  expect_false(grepl("Different arguments are different rules", minimal, fixed = TRUE))
  expect_lt(nchar(minimal), nchar(full))
  expect_true(grepl("own judgement", neutral, fixed = TRUE))
  # The structural contract is held constant so replies stay comparable.
  for (p in list(neutral, minimal)) {
    expect_true(grepl("layer` values MUST be exactly one of", p, fixed = TRUE))
    expect_true(grepl("Output ONLY the JSON array", p, fixed = TRUE))
  }
})

test_that("agreement_overstatement is zero for identical deterministic voters", {
  res <- run_agreement(list(a = "rules", b = "rules"), dataset = "ADSL")
  over <- agreement_overstatement(res)
  expect_equal(over$layer_chain, 1)
  expect_equal(over$full, 1)
  expect_equal(over$overstatement, 0)
  expect_length(over$cases, 0)
})

test_that("agreement_overstatement flags cases agreeing only at layer_chain", {
  ids <- c("c1", "c2")
  lc_agree <- c(TRUE, TRUE)
  fl_agree <- c(TRUE, FALSE)
  res <- structure(
    list(
      dataset = "ADSL", voters = c("a", "b"),
      per_case = rbind(
        data.frame(id = ids, level = "layer_chain", agree = lc_agree,
                   stringsAsFactors = FALSE),
        data.frame(id = ids, level = "full", agree = fl_agree,
                   stringsAsFactors = FALSE)
      ),
      rates = c(abstention = 1, layer_chain = mean(lc_agree),
                full = mean(fl_agree)),
      crosstab = list()
    ),
    class = c("aa_agreement", "list")
  )
  over <- agreement_overstatement(res)
  expect_equal(over$overstatement, 0.5)
  expect_identical(over$cases, "c2")
})

test_that("print.aa_agreement shows dataset, voters, rates and the honesty caveat", {
  res <- run_agreement(list(a = "rules", b = "rules"), dataset = "ADSL")
  out <- capture.output(printed <- print(res))
  expect_identical(printed, res)
  expect_true(any(grepl("dataset: ADSL", out, fixed = TRUE)))
  expect_true(any(grepl("voters:  a, b", out, fixed = TRUE)))
  expect_true(any(grepl("layer_chain", out, fixed = TRUE)))
  expect_true(any(grepl("self-scoring regression corpus", out, fixed = TRUE)))
  expect_true(any(grepl("not correctness or double programming", out, fixed = TRUE)))
})

test_that("run_agreement refuses to invent a number when credentials are absent", {
  skip_if(agreement_credentials_available(), "credentials present; the no-credential path is not reachable")
  err <- tryCatch(
    run_agreement(list(rules = "rules", model_a = list(backend = "llm")), dataset = "ADSL"),
    error = function(e) conditionMessage(e)
  )
  expect_type(err, "character")
  expect_match(err, "ANTHROPIC_API_KEY")
  expect_match(err, "OPENAI_API_KEY")
  expect_match(err, "not measured", fixed = TRUE)
})

test_that("run_agreement validates its voter list", {
  expect_error(run_agreement(list(a = "rules")), "at least two")
  expect_error(run_agreement(list("rules", "rules")), "named list")
})

test_that("real two-model-family agreement is skipped without credentials", {
  skip_if_not(
    agreement_credentials_available(),
    paste0(
      "no LLM credentials; real backend agreement is not measurable here. ",
      "Set one of: ", paste(AGREEMENT_CREDENTIAL_VARS, collapse = ", "),
      " and supply two chat objects from DIFFERENT model families."
    )
  )
  skip_if_not_installed("ellmer")
  skip("requires two model families and a spend budget; run manually, not in CI")
})
