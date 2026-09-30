audit_ir <- function() list(new_variable_ir("ADSL", "X", list(new_step("compute_var", list(target = "X", formula = "AGE + 1")))))

test_that("injection payloads are rejected by validate_ir and all rendering gates", {
  payloads <- c("system('rm -rf')", "AGE); }; system('echo audit')", "AGE; 1", "AGE # comment", "AGE <<- 1", "AGE <- 1", "AGE = 1", "base::system('echo audit')", "AGE$X", "AGE[1]", "`AGE`", "AGE %in% 1", "AGE\n1", "AGE\uff1b1", "get('AGE')", "AGE |> print()", "{AGE}")
  for (x in payloads) {
    ir <- audit_ir(); ir[[1]]$steps[[1]]$args$formula <- x
    expect_true(length(validate_ir(ir)) > 0, info = x)
    expect_error(render_variable(ir[[1]]), "Invalid IR")
    expect_error(render_program(ir), "Invalid IR")
    expect_error(execute_ir(ir, list(base = data.frame(AGE = 1))), "Invalid IR")
    ir[[1]]$steps <- list(new_step("merge_var", list(target = "X", source = "AGE", dataset_add = "dm", by_vars = "USUBJID", mode = "first", filter = x)))
    expect_true(length(validate_ir(ir)) > 0, info = x)
  }
  expect_true(safe_expression("(AGE >= 18 & SEX == 'F') | AGE < 1"))
  ir <- audit_ir(); ir[[1]]$steps[[1]]$args$formula <- "100 * (AGE - BASE) / BASE"
  expect_length(validate_ir(ir), 0)
  expect_match(render_variable(ir[[1]]), "DISCLAIMER")
  expect_true(safe_expression("AVAL.WEIGHT / (AVAL.HEIGHT / 100)^2", TRUE))
  expect_false(safe_expression("AGE + Inf", TRUE))
})

test_that("identifier and literal/comment injection cannot escape generated code", {
  for (nm in c("target", "from")) {
    ir <- list(new_variable_ir("ADSL", "X", list(new_step("assign", list(target = "X", from = "AGE")))))
    ir[[1]]$steps[[1]]$args[[nm]] <- "X); AUDIT <<- 1; #"
    expect_gt(length(validate_ir(ir)), 0)
  }
  skip_if_not_installed("dplyr")
  text <- "\" ); AUDIT <<- 1; #\n\\Unicode \u4e2d\u6587"
  ir <- list(new_variable_ir("ADSL", "X", list(new_step("assign", list(target = "X", literal = text))), spec_origin = "line\nAUDIT <<- 1", rationale = "line\rAUDIT <<- 1"))
  out <- execute_ir(ir, list(base = data.frame(AGE = 1)))
  expect_identical(out$status$status, "EXECUTED")
  expect_identical(out$adsl$X, text)
  expect_false(exists("AUDIT", out$env, inherits = FALSE))
  expect_identical(parent.env(out$env), baseenv())
})

test_that("320 randomized malformed JSON IRs return readable validation errors without crashing", {
  set.seed(20260917)
  garbage <- list(NULL, list(NULL), list(list(NULL)), character(), c("A", "B"), 7, TRUE, NA, "\u4e2d\u6587", paste(rep("X", 17000), collapse = ""))
  for (i in seq_len(320)) {
    ir <- audit_ir()
    field <- sample(c("dataset", "variable", "steps", "needs_human", "confidence", "rationale", "layer", "args", "formula"), 1)
    x <- garbage[[sample.int(length(garbage), 1)]]
    if (field %in% c("layer", "args")) ir[[1]]$steps[[1]][field] <- list(x)
    else if (field == "formula") ir[[1]]$steps[[1]]$args[field] <- list(x)
    else ir[[1]][field] <- list(x)
    raw <- jsonlite::toJSON(ir, auto_unbox = TRUE, null = "null", na = "null")
    decoded <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
    decoded[[1]] <- structure(decoded[[1]], class = c("aa_variable_ir", "list"))
    out <- validate_ir(decoded)
    expect_type(out, "character")
    expect_true(length(out) > 0, info = paste(i, field))
    expect_true(all(nzchar(out)))
  }
})

test_that("at least ten previously unguarded error branches fail usefully", {
  mutations <- list(
    function(v) { v$dataset <- c("A", "B"); v },
    function(v) { v$needs_human <- NA; v },
    function(v) { v$confidence <- Inf; v },
    function(v) { v$steps <- list(NULL); v },
    function(v) { v$steps[[1]]$layer <- c("assign", "assign"); v },
    function(v) { v$steps[[1]]$args <- 1; v },
    function(v) { v$steps[[1]]$args$unexpected <- 1; v },
    function(v) { v$steps[[1]]$args$formula <- list(NULL); v },
    function(v) { v$steps[[1]]$args$on <- "x;1"; v },
    function(v) { v$steps <- list(); v },
    function(v) { v$variable <- "\u4e2d"; v },
    function(v) { v$spec_origin <- rep("x", 2); v })
  for (f in mutations) expect_gt(length(validate_ir(list(f(audit_ir()[[1]])))), 0)
  expect_error(execute_ir(audit_ir(), NULL), "sources")
  expect_error(execute_ir(audit_ir(), list(base = 1)), "data.frame")
  expect_error(execute_ir(audit_ir(), list(base = data.frame(AGE = 1)), variables = "MISSING"), "variables")
  expect_error(execute_ir(audit_ir(), list(base = data.frame(AGE = 1), exprs = data.frame())), "shadow")
})

test_that("partial reruns preserve other outputs and cannot resolve global data", {
  skip_if_not_installed("dplyr")
  ir <- audit_ir()
  base <- data.frame(AGE = 2, KEEP = 7)
  a <- execute_ir(ir, list(base = base))
  b <- execute_ir(ir, list(base = a$adsl), variables = "X")
  expect_equal(a$adsl, b$adsl)
  expect_identical(b$adsl$KEEP, 7)
  none <- execute_ir(ir, list(base = base), variables = character())
  expect_equal(nrow(none$status), 0)
  assign("AGE", 99, envir = globalenv())
  on.exit(rm("AGE", envir = globalenv()), add = TRUE)
  fail <- execute_ir(ir, list(base = data.frame(KEEP = 7)))
  expect_identical(fail$status$status, "ERROR")
})

test_that("derived date names and self-imputation are rejected before mutation", {
  ir <- list(new_variable_ir("ADSL", "X", list(new_step("dtm_to_dt", list(target = "X", source = "TRTSDTM")))))
  expect_match(paste(validate_ir(ir), collapse = " "), "target must equal")
  ir[[1]]$steps <- list(new_step("impute_dtc", list(target = "XDT", dtc = "XDT", output_class = "dt", highest_imputation = "D", date_imputation = "first")))
  expect_match(paste(validate_ir(ir), collapse = " "), "differ from dtc")
})


test_that("public boundaries return actionable diagnostics", {
  for (x in list(NULL, list(), data.frame(), data.frame(WRONG = 1))) {
    for (f in list(read_spec_df, build_context)) expect_error(f(x), "spec.*(data.frame|columns)")
    for (f in list(read_define, parse_define, read_spec, read_dataset_json, dataset_json_meta, read_artifact)) expect_error(f(x), "path")
    expect_error(evals_accuracy(x), "logical ok column")
    expect_error(validation_comments(x), "aa_variable_ir")
    expect_error(write_program_artifact(x, dir = tempfile()), "Invalid IR")
  }
  expect_error(run_validation(NULL, audit_ir()), "data.frame")
  expect_error(artifact_hash(data.frame(WRONG = 1)), "aa_variable_ir")
  expect_error(ir_dependency_report(data.frame(WRONG = 1)), "aa_variable_ir")
  expect_error(check_admiral_compat(data.frame(WRONG = 1)), "aa_variable_ir")
  empty <- mock_spec_adsl()[FALSE, ]
  expect_equal(nrow(read_spec_df(empty)), 0)
})

test_that("Unicode artifacts and overwrite-in-place arithmetic retain inputs", {
  skip_if_not_installed("dplyr")
  ir <- audit_ir(); ir[[1]]$steps[[1]]$args$formula <- "X + 1"
  out <- execute_ir(ir, list(base = data.frame(X = 2)))
  expect_identical(out$status$status, "EXECUTED")
  expect_equal(out$adsl$X, 3)
  ir <- list(new_variable_ir("ADSL", "X", list(new_step("assign", list(target = "X", literal = "\u4e2d\u6587")))))
  dir <- tempfile(); dir.create(dir)
  files <- write_artifact(ir, dir)
  e <- new.env(parent = baseenv()); e$ADSL <- data.frame(AGE = 1)
  source(file.path(dir, files[1]), local = e, encoding = "UTF-8")
  expect_identical(e$ADSL$X, "\u4e2d\u6587")
  expect_true(all(vapply(layer_docs(), function(doc) grepl("on:", doc, fixed = TRUE), logical(1))))
})


test_that("malformed JSON and infinite duplicate breakpoints do not crash", {
  for (raw in c("[null]", "[1]", '[{"steps":[1]}]', '[{"steps":[{"args":1}]}]')) expect_null(parse_ir_json(raw))
  ir <- audit_ir(); ir[[1]]$steps <- list(new_step("categorize", list(target = "X", from = "AGE", breaks = c(-Inf, Inf, Inf), labels = c("a", "b"))))
  expect_match(paste(validate_ir(ir), collapse = " "), "strictly increasing")
  st <- new_step("assign", list(target = "X", literal = list(list(NULL))))
  ir[[1]]$steps <- list(st)
  expect_gt(length(validate_ir(ir)), 0)
})


test_that("BDS-only operations and naked parameter references are rejected", {
  a <- list(paramcd = "BMI", param = "BMI", parameters = "WEIGHT", formula = "AVAL.WEIGHT + 1", by_vars = "USUBJID")
  ir <- list(new_variable_ir("ADSL", "BMI", list(new_step("compute_param", a))))
  expect_match(paste(validate_ir(ir), collapse = " "), "BDS parameter")
  ir[[1]]$dataset <- "ADVS"
  ir[[1]]$steps[[1]]$args$formula <- "WEIGHT + 1"
  expect_match(paste(validate_ir(ir), collapse = " "), "AVAL.<PARAMCD>", fixed = TRUE)
})
