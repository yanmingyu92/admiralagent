for (f in list.files("admiralagent/R", "[.]R$", full.names = TRUE)) source(f, encoding = "UTF-8")
exports <- sub("export\\((.*)\\)", "\\1", grep("^export", readLines("admiralagent/NAMESPACE"), value = TRUE))
garbage <- list(null = NULL, list = list(), empty_df = data.frame(), wrong_columns = data.frame(WRONG = 1))
rows <- list()
for (nm in exports) {
 f <- get(nm); fs <- formals(f)
 if (!length(fs) || nm == "mcp_serve") { rows[[length(rows)+1]] <- data.frame(fn=nm,input="none",result="no data argument / blocking server tested separately"); next }
 for (gn in names(garbage)) {
  a <- list(garbage[[gn]]); names(a) <- names(fs)[1]
  if ("dataset" %in% names(fs) && names(fs)[1] != "dataset") a$dataset <- "ADSL"
  if (nm == "render_step") { a$v <- new_variable_ir("ADSL", "X", list(new_step("assign",list(target="X",literal="a")))); a$i <- 1 }
  if (nm == "execute_ir") a$sources <- list(base=data.frame(X=1))
  if (nm == "run_validation") a$ir <- list(new_variable_ir("ADSL","X",list(new_step("assign",list(target="X",literal="a")))))
  if (nm == "codelist_from_data") a$data <- data.frame(X=1)
  if (nm %in% c("new_variable_ir")) a$variable <- "X"
  if (nm == "log_run") a$file <- tempfile()
  if (nm %in% c("write_artifact","write_program_artifact")) a$dir <- tempfile()
  if (nm == "classify_variables_llm") a$chat <- list()
  result <- tryCatch({suppressWarnings(do.call(f,a)); "ACCEPTED"},error=function(e) conditionMessage(e))
  rows[[length(rows)+1]] <- data.frame(fn=nm,input=gn,result=result)
 }
}
write.csv(do.call(rbind,rows),"admiralagent/audit/export-inputs.csv",row.names=FALSE,fileEncoding="UTF-8")
layers <- aa_layers()
write.csv(data.frame(layer=names(layers),fn=vapply(layers,`[[`,"", "fn"),args=vapply(layers,function(l) paste(names(l$args),collapse=","),""),prompt=vapply(layer_docs(),function(x) grepl(x,build_system_prompt(),fixed=TRUE),logical(1))),"admiralagent/audit/layers.csv",row.names=FALSE)
# Compare Rd argument items with actual signatures and exports.
rd <- lapply(list.files("admiralagent/man", "[.]Rd$", full.names=TRUE), tools::parse_Rd)
rdtags <- function(x, tag) unlist(lapply(x,function(y) if (identical(attr(y,"Rd_tag"),tag)) paste(unlist(y),collapse="") else NULL))
docrows <- lapply(exports,function(nm) {
 hit <- Filter(function(x) nm %in% rdtags(x,"\\alias"),rd)
 params <- if(length(hit)) unlist(lapply(hit[[1]],function(x) if(identical(attr(x,"Rd_tag"),"\\arguments")) vapply(Filter(function(y) identical(attr(y,"Rd_tag"),"\\item"),x),function(y) paste(unlist(y[[1]]),collapse=""),"") else NULL)) else character()
 data.frame(fn=nm,missing_doc=!length(hit),missing_params=paste(setdiff(names(formals(get(nm))),params),collapse=","),extra_params=paste(setdiff(params,names(formals(get(nm)))),collapse=","))
})
write.csv(do.call(rbind,docrows),"admiralagent/audit/docs.csv",row.names=FALSE)
spec <- mock_spec_adsl()[rep(1,500),]; spec$variable <- paste0("V",seq_len(500)); spec$derivation <- "DM.STUDYID"
time <- system.time({ir <- classify_variables(spec,"ADSL"); code <- render_program(ir)})
writeLines(capture.output(time),"admiralagent/audit/performance.txt")
cat("elapsed",time[["elapsed"]],"layers",length(layers),"exports",length(exports),"\n")
