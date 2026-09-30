for (f in list.files(file.path("admiralagent", "R"), pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}

spec <- mock_spec_adsl()
ir <- classify_variables(spec, "ADSL", backend = "rules")

cat("IR gate:", if (length(validate_ir(ir)) == 0) "PASS (0 problems)" else "FAIL", "\n")
cat("Variables:", length(ir),
    "| needs_human:", sum(vapply(ir, function(v) v$needs_human, logical(1))), "\n\n")

files <- write_program_artifact(ir, dir = file.path("admiralagent", "demo", "gen"))
cat("Artifacts written:\n -", paste(files, collapse = "\n - "), "\n\n")

cat(readLines(file.path("admiralagent", "demo", "gen", files[1])), sep = "\n")
