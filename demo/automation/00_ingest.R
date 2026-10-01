# Stage 00 - ingest: real spec + SDTM discovery for the CDISC pilot showcase.
#
# Inputs (read-only):
#   - pilot5 submission define workbook (adam-pilot-5.xlsx)  -> ADaM spec
#   - pilot5 original SDTM .xpt files                        -> execution inputs
# Outputs (demo/automation/out/):
#   - spec_<ds>.rds / spec_<ds>.csv   normalized spec per dataset (read_spec_df
#                                     format; ADSL keeps the unsuffixed names
#                                     spec_adsl.rds / spec_adsl.csv)
#   - mc_<ds>.rds                     mock_metacore() object per dataset, built
#                                     from the workbook's Codelists sheet, for
#                                     codelist_var execution (sources$mc)
#   - ingest_manifest.json            provenance + file digests + derivation
#                                     source counts (method vs predecessor)

source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "_common.R"))
stage_banner("00", "ingest")

stopifnot(file.exists(spec_xlsx))
datasets <- showcase_datasets()

specs <- list()
for (ds in datasets) {
  built <- build_spec_from_define_xlsx(spec_xlsx, dataset = ds)
  spec <- built$spec
  specs[[ds]] <- list(spec = spec, derivation_source = built$derivation_source)
  saveRDS(spec, out_file_ds("spec", ds, ".rds"))
  utils::write.csv(spec, out_file_ds("spec", ds, ".csv"), row.names = FALSE)
  cat(sprintf("%-6s spec variables: %d (derivation sources: %s)\n", ds, nrow(spec),
              paste(names(table(built$derivation_source)), as.integer(table(built$derivation_source)),
                    sep = "=", collapse = ", ")))
}

# --- codelists + executable metacore objects ----------------------------------
# codelist_var steps render metatools::create_var_from_codelist(metacore = mc),
# so every dataset needs an mc built from the workbook's own Codelists sheet
# (finding F-02). If metacore is unavailable the mc is NULL and the manifest
# records the boundary instead of faking one.
codelists <- codelists_from_define_xlsx(spec_xlsx)
cat("codelists built from Codelists sheet:", length(codelists), "\n")

mc_paths <- list()
for (ds in datasets) {
  mc <- withCallingHandlers(
    mock_metacore(specs[[ds]]$spec, codelists = codelists),
    warning = function(w) {
      cat(sprintf("%-6s mock_metacore warning: %s\n", ds, conditionMessage(w)))
      invokeRestart("muffleWarning")
    }
  )
  if (is.null(mc)) {
    mc_paths[[ds]] <- list(path = NA, note = "metacore package not available; codelist_var cannot execute")
  } else {
    p <- out_file_ds("mc", ds, ".rds")
    saveRDS(mc, p)
    mc_paths[[ds]] <- list(path = p, n_codelists = length(codelists))
  }
}

sdtm_files <- file.path(sdtm_dir, paste0(c("dm", "ex", "vs", "ae", "sv", "ds", "sc", "mh", "qs", "lb"), ".xpt"))
sdtm_present <- file.exists(sdtm_files)
sdtm_meta <- lapply(sdtm_files[sdtm_present], function(p) {
  x <- haven::read_xpt(p)
  list(file = basename(p), sha256 = file_sha256(p), rows = nrow(x), cols = ncol(x))
})
names(sdtm_meta) <- basename(sdtm_files[sdtm_present])

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
  datasets = lapply(datasets, function(ds) {
    list(
      dataset = ds,
      n_spec_variables = nrow(specs[[ds]]$spec),
      derivation_source_counts = as.list(table(specs[[ds]]$derivation_source)),
      origin_counts = as.list(table(specs[[ds]]$spec$origin)),
      oracle = list(file = file.path(oracle_dir, paste0(tolower(ds), ".xpt")),
                    sha256 = file_sha256(file.path(oracle_dir, paste0(tolower(ds), ".xpt")))),
      metacore = mc_paths[[ds]]
    )
  }),
  codelists_built = length(codelists),
  sdtm_inputs = sdtm_meta,
  sdtm_missing = basename(sdtm_files[!sdtm_present])
)
names(manifest$datasets) <- datasets
write_json(manifest, file.path(out_dir, "ingest_manifest.json"))

cat("sdtm loaded:", length(sdtm_meta), "files; missing:", length(manifest$sdtm_missing), "\n")
