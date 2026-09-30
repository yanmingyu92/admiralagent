# deliverable_graph() projects the (already cross-dataset) variable dependency
# graph onto v$dataset nodes. Node policy under test: deliverables only, i.e.
# the declared v$dataset values. Raw SDTM source objects (`ex`, `vs`) reached
# through on/dataset_add/dataset_lookup are inputs, never deliverables, so they
# are neither nodes nor edge endpoints.

adsl_producer <- function(target = "TRTSDTM", from = "RFXSTDTC") {
  new_variable_ir("ADSL", target, list(new_step("assign", list(target = target, from = from))))
}

merge_consumer <- function(dataset, variable, source, dataset_add) {
  new_variable_ir(dataset, variable, list(new_step("merge_var", list(
    target = variable, source = source, dataset_add = dataset_add,
    by_vars = c("STUDYID", "USUBJID"), mode = "first"
  ))))
}

test_that("a cross-dataset merge yields exactly one deliverable edge and no cycles", {
  ir <- list(
    adsl_producer(),
    merge_consumer("ADTTE", "STARTDTM", "TRTSDTM", "ADSL")
  )

  g <- deliverable_graph(ir)

  expect_equal(g$nodes, c("ADSL", "ADTTE"))
  expect_equal(g$edges, data.frame(from = "ADSL", to = "ADTTE", stringsAsFactors = FALSE))
  expect_equal(g$cycles, list())
})

test_that("an unproduced source variable creates no edge", {
  # ADSL declares no TRTSDTM here, so the ADTTE merge consumes a key nobody
  # produces: no edge, and ADSL is still a node because it is a deliverable.
  ir <- list(
    adsl_producer("AGE", "AGE"),
    merge_consumer("ADTTE", "STARTDTM", "TRTSDTM", "ADSL")
  )

  g <- deliverable_graph(ir)

  expect_equal(g$nodes, c("ADSL", "ADTTE"))
  expect_equal(nrow(g$edges), 0L)
})

test_that("SDTM source objects are inputs, not deliverable nodes", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  datasets_referenced <- unique(unlist(lapply(ir, function(v) {
    vapply(v$steps, function(s) s$args$dataset_add %||% s$args$on %||% v$dataset, character(1))
  })))

  g <- deliverable_graph(ir)

  # The spec really does reach into raw domains ...
  expect_true(any(!toupper(datasets_referenced) %in% "ADSL"))
  # ... yet only the deliverable itself is a node, and intra-dataset variable
  # ordering never shows up as a self edge.
  expect_equal(g$nodes, "ADSL")
  expect_equal(nrow(g$edges), 0L)
  expect_equal(g$cycles, list())
})

test_that("mutual cross-dataset references produce one deterministically ordered SCC", {
  ir <- list(
    adsl_producer(),
    merge_consumer("ADTTE", "STARTDTM", "TRTSDTM", "ADSL"),
    new_variable_ir("ADTTE", "CNSR", list(new_step("assign", list(target = "CNSR", literal = "0")))),
    merge_consumer("ADSL", "LSTCNSR", "CNSR", "ADTTE")
  )

  g <- deliverable_graph(ir)

  expect_equal(g$nodes, c("ADSL", "ADTTE"))
  expect_equal(
    g$edges,
    data.frame(from = c("ADSL", "ADTTE"), to = c("ADTTE", "ADSL"), stringsAsFactors = FALSE)
  )
  expect_equal(g$cycles, list(c("ADSL", "ADTTE")))
  # Members start at the lexicographically smallest member, SCCs sorted by it.
  expect_equal(vapply(g$cycles, `[`, character(1), 1L), "ADSL")
})

test_that("SCC order is independent of IR order", {
  base <- list(
    adsl_producer(),
    merge_consumer("ADTTE", "STARTDTM", "TRTSDTM", "ADSL"),
    new_variable_ir("ADTTE", "CNSR", list(new_step("assign", list(target = "CNSR", literal = "0")))),
    merge_consumer("ADSL", "LSTCNSR", "CNSR", "ADTTE")
  )

  expect_equal(deliverable_graph(base), deliverable_graph(rev(base)))
})

test_that("dataset objects fuse case-insensitively", {
  upper <- deliverable_graph(list(adsl_producer(), merge_consumer("ADTTE", "STARTDTM", "TRTSDTM", "ADSL")))
  lower <- deliverable_graph(list(adsl_producer(), merge_consumer("ADTTE", "STARTDTM", "TRTSDTM", "adsl")))

  expect_equal(lower$edges, data.frame(from = "ADSL", to = "ADTTE", stringsAsFactors = FALSE))
  expect_equal(lower, upper)
})

test_that("review-only variables neither produce nor consume deliverable edges", {
  producer <- adsl_producer()
  producer$needs_human <- TRUE
  ir <- list(producer, merge_consumer("ADTTE", "STARTDTM", "TRTSDTM", "ADSL"))

  g <- deliverable_graph(ir)

  expect_equal(g$nodes, c("ADSL", "ADTTE"))
  expect_equal(nrow(g$edges), 0L)
})

test_that("deliverable_graph validates IR shape and accepts an empty IR", {
  expect_error(deliverable_graph(list(list(dataset = "ADSL"))), "aa_variable_ir")
  expect_equal(deliverable_graph(list()), list(
    nodes = character(),
    edges = data.frame(from = character(), to = character(), stringsAsFactors = FALSE),
    cycles = list()
  ))
})

test_that("REGRESSION: mock ADSL artifact hash and ordering are unchanged", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")

  expect_equal(artifact_hash(ir), "6aea851a")
  expect_equal(
    vapply(order_variables(ir), function(v) v$variable, character(1)),
    c("TRTSDTM", "TRTEDTM", "AGE", "RACEN", "STUDYID", "USUBJID", "BMIBL", "SUBJID", "TRT01P", "AGEGR1")
  )

  # Projecting the graph must not disturb the variable-level graph.
  invisible(deliverable_graph(ir))
  expect_equal(artifact_hash(ir), "6aea851a")
  expect_equal(
    vapply(order_variables(ir), function(v) v$variable, character(1)),
    c("TRTSDTM", "TRTEDTM", "AGE", "RACEN", "STUDYID", "USUBJID", "BMIBL", "SUBJID", "TRT01P", "AGEGR1")
  )
  expect_length(validate_ir(ir), 0L)
})
