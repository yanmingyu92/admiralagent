serializable_args <- function(args) {
  if (is.numeric(args$breaks) && any(is.infinite(args$breaks))) {
    args$breaks <- lapply(args$breaks, function(x) if (is.infinite(x)) as.character(x) else x)
  }
  args
}

canonical_ir <- function(ir) {
  plain <- lapply(ir, function(v) list(
    dataset = v$dataset,
    variable = v$variable,
    steps = lapply(v$steps, function(s) list(layer = s$layer, args = serializable_args(s$args))),
    spec_origin = v$spec_origin,
    confidence = v$confidence,
    needs_human = v$needs_human,
    rationale = v$rationale
  ))
  jsonlite::toJSON(unname(plain), auto_unbox = TRUE, null = "null", na = "null", digits = NA)
}

#' Deterministic hash of a variable IR
#'
#' @description Hashes the canonical JSON of the IR (preserving variable
#'   and step order) plus the package version; used in deterministic artifact file
#'   names so identical IRs always overwrite the same files.
#' @title Artifact hash
#' @param ir List of `aa_variable_ir` objects.
#' @return An 8-character hash string.
#' @export
artifact_hash <- function(ir) {
  assert_ir_shape(ir)
  substr(digest::digest(
    paste0(canonical_ir(ir), "|admiralagent|", pkg_ver()),
    algo = "xxhash64", serialize = FALSE
  ), 1, 8)
}

sidecar_fields <- function(artifact, ir, backend_label, model = NULL, validation = NULL) {
  list(
    artifact = artifact,
    package_version = pkg_ver(),
    backend = backend_label,
    model = model,
    ir = jsonlite::fromJSON(canonical_ir(ir), simplifyVector = FALSE),
    validation = validation,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    disclaimer = "DRAFT generated code; human review required before regulated use"
  )
}

write_sidecar <- function(path, fields) {
  jsonlite::write_json(fields, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
}

#' Write per-variable artifacts and sidecars
#'
#' @description Writes one `<dataset>__<variable>__<hash8>.R` artifact per
#'   variable (rendered code with CHECK comments) plus a JSON sidecar
#'   recording the IR, backend, model, validation result, and disclaimer.
#'   Same IR overwrites the same files; copies never accumulate.
#' @title Write variable artifacts
#' @param ir List of `aa_variable_ir` objects.
#' @param dir Output directory (created when missing).
#' @param backend_label Backend label recorded in sidecars.
#' @param model Model identifier recorded in sidecars (LLM backend).
#' @param validation Optional validation result recorded in sidecars.
#' @return Invisibly, the character vector of files written.
#' @export
write_artifact <- function(ir, dir = "gen", backend_label = "rules", model = NULL, validation = NULL) {
  assert_valid_ir(ir)
  assert_path(dir)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  hash <- artifact_hash(ir)
  written <- character()
  for (v in ir) {
    artifact <- paste0(
      tolower(v$dataset), "__", tolower(v$variable), "__", hash, ".R"
    )
    path <- file.path(dir, artifact)
    write_utf8(render_variable(v), path)
    write_sidecar(
      file.path(dir, paste0(artifact, ".json")),
      sidecar_fields(artifact, list(v), backend_label, model, validation)
    )
    written <- c(written, artifact, paste0(artifact, ".json"))
  }
  invisible(written)
}

#' Write the assembled program artifact
#'
#' @description Renders the full program via [render_program()], writes it as
#'   `<dataset>__program__<hash8>.R` with a JSON sidecar, and appends a
#'   `write_program` entry to the run log.
#' @title Write program artifact
#' @param ir Non-empty list of `aa_variable_ir` objects.
#' @param dir Output directory (created when missing).
#' @param backend_label Backend label recorded in header and sidecar.
#' @param model Model identifier recorded in the sidecar (LLM backend).
#' @return Invisibly, the character vector of files written.
#' @export
write_program_artifact <- function(ir, dir = "gen", backend_label = "rules", model = NULL) {
  assert_valid_ir(ir)
  assert_path(dir)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  ds <- unique(vapply(ir, function(v) v$dataset, character(1)))[[1]]
  hash <- artifact_hash(ir)
  artifact <- paste0(tolower(ds), "__program__", hash, ".R")
  path <- file.path(dir, artifact)
  write_utf8(render_program(ir, backend_label = backend_label), path)
  write_sidecar(
    file.path(dir, paste0(artifact, ".json")),
    sidecar_fields(artifact, ir, backend_label, model)
  )
  log_run("write_program", list(artifact = artifact, backend = backend_label),
          file = file.path(dir, "admiralagent_log.jsonl"))
  invisible(c(artifact, paste0(artifact, ".json")))
}

#' Append an entry to the audit log
#'
#' @description Appends one JSON line (timestamp, package version, event,
#'   details) to a JSONL audit log.
#' @title Log a run
#' @param event Event name (e.g. `"write_program"`, `"llm_consensus"`).
#' @param details List of event-specific details.
#' @param file Log file path.
#' @return Invisibly `TRUE`.
#' @export
log_run <- function(event, details = list(), file = "admiralagent_log.jsonl") {
  entry <- list(
    time = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    package_version = pkg_ver(),
    event = event,
    details = details
  )
  cat(jsonlite::toJSON(entry, auto_unbox = TRUE), "\n", file = file, append = TRUE)
  invisible(TRUE)
}

#' Read an artifact sidecar back into an IR
#'
#' @description Parses a sidecar JSON, renormalizes its IR through
#'   [new_step()]/[new_variable_ir()] (including step-level `on` absorption),
#'   and returns the IR with its provenance fields. Stale or malformed
#'   sidecars surface as errors rather than silently loading.
#' @title Read artifact
#' @param path Path to the sidecar `.json` file.
#' @return A list with elements `ir`, `artifact`, `backend`, `model`,
#'   `created_at`, and `validation`.
#' @export
read_artifact <- function(path) {
  assert_path(path)
  sc <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!is.list(sc) || is.null(sc$ir)) stop("artifact must contain an ir array", call. = FALSE)
  ir <- normalize_ir_records(sc$ir)
  assert_valid_ir(ir)
  list(
    ir = ir,
    artifact = sc$artifact,
    backend = sc$backend,
    model = sc$model,
    created_at = sc$created_at,
    validation = sc$validation
  )
}
