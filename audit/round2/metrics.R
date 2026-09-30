for (stage in c("before","delivery")) {
 path <- paste0("admiralagent/audit/round2/tests-",stage,".rds")
 x <- readRDS(path)
 cat(stage,"cases",nrow(x),"passed",sum(x$passed),"failed",sum(x$failed),"errors",sum(x$error),"warnings",sum(x$warning),"skipped",sum(x$skipped),"\n")
}
x <- readRDS("admiralagent/audit/round2/check-delivery-result.rds")
counts <- vapply(x[c("errors","warnings","notes")],length,integer(1))
print(counts)
stopifnot(all(counts==0))
