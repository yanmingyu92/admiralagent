for (stage in c("before","after")) {
 x <- readRDS(paste0("admiralagent/audit/round3/tests-",stage,".rds"))
 cat(stage,"cases",nrow(x),"passed",sum(x$passed),"failed",sum(x$failed),"errors",sum(x$error),"warnings",sum(x$warning),"skipped",sum(x$skipped),"\n")
}
for (prefix in c("accuracy","define")) {
 a <- read.csv(paste0("admiralagent/audit/round3/",prefix,"-before.csv"))
 b <- read.csv(paste0("admiralagent/audit/round3/",prefix,"-after.csv"))
 cat(prefix,"identical",identical(a,b),"\n"); stopifnot(identical(a,b))
 if (prefix=="define") cat("define comparable",sum(!is.na(b$oracle_match_pct)),"at100",sum(b$oracle_match_pct==100,na.rm=TRUE),"\n")
}