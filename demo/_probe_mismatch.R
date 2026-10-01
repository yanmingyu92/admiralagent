# probe 3: characterize the three LLM partial mismatches (HEIGHTBL/WEIGHTBL/AGEGR1N)
out <- file.path("demo", "automation", "out")
ours <- readRDS(file.path(out, "adsl_llm.rds"))
oracle <- haven::read_xpt(file.path("..", "cdisc_data", "pilot5data", "original-adamdata", "adsl.xpt"))

m <- merge(ours[, c("USUBJID", "HEIGHTBL", "WEIGHTBL", "AGE", "AGEGR1N")],
           oracle[, c("USUBJID", "HEIGHTBL", "WEIGHTBL", "AGEGR1N")],
           by = "USUBJID", suffixes = c(".ours", ".oracle"))

cat("=== HEIGHTBL ===\n")
cat("n joined:", nrow(m), "\n")
cat("agree:", mean(m$HEIGHTBL.ours == m$HEIGHTBL.oracle, na.rm = TRUE), "\n")
d <- m[m$HEIGHTBL.ours != m$HEIGHTBL.oracle, ]
cat("mismatched:", nrow(d), " of ", nrow(m), "\n")
cat("height ours values:", paste(sort(unique(ours$HEIGHTBL)), collapse = " "), "\n")
cat("height oracle values:", paste(sort(unique(oracle$HEIGHTBL)), collapse = " "), "\n")

cat("\n=== WEIGHTBL ===\n")
cat("agree:", mean(m$WEIGHTBL.ours == m$WEIGHTBL.oracle, na.rm = TRUE), "\n")
cat("sample ours:  ", paste(head(m$WEIGHTBL.ours, 6), collapse = " "), "\n")
cat("sample oracle:", paste(head(m$WEIGHTBL.oracle, 6), collapse = " "), "\n")

cat("\n=== AGEGR1N boundary check ===\n")
bad <- m[m$AGEGR1N.ours != m$AGEGR1N.oracle, ]
cat("mismatched:", nrow(bad), "of", nrow(m), "\n")
print(table(bad$AGE))
cat("-> all mismatches at AGE==80 would confirm the 65-80 vs >=80 boundary reading\n")

# also: what does oracle use for HEIGHTBL/WEIGHTBL vs VS visits? compare against vs directly
vs <- haven::read_xpt(file.path("..", "cdisc_data", "pilot5data", "original-sdtmdata", "vs.xpt"))
h <- vs[vs$VSTESTCD == "HEIGHT", c("USUBJID", "VISITNUM", "VSSTRESN")]
w <- vs[vs$VSTESTCD == "WEIGHT", c("USUBJID", "VISITNUM", "VSSTRESN")]
cat("\nHEIGHT visits present:", paste(sort(unique(h$VISITNUM)), collapse = " "), "\n")
cat("WEIGHT visits present:", paste(sort(unique(w$VISITNUM)), collapse = " "), "\n")
# for one mismatched subject, list their HEIGHT/WEIGHT records vs oracle value
sub <- d$USUBJID[1]
cat("subject", sub, ": ours HEIGHTBL =", d$HEIGHTBL.ours[1], ", oracle =", d$HEIGHTBL.oracle[1], "\n")
print(h[h$USUBJID == sub, ])
subw <- m$USUBJID[m$WEIGHTBL.ours != m$WEIGHTBL.oracle][1]
cat("subject", subw, ": ours WEIGHTBL =", m$WEIGHTBL.ours[m$USUBJID == subw], ", oracle =", m$WEIGHTBL.oracle[m$USUBJID == subw], "\n")
print(w[w$USUBJID == subw, ])
