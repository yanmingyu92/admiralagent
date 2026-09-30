for (f in list.files("admiralagent/R", "[.]R$", full.names=TRUE)) source(f, encoding="UTF-8")
refs <- function(expr) {
  if (!is.call(expr)) return(character())
  if (identical(expr[[1]],as.name("$")) && identical(expr[[2]],as.name("args"))) return(as.character(expr[[3]]))
  unique(unlist(lapply(as.list(expr)[-1],refs)))
}
eval(parse("admiralagent/tests/testthat/test-layers-golden.R")[[1]])
rows <- lapply(names(aa_layers()),function(nm) {
  l <- aa_layers()[[nm]]; used <- refs(body(l$render)); declared <- names(l$args)
  code <- l$render(GOLDEN_ARGS[[nm]],"ADVS")
  parsed <- tryCatch({parse(text=code);TRUE},error=function(e)FALSE)
  stopifnot(parsed,all(used %in% declared),all(l$required %in% declared),all(l$inputs %in% declared))
  data.frame(layer=nm,declared=paste(declared,collapse=","),render_refs=paste(used,collapse=","),outside_render=paste(setdiff(declared,used),collapse=","),parse=parsed,prompt=grepl(layer_docs()[[match(nm,layer_names())]],build_system_prompt(),fixed=TRUE))
})
write.csv(do.call(rbind,rows),"admiralagent/audit/round3/layer-crosscheck.csv",row.names=FALSE,fileEncoding="UTF-8")
# Verify source roxygen params against every actual export signature.
exports <- sub("export\\((.*)\\)","\\1",grep("^export",readLines("admiralagent/NAMESPACE",encoding="UTF-8"),value=TRUE))
text <- unlist(lapply(list.files("admiralagent/R","[.]R$",full.names=TRUE),readLines,encoding="UTF-8"))
roxy <- lapply(exports,function(nm) {
  i <- grep(paste0("^",nm," <- function"),text)[1]; j <- i-1L; doc <- character()
  while(j>0 && startsWith(text[j],"#'")) {doc<-c(text[j],doc);j<-j-1L}
  params <- sub(".*@param ([A-Za-z_]+).*","\\1",grep("@param ",doc,value=TRUE))
  actual <- names(formals(get(nm)))
  data.frame(fn=nm,missing=paste(setdiff(actual,params),collapse=","),extra=paste(setdiff(params,actual),collapse=","))
})
roxy <- do.call(rbind,roxy); stopifnot(all(roxy$missing==""),all(roxy$extra==""))
write.csv(roxy,"admiralagent/audit/round3/roxygen-params.csv",row.names=FALSE)
# Source-tree resource fallback, independently of the caller's parent directory.
old <- setwd("admiralagent")
cat("corpus cases",length(load_evals()),"\n")
setwd(old)
cat("layers",length(rows),"exports",length(exports),"all parsed and prompt/Rd/roxygen checked\n")