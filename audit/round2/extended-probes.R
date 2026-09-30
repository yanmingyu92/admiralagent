
e <- new.env(parent=globalenv())
for(f in list.files("admiralagent/audit/round2/before-src/R","[.]R$",full.names=TRUE)) source(f,local=e,encoding="UTF-8")
v <- function(name,formula) e$new_variable_ir("ADSL",name,list(e$new_step("compute_var",list(target=name,formula=formula))),spec_origin="audit",rationale="audit")
spec <- e$mock_spec_adsl()[1,,drop=FALSE];spec$variable <- "X";spec$origin <- "Derived";spec$derivation <- "X=AGE+1"
out <- e$classify_variables(spec,"ADSL")
cat("Rule X=AGE+1 was reduced to from:",out[[1]]$steps[[1]]$args$from,"\n")
spec$variable <- "X"
out <- e$consensus_vote(spec,list(list(v("X","AGE+1")),list(v("X","AGE+2")),list(v("X","AGE+2"))),"majority")
cat("Two AGE+2 votes vs one AGE+1 selected:",out$ir[[1]]$steps[[1]]$args$formula,"\n")
x <- e$new_variable_ir("ADSL","X",list(e$new_step("assign",list(target="X",from="T"))))
out <- e$execute_ir(list(x),list(base=data.frame(AGE=1)))
cat("Missing column T:",out$status$status,"generated value",out$adsl$X,"\n")
cat("Malformed numeric became NA:",is.na(e$dsj_num_or_na("not-a-number")),"\n")
date <- e$dsj_parse_temporal("2024-01-01T12:30:00+02:00","Datetime")
cat("Offset datetime UTC was:",format(date,tz="UTC"),"expected 10:30\n")
x <- e$new_variable_ir("ADSL","GROUP",list(e$new_step("categorize",list(target="GROUP",from="AGE",breaks=c(0,1.23456789,3),labels=c("a","b")))))
out <- e$execute_ir(list(x),list(base=data.frame(AGE=c(1.23456789,1.23456789+1e-10))))
cat("Precise boundary labels:",paste(as.character(out$adsl$GROUP),collapse=","),"expected a,b\n")
