r3_ir <- function() list(new_variable_ir("ADSL", "X", list(new_step("assign", list(target="X", from="AGE")))))
r3_date <- function(output_class="dt") new_variable_ir("ADSL", paste0("X",toupper(output_class)), list(new_step("impute_dtc", list(target=paste0("X",toupper(output_class)),dtc="DTC",output_class=output_class,highest_imputation="D",date_imputation="first"))))

test_that("date-only reruns preserve unrelated time flags", {
  skip_if_not_installed("admiral")
  base <- data.frame(DTC=c("2020-01-01","2020-02"), XTMF=c("KEEP","U"))
  v <- r3_date()
  expect_length(validate_ir(list(v)),0)
  first <- execute_ir(list(v),list(base=base))
  second <- execute_ir(list(v),list(base=first$adsl),variables="XDT")
  expect_identical(first$status$status,"EXECUTED")
  expect_identical(first$adsl$XTMF,base$XTMF)
  expect_equal(second$adsl,first$adsl)
  expect_setequal(step_output_columns(v$steps[[1]]),step_products(v,v$steps[[1]])$input)
  dtm <- r3_date("dtm")
  expect_setequal(step_output_columns(dtm$steps[[1]]),step_products(dtm,dtm$steps[[1]])$input)
})
test_that("date-only imputation cannot silently ignore a time rule", {
  v <- r3_date(); v$steps[[1]]$args$time_imputation <- "last"
  expect_match(paste(validate_ir(list(v)),collapse=" "),"time_imputation.*dtm")
  expect_error(render_variable(v),"time_imputation")
  expect_error(execute_ir(list(v),list(base=data.frame(DTC="2020"))),"time_imputation")
  expect_match(build_system_prompt(),"preserve existing time flags",fixed=TRUE)
  v <- r3_date("dtm"); v$steps[[1]]$args$time_imputation <- "last"
  expect_length(validate_ir(list(v)),0)
  expect_match(render_variable(v),'time_imputation = "last"',fixed=TRUE)
})
test_that("program finalize requires a scalar logical", {
  for (x in list(NULL,list(),data.frame(),NA,c(TRUE,FALSE),matrix(TRUE),1)) expect_error(render_program(r3_ir(),finalize=x),"finalize.*logical scalar")
})
test_that("program backend label rejects nonstrings and missing values", {
  for (x in list(NULL,list(),data.frame(),NA,c("a","b"),"")) expect_error(render_program(r3_ir(),backend_label=x),"backend_label")
})
test_that("validation quiet reports the offending public argument", {
  for (x in list(NULL,list(),NA,c(TRUE,FALSE),matrix(TRUE))) expect_error(run_validation(data.frame(X=1),r3_ir(),quiet=x),"quiet")
})
test_that("execution quiet rejects matrix flags", {
  expect_error(execute_ir(r3_ir(),list(base=data.frame(AGE=1)),quiet=matrix(TRUE)),"quiet")
})
test_that("compatibility installed has a bounded version contract", {
  for (x in list(list(),data.frame(),character(),c("1","2"),"invalid",42)) expect_error(check_admiral_compat(r3_ir(),installed=x),"installed")
  expect_length(check_admiral_compat(r3_ir(),installed="1.5.0"),0)
})
test_that("ordering rejects malformed known_columns", {
  for (x in list(NULL,list(),NA,data.frame(),matrix("AGE"))) expect_error(order_variables(r3_ir(),x),"known_columns")
})
test_that("dependency reporting rejects malformed known_columns", {
  for (x in list(NULL,list(),NA,data.frame(),matrix("AGE"))) expect_error(ir_dependency_report(r3_ir(),x),"known_columns")
})
test_that("IR scalar and vector fields reject matrices", {
  v <- r3_ir()[[1]]; v$needs_human <- matrix(TRUE)
  expect_match(paste(validate_ir(list(v)),collapse=" "),"needs_human")
  v <- r3_ir()[[1]]; v$steps[[1]]$args$from <- matrix("AGE")
  expect_match(paste(validate_ir(list(v)),collapse=" "),"arg 'from'")
  v <- new_variable_ir("ADSL","X",list(new_step("categorize",list(target="X",from="AGE",breaks=c(0,18,100),labels=c("Y","A"),right=matrix(TRUE)))))
  expect_match(paste(validate_ir(list(v)),collapse=" "),"arg 'right'")
})
test_that("spec ingestion rejects duplicate names and nonscalar cells", {
  spec <- mock_spec_adsl()[1,,drop=FALSE]
  names(spec)[2] <- names(spec)[1]
  expect_error(read_spec_df(spec),"unique")
  spec <- mock_spec_adsl()[1,,drop=FALSE]; spec$derivation <- list(c("A","B"))
  expect_error(classify_variables(spec,"ADSL"),"derivation.*scalar")
  spec$derivation <- matrix("A")
  expect_error(build_context(spec),"derivation.*scalar")
})
test_that("240 JSON mutation cases return readable diagnostics without execution", {
  set.seed(20260918)
  values <- list(NULL,list(NULL),list(list(NULL)),TRUE,42,character(),c("A","B"),"\u4e2d\u6587",strrep("A",17000))
  for (i in seq_len(240)) {
    ir <- r3_ir(); key <- sample(c("dataset","variable","confidence","needs_human","steps"),1)
    ir[[1]][key] <- list(values[[sample.int(length(values),1)]])
    if (i %% 6 == 0) ir[[1]]$steps <- list(list(layer="unknown",args=list()))
    if (i %% 7 == 0) { ir[[1]]$steps <- list(); ir[[1]]$needs_human <- FALSE }
    raw <- jsonlite::toJSON(ir,auto_unbox=TRUE,null="null",na="null")
    dec <- jsonlite::fromJSON(raw,simplifyVector=FALSE)
    dec[[1]] <- structure(dec[[1]],class=c("aa_variable_ir","list"))
    problems <- validate_ir(dec)
    expect_type(problems,"character")
    expect_gt(length(problems),0)
    expect_true(all(nzchar(problems)))
  }
})