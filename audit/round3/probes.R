for (f in list.files("admiralagent/R", "[.]R$", full.names=TRUE)) source(f, encoding="UTF-8")
v <- new_variable_ir("ADSL", "XDT", list(new_step("impute_dtc", list(target="XDT",dtc="DTC",output_class="dt",highest_imputation="D",date_imputation="first"))))
base <- data.frame(DTC="2020-01-01", XTMF="KEEP")
x <- execute_ir(list(v), list(base=base))
cat("date-only gate:",paste(validate_ir(list(v)),collapse=";"),"status",x$status$status,"columns",names(x$adsl),"\n")
v$steps[[1]]$args$time_imputation <- "last"
cat("ignored time option:",paste(validate_ir(list(v)),collapse=";"),"render contains last",grepl("last",render_variable(v)),"\n")
v <- new_variable_ir("ADSL","X",list(new_step("categorize",list(target="X",from="AGE",breaks=c(0,18,100),labels=c("young","adult"),right=matrix(TRUE)))))
cat("matrix logical gate:",paste(validate_ir(list(v)),collapse=";"),"\n")
print(execute_ir(list(v),list(base=data.frame(AGE=18)))$adsl)
for (value in list(NULL,list(),data.frame(),c(TRUE,FALSE),NA)) {
 cat("finalize:",tryCatch({render_program(list(v),finalize=value);"ACCEPT"},error=conditionMessage),"\n")
}