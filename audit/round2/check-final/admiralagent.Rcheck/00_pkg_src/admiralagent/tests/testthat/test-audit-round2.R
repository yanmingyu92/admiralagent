
r2_var <- function(name, formula = "AGE + 1") new_variable_ir("ADSL", name, list(new_step("compute_var",list(target=name,formula=formula))), spec_origin="audit",rationale="audit")
r2_json <- function(ir) jsonlite::toJSON(ir,auto_unbox=TRUE,null="null",na="null",digits=NA)

test_that("a foreign step cannot bypass render_step validation via substitution", {
  v <- r2_var("X")
  for (payload in c("system('echo blocked')", "AGE;1", "AGE <<- 1")) {
    s <- new_step("compute_var",list(on="ex",target="X",formula=payload))
    expect_error(render_step(s,v,1), "identical")
    v2 <- v; v2$steps <- list(s,new_step("assign",list(target="X",literal="ok")))
    expect_error(render_variable(v2), "Invalid IR")
  }
  expect_error(render_step(v$steps[[1]],v,Inf), "index")
  expect_error(render_step(v$steps[[1]],v,2), "index")
})

test_that("all IR decoders preserve bad types instead of executing coerced review flags", {
  rec <- jsonlite::fromJSON(r2_json(list(r2_var("X"))),simplifyVector=FALSE)
  for (field in c("needs_human","confidence")) {
    bad <- rec; bad[[1]][field] <- list(if(field=="needs_human") "true" else "1")
    parsed <- parse_ir_json(r2_json(bad))
    expect_gt(length(validate_ir(parsed)),0)
    path <- tempfile(fileext=".json")
    jsonlite::write_json(list(ir=bad),path,auto_unbox=TRUE)
    expect_error(read_artifact(path),"Invalid IR")
    expect_gt(length(validate_ir(normalize_ir_records(bad))),0)
  }
  bad <- rec; bad[[1]]$steps[[1]]$args$formula <- list("AGE + 1")
  expect_gt(length(validate_ir(parse_ir_json(r2_json(bad)))),0)
  bad <- rec; bad[[1]]$steps[[1]]$on <- "ex"; bad[[1]]$steps[[1]]$args$on <- "dm"
  expect_null(parse_ir_json(r2_json(bad)))
  expect_null(parse_ir_json(sub('"dataset":"ADSL"','"dataset":"ADSL","dataset":"ADVS"',r2_json(rec),fixed=TRUE)))
  bad <- r2_var("X"); names(bad)[names(bad)=="confidence"] <- "confidence_typo"
  expect_gt(length(validate_ir(list(bad))),0)
})

test_that("LLM batch identity is exact and malformed replies enter retry feedback", {
  skip_if_not_installed("ellmer")
  batch <- mock_spec_adsl()[1:2,]
  for (ir in list(list(r2_var("X")), list(r2_var("STUDYID"),r2_var("STUDYID")),list(r2_var("STUDYID")))) {
    expect_error(classify_batch(batch,list(chat=function(prompt) r2_json(ir)),1),"exactly one matching|duplicate")
  }
  expected <- list(r2_var("STUDYID"),r2_var("USUBJID"))
  calls <- 0; prompts <- character()
  chat <- list(chat=function(prompt) {
    calls <<- calls+1; prompts[calls] <<- prompt
    if(calls==1) r2_json(list(r2_var("EXTRA"))) else r2_json(rev(expected))
  })
  out <- classify_batch(batch,chat,2)
  expect_identical(vapply(out,`[[`,"","variable"),batch$variable)
  expect_match(prompts[2],"exactly one matching")
  for(nm in c("batch_size","max_attempts","samples")) for(x in c(0,Inf,NA,1.5)) {
    args <- list(vars=batch,chat=chat); args[[nm]] <- x
    expect_error(do.call(classify_variables_llm,args),"positive integer")
  }
})

test_that("consensus distinguishes arguments and does not elect a minority rule", {
  skip_if_not_installed("ellmer")
  vars <- mock_spec_adsl()[1,,drop=FALSE]
  a <- r2_var("STUDYID","AGE + 1"); b <- r2_var("STUDYID","AGE + 2")
  out <- consensus_vote(vars,list(list(a),list(b),list(b)),"majority")
  expect_identical(out$ir[[1]]$steps[[1]]$args$formula,"AGE + 2")
  expect_false(out$consensus$unanimous)
  tie <- consensus_vote(vars,list(list(a),list(b)),"majority")
  expect_true(tie$ir[[1]]$needs_human)
  expect_length(tie$ir[[1]]$steps,0)
})

test_that("artifact serialization preserves order and full numeric precision", {
  ir <- list(r2_var("Z"),r2_var("A"))
  expect_false(identical(artifact_hash(ir),artifact_hash(rev(ir))))
  path <- tempfile();dir.create(path)
  written <- write_program_artifact(ir,path)
  art <- read_artifact(file.path(path,written[2]))
  expect_identical(vapply(art$ir,`[[`,"","variable"),c("Z","A"))
  v <- new_variable_ir("ADSL","GROUP",list(new_step("categorize",list(target="GROUP",from="AGE",breaks=c(0,1.23456789,3),labels=c("a","b")))))
  json <- canonical_ir(list(v))
  expect_match(json,"1.23456789",fixed=TRUE)
})


test_that("formula dependencies override rank and input order instead of using stale values", {
  skip_if_not_installed("dplyr")
  x <- r2_var("X","Y + 1"); y <- r2_var("Y","AGE + 1")
  ir <- list(x,y)
  expect_length(validate_ir(ir),0)
  out <- execute_ir(ir,list(base=data.frame(AGE=1,Y=100)))
  expect_equal(out$adsl$X,3)
  expect_identical(out$status$variable,c("Y","X"))
  expect_identical(out$status$status,c("EXECUTED","EXECUTED"))
  cycle <- list(r2_var("X","Y + 1"),r2_var("Y","X + 1"))
  expect_match(paste(validate_ir(cycle),collapse=" "),"cyclic")
  expect_error(execute_ir(cycle,list(base=data.frame(X=100,Y=100))),"cyclic")
  expect_match(paste(validate_ir(list(x,x)),collapse=" "),"duplicate")
  other <- y; other$variable <- "OTHER"; other$steps[[1]]$args$target <- "X"
  expect_match(paste(validate_ir(list(x,other)),collapse=" "),"same output")
})

test_that("failed variable rolls back every step and blocks stale downstream reads", {
  skip_if_not_installed("dplyr")
  y <- r2_var("Y","MISSING + 1")
  y$steps <- c(list(new_step("assign",list(target="TEMP",literal="partial"))),y$steps)
  x <- r2_var("X","Y + 1")
  z <- r2_var("Z","AGE + 2")
  out <- execute_ir(list(x,y,z),list(base=data.frame(AGE=1,Y=100)))
  expect_false("TEMP" %in% names(out$adsl))
  expect_false("X" %in% names(out$adsl))
  expect_equal(out$adsl$Y,100)
  expect_equal(out$adsl$Z,3)
  expect_match(out$status$note[out$status$variable=="X"],"upstream")
  partial <- execute_ir(list(x,y),list(base=data.frame(Y=100)),variables="X")
  expect_equal(partial$adsl$X,101)
  expect_identical(partial$status$status,"EXECUTED")
})

test_that("dependency report does not treat review-only or future inputs as available", {
  ir <- list(r2_var("X","Y + 1"),new_variable_ir("ADSL","Y",needs_human=TRUE))
  report <- ir_dependency_report(ir)
  expect_true("Y" %in% report$input)
  v <- r2_var("X","TEMP + 1")
  v$steps[[2]] <- new_step("assign",list(target="TEMP",literal="late"))
  expect_true("TEMP" %in% ir_dependency_report(list(v))$input)
  low <- r2_var("X"); low$confidence <- 0.5
  expect_match(paste(validate_ir(list(low)),collapse=" "),"needs_human")
})


test_that("Dataset-JSON rejects lossy cells and retains timezone instants", {
  file_for <- function(type,value,target=NULL) {
    p <- tempfile(fileext=".json")
    jsonlite::write_json(list(datasetJSONVersion="1.1.0",records=1,columns=list(list(name="X",dataType=type,targetDataType=target)),rows=list(list(value))),p,auto_unbox=TRUE,null="null")
    p
  }
  for(value in list("not a number",list(1,2),TRUE)) expect_error(read_dataset_json(file_for("float",value)),"schema")
  expect_error(read_dataset_json(file_for("integer",1.5)),"fractional")
  expect_error(read_dataset_json(file_for("boolean","yes")),"boolean")
  out <- read_dataset_json(file_for("datetime","2024-01-01T12:30:00+02:00","Datetime"))
  expect_identical(format(out$X,tz="UTC",format="%Y-%m-%d %H:%M:%S"),"2024-01-01 10:30:00")
  out <- read_dataset_json(file_for("datetime","2024-01-01T12:30-05:30","Datetime"))
  expect_identical(format(out$X,tz="UTC",format="%Y-%m-%d %H:%M:%S"),"2024-01-01 18:00:00")
  for(value in c("2024-01", "2024-01-01garbage", "2024-02-30")) {
    out <- read_dataset_json(file_for("date",value,"Date"))
    expect_identical(out$X,value)
  }
})


test_that("base environment constants cannot masquerade as missing columns", {
  skip_if_not_installed("dplyr")
  for(col in c("T","F","LETTERS")) {
    v <- new_variable_ir("ADSL","X",list(new_step("assign",list(target="X",from=col))))
    out <- execute_ir(list(v),list(base=data.frame(AGE=seq_len(26))))
    expect_identical(out$status$status,"ERROR")
    expect_match(out$status$note,"missing from source")
    expect_false("X" %in% names(out$adsl))
  }
  expect_identical(execute_ir(list(r2_var("X","T + 1")),list(base=data.frame(T=3)))$adsl$X,4)
})

test_that("sidecars round-trip infinite breaks and full numeric precision", {
  v <- new_variable_ir("ADSL","GROUP",list(new_step("categorize",list(target="GROUP",from="AGE",breaks=c(-Inf,1.23456789,Inf),labels=c("a","b")))))
  dir <- tempfile();dir.create(dir)
  paths <- write_artifact(list(v),dir)
  read <- read_artifact(file.path(dir,paths[2]))
  expect_identical(read$ir[[1]]$steps[[1]]$args$breaks,v$steps[[1]]$args$breaks)
  v2 <- v;v2$steps[[1]]$args$breaks[2] <- 1.23456788
  expect_false(identical(artifact_hash(list(v)),artifact_hash(list(v2))))
})


test_that("guard cannot delete an imputation or parameter input", {
  v <- new_variable_ir("ADSL","XDTM",list(new_step("impute_dtc",list(target="XDTM",dtc="XDTF",output_class="dtm",highest_imputation="M",date_imputation="first"))))
  expect_match(paste(validate_ir(list(v)),collapse=" "),"flag columns")
  v <- new_variable_ir("ADVS","BMI",list(new_step("compute_param",list(paramcd="BMI",param="BMI",parameters="BMI",formula="AVAL.BMI+1",by_vars="USUBJID"))))
  expect_match(paste(validate_ir(list(v)),collapse=" "),"differ from input")
})

test_that("PARAMCD filter consumers depend on parameter producers", {
  producer <- new_variable_ir("ADVS","BMI",list(new_step("compute_param",list(paramcd="BMI",param="BMI",parameters="WEIGHT",formula="AVAL.WEIGHT+1",by_vars="USUBJID"))))
  consumer <- new_variable_ir("ADSL","BMIBL",list(new_step("merge_var",list(target="BMIBL",source="AVAL",dataset_add="ADVS",by_vars="USUBJID",mode="first",filter="PARAMCD == 'BMI'"))))
  expect_identical(vapply(order_variables(list(consumer,producer)),`[[`,"","variable"),c("BMI","BMIBL"))
})


test_that("rendered numeric breakpoints retain full boundary precision", {
  skip_if_not_installed("dplyr")
  edge <- 1.23456789
  v <- new_variable_ir("ADSL","GROUP",list(new_step("categorize",list(target="GROUP",from="AGE",breaks=c(0,edge,3),labels=c("a","b")))))
  out <- execute_ir(list(v),list(base=data.frame(AGE=c(edge,edge+1e-10))))
  expect_identical(as.character(out$adsl$GROUP),c("a","b"))
})


test_that("all 14 layers survive 420 adversarial cross-gate and serialization probes", {
  e <- new.env(parent=baseenv())
  eval(parse(file="test-layers-golden.R",encoding="UTF-8")[[1]],envir=e)
  fixtures <- e$GOLDEN_ARGS
  garbage <- list(NULL, list(NULL), c("A","B"), "X;1", "system('echo blocked')", NA, 1.25, Inf, "\u4e2d", paste(rep("X",17000),collapse=""), "SAFE", list("AGE"))
  set.seed(20260918)
  for(layer in names(fixtures)) for(i in seq_len(30)) {
    a <- fixtures[[layer]]
    if(i>1) {
      nm <- sample(names(aa_layers()[[layer]]$args),1)
      a[nm] <- list(garbage[[sample.int(length(garbage),1)]])
    }
    v <- new_variable_ir("ADVS","X",list(structure(list(layer=layer,args=a),class=c("aa_step","list"))))
    problems <- validate_ir(list(v))
    expect_type(problems,"character")
    if(!length(problems)) {
      code <- render_variable(v)
      expect_type(parse(text=code,encoding="UTF-8"),"expression")
      back <- parse_ir_json(canonical_ir(list(v)))
      expect_length(validate_ir(back),0)
      expect_identical(render_variable(back[[1]]),code)
    } else expect_true(all(nzchar(problems)))
  }
})


test_that("rules classifier cannot truncate arithmetic to a direct assignment", {
  spec <- mock_spec_adsl()[1,,drop=FALSE]
  spec$variable <- "X";spec$origin <- "Derived"
  for(text in c("X=AGE+1","X=AGE-1","X=AGE if SEX is F","X=AGE; system('echo blocked')")) {
    spec$derivation <- text
    ir <- classify_variables(spec,"ADSL")
    expect_true(ir[[1]]$needs_human)
    expect_length(ir[[1]]$steps,0)
  }
  spec$derivation <- "X=AGE"
  ir <- classify_variables(spec,"ADSL")
  expect_identical(ir[[1]]$steps[[1]]$args$from,"AGE")
})
