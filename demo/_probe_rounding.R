ours <- readRDS(file.path("demo", "automation", "out", "adsl_llm.rds"))
oracle <- haven::read_xpt(file.path("..", "cdisc_data", "pilot5data", "original-adamdata", "adsl.xpt"))
m <- merge(ours[, c("USUBJID", "HEIGHTBL", "WEIGHTBL")],
           oracle[, c("USUBJID", "HEIGHTBL", "WEIGHTBL")],
           by = "USUBJID", suffixes = c(".ours", ".oracle"))
cat("HEIGHTBL rounded-1dp agree:", mean(round(m$HEIGHTBL.ours, 1) == m$HEIGHTBL.oracle, na.rm = TRUE), "\n")
cat("WEIGHTBL rounded-1dp agree:", mean(round(m$WEIGHTBL.ours, 1) == m$WEIGHTBL.oracle, na.rm = TRUE), "\n")
