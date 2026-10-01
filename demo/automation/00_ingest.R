# Stage 00 - ingest: real spec + SDTM discovery for the CDISC pilot showcase.
#
# Inputs (read-only):
#   - pilot5 submission define workbook (adam-pilot-5.xlsx)  -> ADaM spec
#   - pilot5 original SDTM .xpt files                        -> execution inputs
# Outputs (demo/automation/out/):
#   - spec_adsl.rds / spec_adsl.csv   normalized spec (read_spec_df format)
#   - ingest_manifest.json            provenance + file digests + derivation
#                                     source counts (method vs predecessor)

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("00", "ingest")

stopifnot(file.exists(spec_xlsx))
built <- build_spec_from_define_xlsx(spec_xlsx, dataset = "ADSL")
spec <- built$spec
saveRDS(spec, file.path(out_dir, "spec_adsl.rds"))
utils::write.csv(spec, file.path(out_dir, "spec_adsl.csv"), row.names = FALSE)

sdtm_files <- file.path(sdtm_dir, paste0(c("dm", "ex", "vs", "ae", "sv", "ds", "sc", "mh", "qs"), ".xpt"))
sdtm_present <- file.exists(sdtm_files)
sdtm_meta <- lapply(sdtm_files[sdtm_present], function(p) {
  x <- haven::read_xpt(p)
  list(file = basename(p), sha256 = file_sha256(p), rows = nrow(x), cols = ncol(x))
})
names(sdtm_meta) <- basename(sdtm_files[sdtm_present])

oracle_adsl <- file.path(oracle_dir, "adsl.xpt")

manifest <- list(
  stage = "00_ingest",
  generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  spec_source = list(
    file = spec_xlsx,
    sha256 = file_sha256(spec_xlsx),
    note = paste(
      "P21-style define workbook from the pilot5 submission.",
      "Not metacore-compatible (read_spec() fails on it); spec rows were",
      "derived by joining Variables$Method to Methods$Description.",
      "Variables with only a Predecessor pointer received the mechanical",
      "derivation 'Copied directly from <DS.VAR>'. No free text was invented."
    )
  ),
  dataset = "ADSL",
  n_spec_variables = nrow(spec),
  derivation_source_counts = as.list(table(built$derivation_source)),
  origin_counts = as.list(table(spec$origin)),
  sdtm_inputs = sdtm_meta,
  sdtm_missing = basename(sdtm_files[!sdtm_present]),
  oracle_adsl = list(file = oracle_adsl, sha256 = file_sha256(oracle_adsl))
)
write_json(manifest, file.path(out_dir, "ingest_manifest.json"))

cat("spec variables:", nrow(spec), "\n")
cat("derivation sources:", paste(names(table(built$derivation_source)), as.integer(table(built$derivation_source)), sep = "=", collapse = ", "), "\n")
cat("sdtm loaded:", length(sdtm_meta), "files; missing:", length(manifest$sdtm_missing), "\n")
