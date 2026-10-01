serializable_args <- function(args) {
  if (is.numeric(args$breaks) && any(is.infinite(args$breaks))) {
    args$breaks <- lapply(args$breaks, function(x) if (is.infinite(x)) as.character(x) else x)
  }
  args
}

# Arg insertion order is authoring noise, not semantics: sorting names here
# keeps `artifact_hash()` stable across two constructions of the same step.
# Variable order and step order ARE semantic and are preserved.
sorted_args <- function(args) {
  args <- serializable_args(args)
  if (length(args)) args[order(names(args))] else args
}

canonical_ir <- function(ir) {
  plain <- lapply(ir, function(v) list(
    dataset = v$dataset,
    variable = v$variable,
    steps = lapply(v$steps, function(s) list(layer = s$layer, args = sorted_args(s$args))),
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
#'   and step order); used in deterministic artifact file names so identical IRs
#'   always overwrite the same files. The package version is deliberately NOT
#'   part of the hash: it is recorded as provenance in sidecars/manifests
#'   instead, so a version bump never silently moves artifact identities.
#' @title Artifact hash
#' @param ir List of `aa_variable_ir` objects.
#' @return An 8-character hash string.
#' @export
artifact_hash <- function(ir) {
  assert_ir_shape(ir)
  substr(digest::digest(
    paste0(canonical_ir(ir), "|admiralagent"),
    algo = "xxhash64", serialize = FALSE
  ), 1, 8)
}

# sha256 of the bytes actually on disk, so the seal is independent of how the
# string was encoded or line-ended on the way out.
file_digest <- function(path) digest::digest(file = path, algo = "sha256")

# `ir_hash` seals the IR THIS sidecar carries; `code_digest` seals the rendered
# file next to it. Neither is an input to `canonical_ir()` / `artifact_hash()`:
# the sidecar describes an artifact, it never participates in naming it.
sidecar_fields <- function(artifact, ir, backend_label, model = NULL, validation = NULL,
                           gate = NULL, code_path = NULL, gate_enforced = NA) {
  list(
    artifact = artifact,
    package_version = pkg_ver(),
    backend = backend_label,
    model = model,
    ir = jsonlite::fromJSON(canonical_ir(ir), simplifyVector = FALSE),
    ir_hash = artifact_hash(ir),
    code_digest = if (is.null(code_path)) NULL else file_digest(code_path),
    gate = if (is.null(gate)) NULL else unclass(gate),
    # Written on EVERY sidecar, gated or not. An ungated artifact used to be
    # identifiable only by the ABSENCE of a gate field, which is exactly the
    # shape of evidence an auditor cannot rely on: absence is also what a
    # truncated write, an older package version or a stripped sidecar looks
    # like. A positive label cannot be confused with any of those.
    # `release_grade` is a property of THIS artifact; `gate_enforced` is the
    # policy that was in force when it was written. Neither is an input to
    # `canonical_ir()` / `artifact_hash()`.
    release_grade = artifact_release_grade(gate),
    gate_enforced = gate_enforced,
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
      sidecar_fields(artifact, list(v), backend_label, model, validation, code_path = path)
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
#' @param gate Optional approval gate from `sign_gate()`, recorded in the
#'   program header, the sidecar and the run log. A gate names a signer, a
#'   moment and a reason; it is not a claim that any derivation is correct.
#' @param require_gate Whether a covering approval gate is mandatory. `NULL`
#'   (default) reads `getOption("admiralagent.require_gate", TRUE)`:
#'   enforcement is ON out of the box, so an ungated write is refused and the
#'   refusal itself is logged.
#'
#'   Writing ungated requires an explicit opt-out - `require_gate = FALSE` on
#'   the call, or the option switched off for the session - and is never
#'   silent: the rendered program carries an `UNGATED DRAFT` banner, the
#'   sidecar and the audit record carry `release_grade = "ungated-draft"` and
#'   `gate_enforced = FALSE`, and the first ungated write of a session prints a
#'   notice. An ungated artifact is never release-grade.
#' @return Invisibly, the character vector of files written.
#' @export
write_program_artifact <- function(ir, dir = "gen", backend_label = "rules", model = NULL,
                                   gate = NULL, require_gate = NULL) {
  assert_valid_ir(ir)
  assert_path(dir)
  log_file <- file.path(dir, "admiralagent_log.jsonl")
  # Resolved ONCE and threaded through the block, the banner, the sidecar and
  # the audit record, so what the artifact claims about the policy is what the
  # policy actually did. `log_run_manifest()` resolves the same way.
  policy <- gate_policy(require_gate)
  gate <- gate_check(gate, gate_scope(ir), "write_program_artifact()",
                     policy$enforced, log_file)
  # Reachable only with enforcement off: `gate_check()` has already stopped an
  # ungated write when enforcement is on.
  if (is.null(gate)) gate_off_notice(policy)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  ds <- unique(vapply(ir, function(v) v$dataset, character(1)))[[1]]
  hash <- artifact_hash(ir)
  artifact <- paste0(tolower(ds), "__program__", hash, ".R")
  path <- file.path(dir, artifact)
  code <- render_program(ir, backend_label = backend_label, gate = gate)
  if (is.null(gate)) code <- ungated_banner(code)
  write_utf8(code, path)
  write_sidecar(
    file.path(dir, paste0(artifact, ".json")),
    sidecar_fields(artifact, ir, backend_label, model, gate = gate, code_path = path,
                   gate_enforced = policy$enforced)
  )
  details <- list(
    artifact = artifact,
    backend = backend_label,
    release_grade = artifact_release_grade(gate),
    gate_enforced = policy$enforced,
    gate_policy_source = policy$source
  )
  if (!is.null(gate)) details$gate_id <- gate$gate_id
  log_run("write_program", details, file = log_file)
  invisible(c(artifact, paste0(artifact, ".json")))
}

# ---------------------------------------------------------------------------
# Artifact integrity on reload
# ---------------------------------------------------------------------------

# `<dataset>__<variable|program>__<hash8>.R`
ARTIFACT_NAME_RE <- "^.+__([0-9a-f]{8})[.][Rr]$"

# Checked in a fixed order so the first error names the outermost thing that is
# wrong: the artifact this sidecar belongs to, then the IR it carries, then the
# code it sealed, then the approval attached to it.
verify_artifact_integrity <- function(path, sc, ir) {
  sidecar_name <- basename(path)
  expected <- sub("[.]json$", "", sidecar_name)

  # 1. name drift: the sidecar must still be the sidecar of the file it names
  if (!is.null(sc$artifact)) {
    if (!scalar_text(sc$artifact) || !identical(sc$artifact, expected)) {
      stop("artifact name drift: this sidecar is the sidecar of '",
           if (scalar_text(sc$artifact)) sc$artifact else "<unreadable>",
           "' but was read as '", expected,
           "'; the artifact was renamed or the sidecar was moved", call. = FALSE)
    }
  }
  name <- if (scalar_text(sc$artifact)) sc$artifact else expected

  # 2. hash drift: the IR carried here must still hash to what the artifact was
  # sealed and named under. This is what rejects a `needs_human` flipped in the
  # sidecar: the flag is an input to canonical_ir(), so flipping it moves the
  # hash away from the one the file is named with.
  claimed <- if (scalar_text(sc$ir_hash)) {
    sc$ir_hash
  } else if (grepl(ARTIFACT_NAME_RE, name)) {
    sub(ARTIFACT_NAME_RE, "\\1", name)
  } else {
    NA_character_
  }
  actual <- artifact_hash(ir)
  if (!is.na(claimed) && !identical(actual, claimed)) {
    stop("artifact hash drift: the IR in this sidecar hashes to ", actual,
         " but the artifact is sealed as ", claimed,
         "; the sidecar IR was edited (for example needs_human flipped) or the ",
         "file was renamed", call. = FALSE)
  }

  # 3. digest drift: sidecar and rendered code must not have drifted apart
  if (!is.null(sc$code_digest)) {
    if (!scalar_text(sc$code_digest)) {
      stop("artifact sidecar carries an unreadable code_digest", call. = FALSE)
    }
    code_path <- file.path(dirname(path), name)
    if (!file.exists(code_path)) {
      stop("rendered program '", name, "' is missing beside its sidecar; ",
           "the sealed code cannot be verified", call. = FALSE)
    }
    on_disk <- file_digest(code_path)
    if (!identical(on_disk, sc$code_digest)) {
      stop("rendered code digest drift: '", name, "' now digests to ",
           substr(on_disk, 1, 16), " but the sidecar sealed ",
           substr(sc$code_digest, 1, 16),
           "; the generated code was edited after it was written", call. = FALSE)
    }
    # 3b. abstention drift. Everything above compares the sidecar with values
    # the sidecar itself carries, so an editor who recomputes `ir_hash` stays
    # consistent. The rendered code does not follow: a variable whose
    # `needs_human` was flipped to FALSE still has its abstention block in the
    # .R file. Comparing the two closes the bypass without re-rendering (which
    # would make every artifact unreadable after a version bump).
    code_lines <- readLines(code_path, warn = FALSE)
    for (v in ir) {
      marker <- review_block_marker(v)
      if (renders_review_block(v) != any(grepl(marker, code_lines, fixed = TRUE))) {
        stop("abstention drift: the sidecar says ", v$variable, " needs_human = ",
             isTRUE(v$needs_human), " but the rendered code for '", name,
             "' says otherwise; the abstention flag was edited in the sidecar",
             call. = FALSE)
      }
    }
  }

  # 4. the approval attached to the artifact, if any
  gate <- if (is.null(sc$gate)) NULL else as_gate(sc$gate)

  # 5. grade drift: the label must match what the sidecar actually carries. A
  # sidecar that calls itself release-grade while carrying no approval is the
  # exact confusion the grade exists to prevent, so it is refused rather than
  # believed. Sidecars written before the label existed carry none and are read
  # as-is; their grade is inferred from the gate in `read_artifact()`.
  if (scalar_text(sc$release_grade) &&
      !identical(sc$release_grade, artifact_release_grade(gate))) {
    stop("release grade drift: this sidecar is labelled '", sc$release_grade,
         "' but carries ", if (is.null(gate)) "no approval gate" else "an approval gate",
         "; the grade label was edited", call. = FALSE)
  }
  gate
}

#' Read an artifact sidecar back into an IR
#'
#' @description Parses a sidecar JSON, renormalizes its IR through
#'   [new_step()]/[new_variable_ir()] (including step-level `on` absorption),
#'   and returns the IR with its provenance fields. Stale or malformed
#'   sidecars surface as errors rather than silently loading.
#'
#'   Reloading also re-checks integrity, in this order: the sidecar still names
#'   the artifact it was read as; the IR it carries still hashes to the value
#'   the artifact was sealed and named under; the rendered `.R` beside it still
#'   digests to the value the sidecar sealed; and any attached approval gate is
#'   well formed and unedited. Each check is a hard error. Together they detect
#'   drift between sidecar, code and file name - they are not signatures, and
#'   the identity anchor for an approval remains the gate record in the
#'   hash-chained audit log.
#' @title Read artifact
#' @param path Path to the sidecar `.json` file.
#' @return A list with elements `ir`, `artifact`, `backend`, `model`,
#'   `created_at`, `validation`, `gate` (`NULL` when ungated), `release_grade`
#'   (`"gated"` or `"ungated-draft"`), `release_ready` and `gate_enforced`
#'   (the policy in force when the artifact was written, `NA` for artifacts
#'   written before that was recorded).
#' @export
read_artifact <- function(path) {
  assert_path(path)
  sc <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (!is.list(sc) || is.null(sc$ir)) stop("artifact must contain an ir array", call. = FALSE)
  ir <- normalize_ir_records(sc$ir)
  assert_valid_ir(ir)
  gate <- verify_artifact_integrity(path, sc, ir)
  list(
    ir = ir,
    artifact = sc$artifact,
    backend = sc$backend,
    model = sc$model,
    created_at = sc$created_at,
    validation = sc$validation,
    gate = gate,
    # Derived from the gate rather than read from the label, so a historical
    # artifact written before the label existed is still self-identifying and
    # an edited label can never upgrade one (see check 5 above).
    release_grade = artifact_release_grade(gate),
    release_ready = is_release_grade(artifact_release_grade(gate)),
    gate_enforced = if (is.logical(sc$gate_enforced) && length(sc$gate_enforced) == 1L) {
      sc$gate_enforced
    } else {
      NA
    }
  )
}
