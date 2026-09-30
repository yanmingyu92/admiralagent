# Two halves, in the order the spike (.agents/ARS-SPIKE.md) justifies them:
#
#   1. The `ir_products()` / `ir_refs()` / `ir_rank()` seam made
#      `dependency_graph()` type-agnostic. The acceptance criterion is that the
#      ADaM path is BIT-IDENTICAL afterwards, so the pinned goldens are asserted
#      here as well as in their own files.
#   2. The spike concluded CDISC ARS is a SINK FORMAT, not an IR: its
#      `Operation` class names statistics in free text with no enumeration, and
#      `AnalysisMethod.codeTemplate` is opaque source. The compiler therefore
#      owns `aa_operations()`, and that registry - not an ARS reader - is what
#      is tested below, exactly as the brief requires when the spike lands this
#      way.

# ---- 1. ADaM path is bit-identical through the generics --------------------

test_that("pinned golden: artifact_hash of the rules-classified ADSL spec is unchanged", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_identical(artifact_hash(ir), "84a18650")
})

test_that("pinned golden: order_variables name order is unchanged", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  expect_identical(
    vapply(order_variables(ir), function(v) v$variable, character(1)),
    c("TRTSDTM", "TRTEDTM", "AGE", "RACEN", "STUDYID", "USUBJID",
      "BMIBL", "SUBJID", "TRT01P", "AGEGR1")
  )
})

test_that("the aa_variable_ir methods ARE the pre-seam functions, not copies", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  for (v in ir) {
    # Identical, not merely equal: any divergence between the method and the
    # original function is what would make the ADaM path non-bit-identical.
    expect_identical(ir_products(v), variable_product_keys(v))
    expect_identical(ir_refs(v), variable_input_keys(v))
    expect_identical(ir_rank(v), step_rank(v))
  }
})

test_that("dependency_graph output is unchanged for the ADaM path", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  graph <- dependency_graph(ir)
  # Recomputed with the pre-seam call sites, inline, as the reference.
  n <- length(ir)
  active <- which(!vapply(ir, function(v) isTRUE(v$needs_human), logical(1)))
  products <- lapply(ir, variable_product_keys)
  producer <- list()
  for (i in active) for (key in products[[i]]) producer[[key]] <- union(producer[[key]], i)
  parents <- rep(list(integer()), n)
  for (i in active) {
    for (key in variable_input_keys(ir[[i]])) {
      parents[[i]] <- union(parents[[i]], setdiff(producer[[key]] %||% integer(), i))
    }
  }
  ranks <- vapply(ir, step_rank, numeric(1))
  placed <- integer()
  while (length(placed) < n) {
    remaining <- setdiff(seq_len(n), placed)
    ready <- remaining[vapply(parents[remaining], function(ps) all(ps %in% placed), logical(1))]
    if (!length(ready)) ready <- remaining
    placed <- c(placed, ready[order(ranks[ready], ready)][1])
  }
  expect_identical(graph$order, placed)
  expect_identical(graph$blocked, integer())
  expect_identical(graph$duplicate, character())
})

test_that("deliverable_graph still resolves cross-dataset edges through the seam", {
  ir <- classify_variables(mock_spec_adsl(), "ADSL", backend = "rules")
  graph <- deliverable_graph(ir)
  expect_identical(graph$nodes, "ADSL")
  expect_identical(nrow(graph$edges), 0L)
  expect_identical(graph$cycles, list())
})

test_that("an unclassed record still routes to the variable implementation", {
  v <- new_variable_ir("ADSL", "AGE", list(new_step("assign", list(target = "AGE", from = "RAWAGE"))))
  plain <- unclass(v)
  expect_identical(ir_products(plain), variable_product_keys(v))
  expect_identical(ir_refs(plain), variable_input_keys(v))
})

# ---- 2. Operation registry (ARS is a sink, so we own the vocabulary) -------

test_that("aa_operations is a closed, well-formed registry", {
  ops <- aa_operations()
  expect_gt(length(ops), 0L)
  expect_false(anyDuplicated(names(ops)) > 0L)
  for (nm in names(ops)) {
    o <- ops[[nm]]
    expect_true(setequal(names(o), c("label", "scale", "result_pattern", "ars_name", "order")),
                info = nm)
    expect_true(nzchar(o$label), info = nm)
    expect_true(o$scale %in% c("numeric", "categorical", "any"), info = nm)
    expect_true(nzchar(o$result_pattern), info = nm)
    expect_true(nzchar(o$ars_name), info = nm)
    expect_true(is.numeric(o$order) && length(o$order) == 1L, info = nm)
  }
  # `order` maps to ARS Operation.order, which is required and ordinal.
  orders <- vapply(ops, function(o) as.double(o$order), numeric(1))
  expect_false(anyDuplicated(orders) > 0L)
})

test_that("analysis_method_spec resolves operations into ARS-facing metadata", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE",
                       operations = c("sd", "n", "mean"),
                       analysis_set = "SAFFL == 'Y'", grouping = "TRT01P")
  spec <- analysis_method_spec(a)
  # Emitted in registry order, not in the order the caller happened to list.
  expect_identical(spec$operation, c("n", "mean", "sd"))
  expect_identical(spec$ars_name, c("n", "Mean", "Standard Deviation"))
  expect_identical(spec$result_pattern, c("XX", "XX.X", "XX.XX"))
})

test_that("analysis_method_spec refuses to describe a malformed analysis", {
  bad <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE", operations = "geomean")
  expect_error(analysis_method_spec(bad), "unknown operation")
})

# ---- 3. A minimal analysis IR resolves its ADaM -> TLF edges ----------------

adsl_for_analysis <- function() {
  list(
    new_variable_ir("ADSL", "AGE", list(
      new_step("assign", list(target = "AGE", from = "RAWAGE"))
    )),
    new_variable_ir("ADSL", "TRT01P", list(
      new_step("assign", list(target = "TRT01P", from = "ARM"))
    )),
    new_variable_ir("ADVS", "AVAL", list(
      new_step("assign", list(target = "AVAL", from = "VSSTRESN"))
    ))
  )
}

test_that("a minimal analysis IR is valid and keys its results by output", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE",
                       operations = c("n", "mean"),
                       analysis_set = "SAFFL == 'Y'", grouping = "TRT01P")
  expect_identical(validate_analysis_ir(list(a)), character())
  expect_identical(
    ir_products(a),
    c("T14-3-1::result::AN01.n", "T14-3-1::result::AN01.mean")
  )
  # "result" is the third `kind`, which the spike showed the column/parameter
  # vocabulary could not express.
  expect_true(all(grepl("::result::", ir_products(a), fixed = TRUE)))
})

test_that("an analysis consumes its variable, groupings and predicate columns", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE",
                       operations = "mean",
                       analysis_set = "SAFFL == 'Y'",
                       data_subset = "ITTFL == 'Y'",
                       grouping = "TRT01P")
  refs <- ir_refs(a)
  expect_setequal(refs, c(
    "ADSL::column::AGE", "ADSL::column::TRT01P",
    "ADSL::column::SAFFL", "ADSL::column::ITTFL"
  ))
})

test_that("analysis_graph derives the ADaM -> TLF edges", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE",
                       operations = c("n", "mean"),
                       analysis_set = "SAFFL == 'Y'", grouping = "TRT01P")
  b <- new_analysis_ir("T14-3-2", "AN02", "ADVS", "AVAL", operations = "median")
  graph <- analysis_graph(c(adsl_for_analysis(), list(a, b)))

  expect_identical(graph$datasets, c("ADSL", "ADVS"))
  expect_identical(graph$outputs, c("T14-3-1", "T14-3-2"))
  expect_identical(graph$edges$from, c("ADSL", "ADVS"))
  expect_identical(graph$edges$to, c("T14-3-1", "T14-3-2"))
})

test_that("an analysis reading only underived columns contributes no edge", {
  # SAFFL is collected, not derived by this IR, so nothing links the output.
  a <- new_analysis_ir("T99-9-9", "AN09", "ADSL", "SAFFL", operations = "count")
  graph <- analysis_graph(c(adsl_for_analysis(), list(a)))
  expect_false("T99-9-9" %in% graph$edges$to)
  expect_true("T99-9-9" %in% graph$outputs)
})

test_that("dependency_graph schedules a mixed IR with analyses last", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE",
                       operations = "mean", grouping = "TRT01P")
  mixed <- c(adsl_for_analysis(), list(a))
  graph <- dependency_graph(mixed)
  expect_identical(sort(graph$order), seq_along(mixed))
  # ANALYSIS_RANK exceeds every step_rank(), so the analysis is emitted last.
  expect_identical(graph$order[length(graph$order)], length(mixed))
  expect_identical(graph$blocked, integer())
  expect_identical(graph$duplicate, character())
})

test_that("two analyses producing the same result key are reported as duplicates", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE", operations = "mean")
  graph <- dependency_graph(list(a, a))
  expect_identical(graph$duplicate, "T14-3-1::result::AN01.mean")
})

# ---- 4. Malformed analysis IR is rejected ----------------------------------

test_that("malformed analysis IRs are rejected with a reason, never repaired", {
  base <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE", operations = "mean")

  mutate <- function(field, value) {
    out <- base
    out[[field]] <- value
    out
  }

  expect_match(validate_analysis_ir_record(mutate("operations", "geomean")),
               "unknown operation", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("operations", character())),
               "no operations", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("operations", c("mean", "mean"))),
               "duplicate operations", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("dataset", "adsl")),
               "dataset must be one uppercase identifier", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("variable", "age")),
               "variable must be one uppercase identifier", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("output", "t14-3-1")),
               "output must be one uppercase output identifier", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("grouping", "trt01p")),
               "grouping must be a character vector", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("needs_human", NA)),
               "needs_human must be TRUE or FALSE", all = FALSE)

  # The predicate sublanguage is the same one safe_expression() fences for
  # layer filters: a function call is not in it.
  expect_match(validate_analysis_ir_record(mutate("analysis_set", "toupper(SAFFL) == 'Y'")),
               "not an accepted predicate expression", all = FALSE)
  expect_match(validate_analysis_ir_record(mutate("data_subset", "AVAL > 1; rm(x)")),
               "not an accepted predicate expression", all = FALSE)

  # Unknown / missing fields are a shape error, not a field-by-field error.
  extra <- base
  extra$method_oid <- "M01"
  expect_match(validate_analysis_ir_record(extra), "exact analysis IR fields", all = FALSE)

  expect_identical(
    validate_analysis_ir_record(structure(list(), class = c("aa_variable_ir", "list"))),
    "analysis record must be an aa_analysis_ir object built by new_analysis_ir()"
  )
})

test_that("duplicate output/analysis_id pairs are rejected at the list level", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE", operations = "mean")
  expect_match(validate_analysis_ir(list(a, a)), "duplicate output/analysis_id", all = FALSE)
  expect_match(validate_analysis_ir(list()), "non-empty list", all = FALSE)
})

test_that("a needs_human analysis may carry no operations and produces no edge", {
  a <- new_analysis_ir("T14-3-1", "AN01", "ADSL", "AGE",
                       operations = character(), needs_human = TRUE)
  expect_identical(validate_analysis_ir(list(a)), character())
  graph <- analysis_graph(c(adsl_for_analysis(), list(a)))
  expect_identical(nrow(graph$edges), 0L)
})
