# Shared helpers for the CDISC pilot automation showcase pipeline.
# Sourced by every stage (00-05) and by run_all.R. No stage writes outside
# demo/automation/out/.

# Locate the package root by walking up from getwd() (or from the sourcing
# script's directory) until a DESCRIPTION naming admiralagent is found.
find_pkg_root <- function() {
  candidates <- unique(c(getwd(), dirname(this_script_path())))
  for (start in candidates) {
    d <- normalizePath(start, winslash = "/", mustWork = FALSE)
    for (i in 1:6) {
      desc <- file.path(d, "DESCRIPTION")
      if (file.exists(desc) && any(grepl("^Package:\\s*admiralagent\\s*$", readLines(desc)))) {
        return(d)
      }
      parent <- dirname(d)
      if (identical(parent, d)) break
      d <- parent
    }
  }
  stop("could not locate admiralagent package root from ", getwd(), call. = FALSE)
}

# Path of the file currently being source()d (best effort; falls back to getwd()).
this_script_path <- function() {
  frames <- sys.frames()
  for (f in rev(frames)) {
    if (!is.null(f$ofile)) return(normalizePath(f$ofile, winslash = "/"))
  }
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg)) return(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
  file.path(getwd(), "run_all.R")
}

pkg_root <- find_pkg_root()
auto_dir <- file.path(pkg_root, "demo", "automation")
out_dir <- file.path(auto_dir, "out")
cdisc_dir <- normalizePath(file.path(pkg_root, "..", "cdisc_data"), winslash = "/", mustWork = FALSE)
spec_xlsx <- file.path(cdisc_dir, "pilot5data", "pilot5-submission", "pilot5-input",
                       "adamdata", "adam-pilot-5.xlsx")
sdtm_dir <- file.path(cdisc_dir, "pilot5data", "original-sdtmdata")
oracle_dir <- file.path(cdisc_dir, "pilot5data", "original-adamdata")
env_file <- normalizePath(file.path(pkg_root, "..", ".env"), winslash = "/", mustWork = FALSE)

if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# Source the package (demo context: no installed package assumed).
for (f in list.files(file.path(pkg_root, "R"), pattern = "[.]R$", full.names = TRUE)) source(f)

# --- .env loading (pattern from demo/demo_llm.R; values never printed) -------

read_env_file <- function(path) {
  kv <- list()
  if (!file.exists(path)) return(kv)
  for (l in readLines(path)) {
    if (grepl("^[A-Za-z_]+=", l)) {
      parts <- strsplit(l, "=", fixed = TRUE)[[1]]
      kv[[parts[1]]] <- paste(parts[-1], collapse = "=")
    }
  }
  kv
}

ensure_deepseek_key <- function() {
  if (nzchar(Sys.getenv("DEEPSEEK_API_KEY"))) return(invisible(TRUE))
  env <- read_env_file(env_file)
  if (!is.null(env$DEEPSEEK_API_KEY) && nzchar(env$DEEPSEEK_API_KEY)) {
    Sys.setenv(DEEPSEEK_API_KEY = env$DEEPSEEK_API_KEY)
    return(invisible(TRUE))
  }
  stop("DEEPSEEK_API_KEY not found in environment or ", env_file, call. = FALSE)
}

make_chat <- function(model = "deepseek-chat") {
  ensure_deepseek_key()
  if (exists("chat_deepseek", where = asNamespace("ellmer"), inherits = FALSE)) {
    ellmer::chat_deepseek(model = model)
  } else {
    ellmer::chat_openai(base_url = "https://api.deepseek.com", model = model)
  }
}

# --- spec construction from the real P21-style define workbook ----------------
#
# adam-pilot-5.xlsx is the pilot5 submission's define workbook (sheets:
# Datasets / Variables / ValueLevel / Methods / Codelists / ...). It is NOT in
# metacore's expected spec layout, so read_spec() fails on it; the spec data
# frame is derived here by joining Variables$Method -> Methods$Description.
# Every derivation string below is verbatim from the workbook; variables whose
# only metadata is a Predecessor pointer get an explicit "Copied directly from
# <DS.VAR>" derivation, and ingest_manifest.json records how many rows used
# each path. No derivation text is invented beyond that mechanical template.

build_spec_from_define_xlsx <- function(xlsx, dataset = "ADSL") {
  vars <- as.data.frame(readxl::read_excel(xlsx, sheet = "Variables"))
  methods <- as.data.frame(readxl::read_excel(xlsx, sheet = "Methods"))
  vars <- vars[vars$Dataset == dataset, , drop = FALSE]

  method_desc <- stats::setNames(methods$Description, methods$ID)
  derivation <- character(nrow(vars))
  deriv_source <- character(nrow(vars))
  for (i in seq_len(nrow(vars))) {
    mid <- vars$Method[i]
    if (!is.na(mid) && mid %in% names(method_desc)) {
      derivation[i] <- gsub("\\s+", " ", trimws(method_desc[[mid]]))
      deriv_source[i] <- "method"
    } else if (!is.na(vars$Predecessor[i]) && nzchar(vars$Predecessor[i])) {
      derivation[i] <- paste0("Copied directly from ", vars$Predecessor[i])
      deriv_source[i] <- "predecessor"
    } else {
      derivation[i] <- vars$Label[i]
      deriv_source[i] <- "label_fallback"
    }
  }

  # Predecessor "DM.STUDYID" -> source_dataset "dm", source_variable "STUDYID"
  src_ds <- rep(NA_character_, nrow(vars))
  src_var <- rep(NA_character_, nrow(vars))
  pred <- vars$Predecessor
  has_pred <- !is.na(pred) & grepl("^[A-Za-z]+\\.[A-Za-z0-9_]+$", pred)
  src_ds[has_pred] <- tolower(sub("\\..*$", "", pred[has_pred]))
  src_var[has_pred] <- sub("^.*\\.", "", pred[has_pred])

  spec <- data.frame(
    dataset = vars$Dataset,
    variable = vars$Variable,
    label = vars$Label,
    type = tolower(vars[["Data Type"]]),
    origin = tolower(vars$Origin),
    derivation = derivation,
    stringsAsFactors = FALSE
  )
  spec$source_dataset <- src_ds
  spec$source_variable <- src_var
  spec$order <- as.character(vars$Order)
  spec$codelist <- vars$Codelist
  list(spec = read_spec_df(spec), derivation_source = deriv_source)
}

# --- SDTM loading -------------------------------------------------------------

load_pilot5_sdtm <- function(names = c("dm", "ex", "vs", "ae", "sv", "ds", "sc", "mh", "qs")) {
  out <- list()
  for (nm in names) {
    p <- file.path(sdtm_dir, paste0(nm, ".xpt"))
    if (file.exists(p)) out[[nm]] <- haven::read_xpt(p)
  }
  # BDS shape for vs, mirroring demo/demo_llm_exec.R: PARAMCD/AVAL are the
  # tokens the layer vocabulary references.
  if (!is.null(out$vs)) {
    out$vs <- dplyr::mutate(out$vs, AVAL = VSSTRESN, PARAMCD = VSTESTCD)
  }
  out
}

# --- misc ---------------------------------------------------------------------

write_json <- function(x, path) {
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
  invisible(path)
}

file_sha256 <- function(path) digest::digest(file = path, algo = "sha256")

ir_layers_label <- function(ir) {
  vapply(ir, function(v) {
    if (isTRUE(v$needs_human)) "needs_human" else paste(vapply(v$steps, function(s) s$layer, character(1)), collapse = "->")
  }, character(1))
}

stage_banner <- function(stage, title) {
  cat(sprintf("\n========== stage %s: %s ==========\n", stage, title))
}
