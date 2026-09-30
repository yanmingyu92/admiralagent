
for (f in list.files("admiralagent/R", "[.]R$", full.names = TRUE)) source(f, encoding="UTF-8")
for (stage in c("before","after")) {
 x <- readRDS(paste0("admiralagent/audit/tests-",stage,".rds"))
 cat(stage, "cases", nrow(x),"passed",sum(x$passed),"failed",sum(x$failed),"errors",sum(x$error),"warnings",sum(x$warning),"skipped",sum(x$skipped),"\n")
}
e <- new.env(); utils::data("dm",package="pharmaversesdtm",envir=e); utils::data("adsl",package="pharmaverseadam",envir=e)
ir <- classify_variables(mock_spec_adsl(),"ADSL")
x <- execute_ir(ir,list(base=e$dm),variables=c("TRT01P","TRTSDTM"))
m <- merge(x$adsl[,c("USUBJID","TRT01P","TRTSDTM")],e$adsl[,c("USUBJID","TRT01P","TRTSDTM")],by="USUBJID")
a <- as.Date(m$TRTSDTM.x); b <- as.Date(m$TRTSDTM.y)
cat("TRT01P",mean(m$TRT01P.x==m$TRT01P.y),"TRTSDTM comparable",sum(!is.na(a)&!is.na(b)),"missing both",sum(is.na(a)&is.na(b)),"nonmissing match",mean(a==b,na.rm=TRUE),"including matching missing",mean((is.na(a)&is.na(b))|(!is.na(a)&!is.na(b)&a==b)),"\n")
for (stage in c("before","after")) {
 d <- read.csv(paste0("admiralagent/audit/define-",stage,".csv"))
 cat(stage,"define",sum(!is.na(d$oracle_match_pct)),"comparable",sum(d$oracle_match_pct==100,na.rm=TRUE),"100%\n")
}
