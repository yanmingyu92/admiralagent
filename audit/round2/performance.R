
for(f in list.files("admiralagent/R","[.]R$",full.names=TRUE)) source(f,encoding="UTF-8")
spec <- mock_spec_adsl()[rep(1,500),];spec$variable <- paste0("V",seq_len(500));spec$derivation <- "DM.STUDYID"
print(system.time({ir <- classify_variables(spec,"ADSL");code <- render_program(ir)}))
