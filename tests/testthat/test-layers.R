test_that("layer registry is the single source of truth", {
  expect_identical(
    layer_names(),
    c("assign", "merge_var", "lookup_join", "impute_dtc", "dtm_to_dt", "duration",
      "date_shift", "compute_param", "summary_record", "extreme_flag", "codelist_var",
      "obs_number", "categorize", "compute_var", "assign_conditional")
  )
  for (nm in layer_names()) {
    l <- aa_layers()[[nm]]
    expect_true(is.function(l$render), info = nm)
    expect_true(is.character(l$label) && nzchar(l$label), info = nm)
    expect_true(is.numeric(l$rank), info = nm)
    expect_true(is.character(l$required), info = nm)
    expect_true(length(l$checks) > 0, info = nm)
    for (cid in l$checks) expect_true(cid %in% names(aa_checks()), info = paste(nm, cid))
  }
})

test_that("layer_docs exposes vocabulary for prompts", {
  docs <- layer_docs()
  expect_length(docs, length(layer_names()))
  expect_true(all(grepl("^layer: ", docs)))
})
