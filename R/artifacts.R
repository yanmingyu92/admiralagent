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
# Audit log: hash-chained JSONL (21 CFR Part 11 s11.10(e))
#
# Every record carries the digest of the record before it, so an edit, a
# deletion or a reordering breaks the chain at the tampered record. The chain
# is per log FILE and completely independent of `canonical_ir()` /
# `artifact_hash()`: log state must never feed the IR hash.
# ---------------------------------------------------------------------------

# prev digest of the (non-existent) record before the first one
LOG_CHAIN_GENESIS <- strrep("0", 64L)

# The digest is always the last field of a record, which lets verification
# recover the exact bytes that were hashed instead of re-serializing JSON.
LOG_DIGEST_RE <- ',"digest":"[0-9a-f]+"\\}$'

# Chain head per log file, so appending does not re-read the whole log. The
# cache is trusted only while the file is exactly the size we last wrote.
log_cache <- new.env(parent = emptyenv())

# Optional HMAC key: tamper-EVIDENCE (an editor without the key cannot forge a
# chain) on top of the tamper-detection the plain chain already gives. A
# missing key never silently downgrades: the mode is recorded in every record
# and `verify_log()` rejects an unkeyed record in a keyed log.
log_key <- function() {
  key <- getOption("admiralagent.log_key")
  if (is.null(key)) {
    key <- Sys.getenv("ADMIRALAGENT_LOG_KEY", "")
    if (!nzchar(key)) return(NULL)
  }
  if (!is.character(key) || length(key) != 1L || is.na(key) || !nzchar(key)) {
    stop("admiralagent.log_key must be a single non-empty string", call. = FALSE)
  }
  key
}

log_mode <- function(key) if (is.null(key)) "sha256" else "hmac-sha256"

#' Resolve the active audit log destination
#'
#' @description Logging is on by default. Precedence is
#'   `getOption("admiralagent.log_file")`, then the `ADMIRALAGENT_LOG_FILE`
#'   environment variable, then a session-scoped file in [tempdir()]. The
#'   default stays inside the session because a package may not write to the
#'   user's file system unasked; a regulated run points the option at a
#'   retained location.
#'   Opting out is explicit: `NA` or `FALSE` (as the option or as the argument)
#'   returns `NULL`, which callers read as "do not log".
#' @param file Optional explicit path, returned as-is after validation.
#' @return A single file path, or `NULL` when logging is switched off.
#' @noRd
aa_log_file <- function(file = NULL) {
  if (is.null(file)) {
    file <- getOption("admiralagent.log_file")
  }
  if (is.null(file)) {
    env_file <- Sys.getenv("ADMIRALAGENT_LOG_FILE", "")
    file <- if (nzchar(env_file)) env_file else file.path(tempdir(), "admiralagent_audit.jsonl")
  }
  if (identical(file, FALSE) || (is.atomic(file) && length(file) == 1L && is.na(file))) {
    return(NULL)
  }
  if (!is.character(file) || length(file) != 1L || !nzchar(file)) {
    stop("audit log file must be a single non-empty path", call. = FALSE)
  }
  file
}

chain_digest <- function(core, key) {
  if (is.null(key)) {
    digest::digest(core, algo = "sha256", serialize = FALSE)
  } else {
    digest::hmac(key, core, algo = "sha256")
  }
}

log_head <- function(file) {
  cached <- log_cache[[file]]
  size <- if (file.exists(file)) file.size(file) else NA_real_
  if (!is.null(cached) && identical(cached$size, size)) return(cached)
  empty <- list(seq = 0L, digest = LOG_CHAIN_GENESIS, size = size)
  if (is.na(size) || size == 0) return(empty)
  lines <- readLines(file, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  if (!length(lines)) return(empty)
  last <- lines[[length(lines)]]
  rec <- tryCatch(jsonlite::fromJSON(last, simplifyVector = FALSE), error = function(e) NULL)
  list(
    seq = as.integer(rec$seq %||% length(lines)),
    digest = rec$digest %||% LOG_CHAIN_GENESIS,
    size = size
  )
}

# Head pointer sidecar: the chain alone cannot notice records removed from the
# END of the log, because what remains is still internally consistent.
write_log_head <- function(file, seq, digest) {
  head <- list(seq = seq, digest = digest)
  cat(as.character(jsonlite::toJSON(head, auto_unbox = TRUE)), "\n",
      file = paste0(file, ".head"), sep = "")
  log_cache[[file]] <- list(seq = seq, digest = digest, size = file.size(file))
  invisible(TRUE)
}

#' Append an entry to the audit log
#'
#' @description Appends one JSON line (schema, sequence number, timestamp,
#'   package version, event, details, previous digest, digest mode, digest) to
#'   a hash-chained JSONL audit log. Each record seals the digest of the record
#'   before it, so editing, deleting or reordering any line is detectable with
#'   [verify_log()]. When a key is configured (`admiralagent.log_key` option or
#'   `ADMIRALAGENT_LOG_KEY`) the digest is an HMAC and the record records that
#'   mode, so a keyed log can never be silently continued unkeyed.
#' @title Log a run
#' @param event Event name (e.g. `"write_program"`, `"execute_variable"`).
#' @param details List of event-specific details. Never put patient data here.
#' @param file Log file path; defaults to the active audit log (see
#'   `admiralagent.log_file`).
#' @return Invisibly `TRUE`.
#' @export
log_run <- function(event, details = list(), file = aa_log_file()) {
  if (!is.character(event) || length(event) != 1L || is.na(event) || !nzchar(event)) {
    stop("event must be a single non-empty string", call. = FALSE)
  }
  file <- aa_log_file(file)
  if (is.null(file)) stop("audit logging is switched off; no destination to write to", call. = FALSE)
  key <- log_key()
  head <- log_head(file)
  entry <- list(
    schema = "admiralagent-audit-1",
    seq = head$seq + 1L,
    time = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    package_version = pkg_ver(),
    event = event,
    details = details,
    prev = head$digest,
    mode = log_mode(key)
  )
  payload <- as.character(jsonlite::toJSON(
    entry, auto_unbox = TRUE, null = "null", na = "null", digits = NA
  ))
  core <- substr(payload, 1L, nchar(payload) - 1L) # drop the closing brace
  seal <- chain_digest(core, key)
  dir <- dirname(file)
  if (nzchar(dir) && !dir.exists(dir)) dir.create(dir, recursive = TRUE)
  cat(core, ',"digest":"', seal, '"}\n', file = file, sep = "", append = TRUE)
  write_log_head(file, entry$seq, seal)
  invisible(TRUE)
}

#' Verify an audit log's hash chain
#'
#' @description Walks the chain from the genesis digest and stops at the first
#'   record whose sequence number, previous digest, digest mode or digest does
#'   not hold, naming that record. A trailing head pointer sidecar
#'   (`<file>.head`) additionally catches records removed from the end, which
#'   the chain alone cannot see.
#' @param file Log file path.
#' @param key Optional HMAC key; defaults to the configured key (if any).
#' @return List with `ok`, `file`, `records`, `broken_line`, `broken_seq`,
#'   `broken_event` and `reason`.
#' @noRd
verify_log <- function(file = aa_log_file(), key = log_key()) {
  if (!file.exists(file)) stop("audit log not found: ", file, call. = FALSE)
  lines <- readLines(file, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  outcome <- function(ok, line = NA_integer_, reason = "", seq = NA_integer_,
                      event = NA_character_) {
    list(ok = ok, file = file, records = length(lines), broken_line = line,
         broken_seq = seq, broken_event = event, reason = reason)
  }

  prev <- LOG_CHAIN_GENESIS
  for (i in seq_along(lines)) {
    line <- lines[[i]]
    if (!grepl(LOG_DIGEST_RE, line)) {
      return(outcome(FALSE, i, "record carries no chain digest"))
    }
    core <- sub(LOG_DIGEST_RE, "", line)
    claimed <- sub('^.*,"digest":"([0-9a-f]+)"\\}$', "\\1", line)
    rec <- tryCatch(
      jsonlite::fromJSON(paste0(core, "}"), simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.null(rec)) return(outcome(FALSE, i, "record is not parseable JSON"))
    seq_no <- rec$seq
    event <- rec$event %||% NA_character_
    if (!is.numeric(seq_no) || !identical(as.integer(seq_no), i)) {
      return(outcome(FALSE, i, paste0(
        "sequence number ", seq_no %||% "<missing>", " does not match position ", i,
        "; a record was inserted, deleted or reordered"
      ), as.integer(seq_no %||% NA), event))
    }
    if (!identical(rec$prev, prev)) {
      return(outcome(FALSE, i, paste0(
        "prev digest does not chain to record ", i - 1L,
        "; a record was edited, deleted or reordered"
      ), as.integer(seq_no), event))
    }
    if (!is.null(key) && !identical(rec$mode, "hmac-sha256")) {
      return(outcome(FALSE, i, "unkeyed record in a keyed log; possible downgrade",
                     as.integer(seq_no), event))
    }
    if (is.null(key) && identical(rec$mode, "hmac-sha256")) {
      return(outcome(FALSE, i, paste0(
        "record is HMAC-sealed but no key is configured; ",
        "set options(admiralagent.log_key = ) to verify"
      ), as.integer(seq_no), event))
    }
    if (!identical(chain_digest(core, key), claimed)) {
      return(outcome(FALSE, i, "digest does not match the record contents; record was edited",
                     as.integer(seq_no), event))
    }
    prev <- claimed
  }

  head_file <- paste0(file, ".head")
  if (file.exists(head_file)) {
    head_line <- readLines(head_file, warn = FALSE)
    head_line <- head_line[nzchar(trimws(head_line))]
    head <- if (!length(head_line)) NULL else tryCatch(
      jsonlite::fromJSON(head_line[[length(head_line)]], simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (!is.null(head) &&
        (!identical(as.integer(head$seq), length(lines)) || !identical(head$digest, prev))) {
      return(outcome(FALSE, length(lines) + 1L, paste0(
        "log ends at record ", length(lines), " but the head pointer records ",
        head$seq, "; records were removed from the end"
      )))
    }
  }
  outcome(TRUE)
}

# ---------------------------------------------------------------------------
# Approval gates
#
# WHAT A GATE IS: an approval RECORD. It names a signer, the moment they
# signed, the reason they gave, and the exact scope the approval covers. It is
# appended to the SAME hash-chained audit log as every other event, as a new
# `event` value through `log_run()` - never a second log file, because two
# chains over one run would diverge and neither would verify.
#
# WHAT A GATE IS NOT: it is not a claim that a derivation is correct, and it is
# not a substitute for independent double programming of the output data. It
# records who took responsibility for a decision and when. Nothing more.
#
# Gate information travels through function arguments, the sidecar and the log
# record's `details`. It never enters `aa_variable_ir`: `canonical_ir()`
# whitelists exactly seven fields, so a gate field on the IR would hash
# identically to an IR without it - a silent collision.
# ---------------------------------------------------------------------------

AA_GATE_SCHEMA <- "admiralagent-gate-1"
AA_GATE_FIELDS <- c("schema", "gate_id", "decision", "signer", "reason", "scope", "time")
AA_GATE_DECISIONS <- c("approve", "reject")
AA_GATE_ANY_SCOPE <- "*"

# Identity of the gate derived from its own contents, so editing a signer, a
# reason or a timestamp in a copied gate (for example in a sidecar) no longer
# matches the id it travels under.
gate_fingerprint <- function(g) {
  substr(digest::digest(paste0(
    AA_GATE_SCHEMA, "|", g$decision, "|", g$signer, "|", g$reason, "|",
    paste(g$scope, collapse = ","), "|", g$time
  ), algo = "sha256", serialize = FALSE), 1, 16)
}

#' Scope string that a gate must cover to approve an IR
#'
#' @description The scope binds an approval to exact content: it is the
#'   [artifact_hash()] of the IR, so re-deriving anything invalidates the gate
#'   rather than carrying an old approval forward.
#' @param ir List of `aa_variable_ir` objects.
#' @return A single scope string.
#' @noRd
gate_scope <- function(ir) paste0("artifact:", artifact_hash(ir))

# Per-variable scope, used when a gate clears an abstention on one variable.
gate_scope_variable <- function(v) paste0("variable:", v$dataset, ":", v$variable)

validate_gate <- function(gate) {
  if (!is.list(gate)) return("gate must be a list")
  if (!exact_fields(gate, AA_GATE_FIELDS)) {
    return(paste0("gate fields must be exactly: ", paste(AA_GATE_FIELDS, collapse = ", ")))
  }
  bad <- character()
  if (!identical(gate$schema, AA_GATE_SCHEMA)) {
    bad <- c(bad, paste0("schema must be '", AA_GATE_SCHEMA, "'"))
  }
  for (nm in c("gate_id", "signer", "reason", "time")) {
    if (!scalar_text(gate[[nm]]) || !nzchar(trimws(gate[[nm]]))) {
      bad <- c(bad, paste0(nm, " must be one non-empty string"))
    }
  }
  if (!scalar_text(gate$decision) || !gate$decision %in% AA_GATE_DECISIONS) {
    bad <- c(bad, paste0("decision must be one of ", paste(AA_GATE_DECISIONS, collapse = ", ")))
  }
  if (!is.character(gate$scope) || !length(gate$scope) || anyNA(gate$scope) ||
      !all(nzchar(gate$scope))) {
    bad <- c(bad, "scope must be a non-empty character vector of non-empty strings")
  }
  if (length(bad)) return(bad)
  if (!identical(gate$gate_id, gate_fingerprint(gate))) {
    return("gate_id does not match the gate contents; the approval record was edited")
  }
  character()
}

# Accepts a signed gate or the plain list a sidecar / log record decodes to.
as_gate <- function(gate) {
  if (inherits(gate, "aa_gate")) return(gate)
  if (is.list(gate) && !is.null(gate$scope)) {
    gate$scope <- tryCatch(as.character(unlist(gate$scope, use.names = FALSE)),
                           error = function(e) gate$scope)
  }
  bad <- validate_gate(gate)
  if (length(bad)) {
    stop("invalid approval gate: ", paste(bad, collapse = "; "), call. = FALSE)
  }
  structure(gate[AA_GATE_FIELDS], class = c("aa_gate", "list"))
}

#' Sign an approval gate and seal it into the audit log
#'
#' @description Builds an approval record (signer, timestamp, reason, scope,
#'   decision) and appends it to the hash-chained audit log as a `gate` event,
#'   so it is tamper-evident alongside the runs it authorises. Signing is
#'   refused when audit logging is switched off: an approval nobody can recover
#'   is not an approval.
#'
#'   A gate records WHO approved something and WHEN. It asserts nothing about
#'   whether the derivation is correct, and it does not replace independent
#'   double programming of the output data.
#' @param signer Identity of the human taking responsibility (name, and
#'   ideally role and contact). Never a placeholder.
#' @param reason Why the approval was given, in the signer's words.
#' @param scope Character vector of scopes the approval covers; use
#'   [gate_scope()] for an IR, or `"*"` for a blanket approval.
#' @param decision `"approve"` or `"reject"`; a rejection blocks just as
#'   an absent gate does, but records who refused and why.
#' @param file Audit log destination; defaults to the active log.
#' @return An `aa_gate` object.
#' @noRd
sign_gate <- function(signer, reason, scope, decision = "approve", file = aa_log_file()) {
  gate <- list(
    schema = AA_GATE_SCHEMA,
    gate_id = NA_character_,
    decision = decision,
    signer = if (scalar_text(signer)) trimws(signer) else signer,
    reason = if (scalar_text(reason)) trimws(reason) else reason,
    scope = scope,
    time = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  if (is.list(gate$scope)) gate$scope <- as.character(unlist(gate$scope, use.names = FALSE))
  gate$gate_id <- gate_fingerprint(gate)
  gate <- as_gate(gate)

  dest <- aa_log_file(file)
  if (is.null(dest)) {
    stop("an approval gate must be recorded in the audit log, but logging is switched off",
         call. = FALSE)
  }
  log_run("gate", unclass(gate), file = dest)
  gate
}

gate_permits <- function(gate, scope) {
  if (is.null(gate)) return(FALSE)
  g <- tryCatch(as_gate(gate), error = function(e) NULL)
  if (is.null(g) || !identical(g$decision, "approve")) return(FALSE)
  AA_GATE_ANY_SCOPE %in% g$scope || all(scope %in% g$scope)
}

# Blocking semantics in one place: no gate blocks, a malformed gate blocks, a
# rejection blocks, and a gate signed for other content blocks.
assert_gate <- function(gate, scope, action) {
  if (is.null(gate)) {
    stop(action, " requires an approval gate covering ", paste(scope, collapse = ", "),
         "; sign one with sign_gate(signer = , reason = , scope = )", call. = FALSE)
  }
  g <- as_gate(gate)
  if (identical(g$decision, "reject")) {
    stop(action, " is blocked by gate ", g$gate_id, ": rejected by ", g$signer,
         " (", g$reason, ")", call. = FALSE)
  }
  if (!gate_permits(g, scope)) {
    stop(action, " is blocked: gate ", g$gate_id, " is scoped to ",
         paste(g$scope, collapse = ", "), " and does not cover ",
         paste(scope, collapse = ", "), call. = FALSE)
  }
  invisible(g)
}

# ---------------------------------------------------------------------------
# DECISION: the enforcement default is ON, and the opt-out is LOUD
#
# THE REQUIREMENT was "gate absence blocks write_program_artifact()". That is
# now the shipped posture: `AA_GATE_REQUIRED_DEFAULT` is TRUE, so out of the
# box an ungated write is refused and the refusal itself is logged. Writing
# ungated requires an explicit opt-out - the `require_gate = FALSE` ARGUMENT on
# the call (policy source "argument") or
# `options(admiralagent.require_gate = FALSE)` for the session (source
# "option") - and the ungated path remains a supported, loudly
# self-identifying path.
#
# HISTORY, because this flip failed once and the record is what stopped it
# failing twice. The default originally shipped FALSE: the block existed but
# was wired to an option nobody set, which for a regulated control is closer
# to ABSENT than to present. A first flip attempt was budgeted from an
# estimate of three call sites, found at least nine across four test files,
# and was REVERTED. The flip that landed re-derived the definitive site list
# by grep (write_program_artifact / require_gate / admiralagent.require_gate /
# gate_enforced / release_grade / ungated) across tests/, R/ and the docs:
# gate-related references live in SIX test files, not four -
#
#   test-artifacts.R      default-contract test inverted to pin TRUE; ungated
#                         writes moved to the require_gate = FALSE argument;
#                         new test pins that the shipped default blocks an
#                         ungated write and a covering gate unblocks it
#   test-gate.R           ungated helper writes moved to the argument; the
#                         "default policy is off" leg inverted
#   test-manifest.R       an unqualified run now records gate_enforced = TRUE;
#                         option-off and argument-off legs added
#   test-audit-round2.R   the OFF leg now opts out via the option explicitly
#   test-audit-security.R checked: its write_program_artifact() call feeds an
#                         invalid IR, which errors before gate policy resolves;
#                         no change needed
#   test-manifest-auto.R  checked: asserts only is.logical(gate_enforced);
#                         no change needed
#
# THE SECOND-ORDER TRAP that killed attempt #1: reaching the ungated path by
# setting the option changes `gate_policy()$source` from "default" to
# "option", which the provenance assertions in test-artifacts.R pin. The rule
# applied site by site: a site that merely needs an ungated artifact uses the
# ARGUMENT; a site that deliberately tests option-resolution keeps the option
# and asserts accordingly. Provenance is covered for all three sources:
# "default" (now TRUE), "option" and "argument".
#
# WHAT DID NOT CHANGE, because it never depended on the default: an artifact
# written WITHOUT an approval gate is permanently and positively
# self-identifying, so no reader and no auditor can mistake an ungated run for
# a gated one, now or in five years:
#
#   1. the rendered .R carries an UNGATED DRAFT banner. The GATED case already
#      had a header (`gate_header_lines()` in codegen); the ungated case said
#      nothing whatsoever, and the .R file is the artifact that actually
#      circulates;
#   2. the sidecar carries `release_grade` and `gate_enforced`;
#   3. the `write_program` audit record carries the same two fields plus where
#      the policy came from;
#   4. `read_artifact()` reports the grade and refuses a sidecar that labels
#      itself approved while carrying no approval;
#   5. one console notice per session on the first ungated write.
#
# THE PATTERN, NOT THE SYMPTOM. This was the third control in this programme
# that was functionally complete but inert by default; it is no longer inert,
# but the opt-out state must stay loud. The rule adopted here, and the rule to
# apply to the next one:
#
#   A CONTROL THAT IS OFF BY DEFAULT MUST LEAVE ITS OFF STATE IN THE PERSISTENT
#   RECORD, NOT ONLY ON THE CONSOLE, AND MUST REFUSE TO LET AN UNCONTROLLED
#   OUTPUT CARRY A CONTROLLED LABEL.
#
# A console message is for the operator who is already present; the record is
# for the auditor who is not. Only the second one is evidence.
# ---------------------------------------------------------------------------

# The shipped enforcement default. Changing it is NOT a one-line edit: the
# DECISION block above records the six test files that pin the default as
# behaviour and the provenance trap that reverted the first flip attempt.
AA_GATE_REQUIRED_DEFAULT <- TRUE

# Release grade is a LABEL ON AN ARTIFACT, not a policy. It answers one
# question: did a named human approve THIS content? It is "gated" only when a
# covering approval gate is attached, whatever the enforcement policy was - that
# is the "refuse to mark an uncontrolled output as controlled" half of the rule
# above. A run with enforcement off and a gate signed anyway IS approved, and is
# graded accordingly; `gate_enforced` separately records the policy.
AA_GRADE_GATED <- "gated"
AA_GRADE_UNGATED <- "ungated-draft"

artifact_release_grade <- function(gate) {
  if (is.null(gate)) AA_GRADE_UNGATED else AA_GRADE_GATED
}

# The only thing allowed to answer "is this release-grade?", so the answer
# cannot drift between the sidecar, the audit record and the reader.
is_release_grade <- function(grade) identical(grade, AA_GRADE_GATED)

# Resolution AND provenance of the enforcement policy in one place, so the write
# path, the sidecar and `log_run_manifest()` can never disagree about which
# policy applied or where it came from. Precedence: explicit argument, then
# `admiralagent.require_gate`, then the shipped default.
gate_policy <- function(require_gate = NULL) {
  source <- "argument"
  if (is.null(require_gate)) {
    opt <- getOption("admiralagent.require_gate")
    if (is.null(opt)) {
      require_gate <- AA_GATE_REQUIRED_DEFAULT
      source <- "default"
    } else {
      require_gate <- opt
      source <- "option"
    }
  }
  if (!scalar_flag(require_gate)) stop("require_gate must be TRUE or FALSE", call. = FALSE)
  list(enforced = require_gate, source = source)
}

gate_required <- function(require_gate = NULL) gate_policy(require_gate)$enforced

# Loud once per session for the operator who is present. A message() and not a
# warning(): an ungated run is a policy state, not a defect, and overstating it
# as a defect trains people to ignore it. The durable evidence is the banner,
# the sidecar and the audit record, not this line.
gate_notice_env <- new.env(parent = emptyenv())

gate_off_notice <- function(policy) {
  if (isTRUE(gate_notice_env$notified)) return(invisible(FALSE))
  gate_notice_env$notified <- TRUE
  message(
    "admiralagent: approval gating is NOT enforced (policy source: ", policy$source,
    "). This program is being written with NO approval gate, is recorded as '",
    AA_GRADE_UNGATED, "' and is not release-grade. Enforce gating with ",
    "options(admiralagent.require_gate = TRUE) and approve with ",
    "sign_gate(signer = , reason = , scope = gate_scope(ir))."
  )
  invisible(TRUE)
}

# Injected at write time rather than inside `render_program()`, which is
# deliberately pure: the same IR must render byte-identically whoever asks (see
# test-gate.R "an ungated program renders byte-identically"). The grade is a
# property of the WRITE, not of the IR, so this is the correct seam for it.
ungated_banner <- function(code) {
  paste0(paste(c(
    "# ===================================================================",
    paste0("# UNGATED DRAFT - NO APPROVAL GATE. release_grade: ", AA_GRADE_UNGATED),
    "# No named human approved this program. It was generated while",
    "# approval gating was not enforced. Do NOT treat it as reviewed,",
    "# approved or release-grade. The audit log records this run as",
    "# ungated; see read_artifact()$release_grade.",
    "# ==================================================================="
  ), collapse = "\n"), "\n", code)
}

# A refused write leaves a trace: the attempt is logged before the error, so
# "nothing happened" and "an approval was missing" are distinguishable later.
gate_check <- function(gate, scope, action, require_gate, log_file) {
  if (!gate_required(require_gate)) {
    return(if (is.null(gate)) NULL else assert_gate(gate, scope, action))
  }
  if (!gate_permits(gate, scope)) {
    details <- list(action = action, scope = scope)
    id <- tryCatch(as_gate(gate)$gate_id, error = function(e) NULL)
    if (!is.null(id)) details$gate_id <- id
    log_run("gate_blocked", details, file = log_file)
  }
  assert_gate(gate, scope, action)
}

#' Clear `needs_human` on gated variables
#'
#' @description The abstention flag is the "rather abstain than fabricate"
#'   channel, so it is cleared only against an approval gate scoped to the
#'   variables being cleared. Returns a new IR (the input is never mutated) and
#'   logs a `needs_human_cleared` event naming the gate, the signer, the
#'   variables and the artifact hash before and after.
#'
#'   Clearing the flag records that a human took responsibility for the
#'   derivation. It does not make the derivation correct.
#' @param ir List of `aa_variable_ir` objects.
#' @param gate An approval gate from [sign_gate()] covering each cleared
#'   variable (see `gate_scope_variable()`), or `"*"`.
#' @param variables Optional character vector of variable names to clear;
#'   defaults to every variable currently flagged.
#' @param file Audit log destination; defaults to the active log.
#' @return A new IR with `needs_human` set to `FALSE` on the cleared variables.
#' @noRd
gate_clear_needs_human <- function(ir, gate, variables = NULL, file = aa_log_file()) {
  assert_valid_ir(ir)
  names_all <- vapply(ir, function(v) v$variable, character(1))
  flagged <- names_all[vapply(ir, function(v) isTRUE(v$needs_human), logical(1))]
  if (is.null(variables)) {
    variables <- flagged
  } else if (!is.character(variables) || !length(variables) || anyNA(variables)) {
    stop("variables must be a non-empty character vector of variable names", call. = FALSE)
  }
  unflagged <- setdiff(variables, flagged)
  if (length(unflagged)) {
    stop("not flagged for human review: ", paste(unflagged, collapse = ", "),
         "; nothing to clear", call. = FALSE)
  }
  if (!length(variables)) stop("no variable in this IR is flagged for human review", call. = FALSE)

  targets <- names_all %in% variables
  scope <- vapply(ir[targets], gate_scope_variable, character(1))
  g <- assert_gate(gate, scope, "clearing needs_human")

  before <- artifact_hash(ir)
  cleared <- ir
  for (i in which(targets)) cleared[[i]]$needs_human <- FALSE
  assert_valid_ir(cleared)

  dest <- aa_log_file(file)
  if (is.null(dest)) {
    stop("clearing needs_human must be recorded in the audit log, but logging is switched off",
         call. = FALSE)
  }
  log_run("needs_human_cleared", list(
    gate_id = g$gate_id, signer = g$signer, signed_at = g$time, reason = g$reason,
    variables = variables, hash_before = before, hash_after = artifact_hash(cleared)
  ), file = dest)
  cleared
}

#' Recover gate records from an audit log
#'
#' @description Returns the `gate` events of a log in order, so the signer,
#'   timestamp, reason and scope of every approval are recoverable after the
#'   fact. Call [verify_log()] first: this reads the records, it does not
#'   vouch for them.
#' @param file Log file path.
#' @return A list of `aa_gate` objects (possibly empty).
#' @noRd
read_gates <- function(file = aa_log_file()) {
  if (!file.exists(file)) stop("audit log not found: ", file, call. = FALSE)
  lines <- readLines(file, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  out <- list()
  for (line in lines) {
    rec <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(rec) || !identical(rec$event, "gate")) next
    g <- tryCatch(as_gate(rec$details), error = function(e) NULL)
    if (!is.null(g)) out[[length(out) + 1L]] <- g
  }
  out
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

# ---------------------------------------------------------------------------
# Run manifest
#
# WHAT IT IS: the pinned execution environment of one run. The IR says what to
# derive; the manifest says what actually surrounded the derivation - the R
# version, the versions of the packages the rendered code binds against, who
# ran it, a digest of the source data it read, the model parameters behind an
# LLM classification, and whether gating was ENFORCED. `execute_ir()` binds
# `rlang::exprs` and `admiral::params` from whatever happens to be installed
# and degrades to ERROR when they are absent, so without a manifest the same IR
# on two machines produces two different results and nothing says why.
#
# WHERE IT LIVES: it is ONE MORE `log_run()` event on the SAME hash-chained
# audit log, never a parallel record store and never a second log file for one
# run - two chains over one run would diverge and neither would verify. It
# therefore inherits the existing schema, sequence numbers, HMAC mode and
# tamper-evidence unchanged.
#
# WHAT IT NEVER TOUCHES: `aa_variable_ir`. `canonical_ir()` whitelists exactly
# seven fields, so a manifest field on the IR would hash identically to an IR
# without it - a silent collision. Manifest data travels as ARGUMENTS and lands
# in the log record's `details`, exactly as gate data does.
#
# NO PATIENT DATA. The source-data snapshot is a DIGEST plus the shape and the
# column NAMES (schema level, the level `build_context()` is allowed to emit);
# no cell value is ever recorded. Free text such as a prompt is digested in the
# style A13 set for `spec_origin` rather than echoed.
# ---------------------------------------------------------------------------

AA_MANIFEST_SCHEMA <- "admiralagent-manifest-1"

# The packages `seed_exec_env()` binds from the installed library and
# `check_admiral_compat()` checks at render time, but that nobody recorded.
AA_MANIFEST_PACKAGES <- c("admiral", "metatools", "dplyr", "rlang")

# Digest width for free text and for the rolled-up source snapshot, matching
# the width A13 chose for `origin:` digests.
AA_MANIFEST_DIGEST_CHARS <- 16L

installed_version_or_na <- function(pkg) {
  tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NA_character_)
}

# Free text is digested, never echoed: comparable and traceable across runs
# without opening an echo channel into the log.
manifest_text_digest <- function(x, label) {
  if (!scalar_text(x) || !nzchar(x)) return(NA_character_)
  paste0(label, ":", substr(
    digest::digest(x, algo = "xxhash64", serialize = FALSE), 1, AA_MANIFEST_DIGEST_CHARS
  ))
}

# A snapshot DIGEST of the inputs, not the inputs. Shape and column names are
# schema-level and replayable; values are not recorded at any width.
manifest_source_snapshot <- function(sources) {
  if (!is.list(sources) || !length(sources)) return(list())
  nms <- names(sources) %||% rep("", length(sources))
  lapply(seq_along(sources), function(i) {
    x <- sources[[i]]
    df <- is.data.frame(x)
    list(
      source = if (nzchar(nms[[i]])) nms[[i]] else paste0("[[", i, "]]"),
      rows = if (df) nrow(x) else NA_integer_,
      cols = if (df) ncol(x) else NA_integer_,
      columns = if (df) as.list(names(x)) else NULL,
      digest = paste0("xxhash64:", digest::digest(x, algo = "xxhash64"))
    )
  })
}

# One scalar over the whole input set, so two runs are comparable at a glance
# without walking the per-source entries.
manifest_sources_digest <- function(snapshot) {
  if (!length(snapshot)) return(NA_character_)
  joined <- paste(vapply(
    snapshot, function(s) paste0(s$source, "=", s$digest), character(1)
  ), collapse = "|")
  manifest_text_digest(joined, "sources")
}

# Identity is an ARGUMENT first: a regulated run names the human. The session
# user is a fallback, not an authority, so the manifest records WHICH of the
# two it got - an auditor must not read a login name as a signature.
manifest_operator <- function(operator = NULL) {
  if (!is.null(operator)) {
    if (!scalar_text(operator) || !nzchar(trimws(operator))) {
      stop("operator must be one non-empty string naming the human running this",
           call. = FALSE)
    }
    return(list(operator = trimws(operator), operator_source = "declared"))
  }
  opt <- getOption("admiralagent.operator")
  if (scalar_text(opt) && nzchar(trimws(opt))) {
    return(list(operator = trimws(opt), operator_source = "option"))
  }
  env <- Sys.getenv("ADMIRALAGENT_OPERATOR", "")
  if (nzchar(env)) return(list(operator = env, operator_source = "environment"))
  user <- tryCatch(unname(Sys.info()[["user"]]), error = function(e) NA_character_)
  list(
    operator = if (scalar_text(user) && nzchar(user)) user else NA_character_,
    operator_source = "session"
  )
}

manifest_number <- function(x, nm) {
  if (is.null(x)) return(NA_real_)
  if (!is.numeric(x) || length(x) != 1L || is.na(x)) {
    stop(nm, " must be a single number or NULL", call. = FALSE)
  }
  as.numeric(x)
}

#' Record the run manifest of one run
#'
#' @description Appends a `run_manifest` event to the hash-chained audit log
#'   pinning the execution environment of a run: R version and platform, the
#'   admiral/metatools/dplyr/rlang versions actually installed, the
#'   admiralagent version AND whether that version was resolved or guessed, the
#'   operator and where their identity came from, a digest of the source data,
#'   the model parameters, and whether gating was enforced.
#'
#'   It shares `run_id` with the per-variable `execute_variable` records of the
#'   same run, so a manifest and the executions it describes join up.
#'
#'   The manifest is emitted AUTOMATICALLY: `execute_ir()` and `execute_study()`
#'   mint the `run_id` internally and record exactly one `run_manifest` per
#'   call whenever logging is on (see `log_run_manifest_auto()` in R/execute.R).
#'   Calling `log_run_manifest()` by hand for a run that executed through those
#'   entry points therefore DUPLICATES the record. The manual call remains only
#'   for runs that did NOT go through them.
#'
#'   A manifest records the conditions of a run. It asserts nothing about
#'   whether the derivations were correct.
#' @param run_id Run identifier shared with this run's execution records.
#' @param ir Optional IR, recorded as its [artifact_hash()] only.
#' @param sources Optional named list of source datasets, recorded as digests
#'   and shapes. Never as values.
#' @param operator Identity of the human running this. Defaults to
#'   `admiralagent.operator`, then `ADMIRALAGENT_OPERATOR`, then the session
#'   user; the manifest records which.
#' @param backend Classification backend label (`"rules"`, `"llm"`).
#' @param model Model identifier, when a model was involved.
#' @param prompt Prompt text; recorded as a digest, never echoed.
#' @param seed,temperature Model/RNG parameters, or `NULL` when not set.
#' @param gate Optional approval gate whose id is recorded.
#' @param require_gate Whether gating was enforced; `NULL` reads
#'   `getOption("admiralagent.require_gate", TRUE)`, the same resolution the
#'   write path uses, so the manifest states the policy that actually applied.
#' @param file Audit log destination; defaults to the active log.
#' @return Invisibly, the recorded manifest details.
#' @noRd
log_run_manifest <- function(run_id, ir = NULL, sources = list(), operator = NULL,
                             backend = NULL, model = NULL, prompt = NULL,
                             seed = NULL, temperature = NULL, gate = NULL,
                             require_gate = NULL, file = aa_log_file()) {
  if (!scalar_text(run_id) || !nzchar(trimws(run_id))) {
    stop("run_id must be one non-empty string identifying the run", call. = FALSE)
  }
  dest <- aa_log_file(file)
  if (is.null(dest)) {
    stop("a run manifest must be recorded in the audit log, but logging is switched off",
         call. = FALSE)
  }
  ver <- pkg_ver_info()
  who <- manifest_operator(operator)
  snapshot <- manifest_source_snapshot(sources)
  g <- if (is.null(gate)) NULL else as_gate(gate)

  details <- list(
    manifest_schema = AA_MANIFEST_SCHEMA,
    run_id = run_id,
    # --- execution environment ---------------------------------------------
    r_version = R.version.string,
    r_release = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform,
    packages = stats::setNames(
      lapply(AA_MANIFEST_PACKAGES, installed_version_or_na), AA_MANIFEST_PACKAGES
    ),
    package_version = ver$version,
    # loud where it used to be silent: "installed" is a fact, "fallback" is a
    # guess that collapses distinct source trees onto one artifact_hash()
    package_version_source = ver$source,
    package_version_reliable = ver$reliable,
    # --- who ----------------------------------------------------------------
    operator = who$operator,
    operator_source = who$operator_source,
    # --- what went in (digests only) ---------------------------------------
    source_data = snapshot,
    source_data_digest = manifest_sources_digest(snapshot),
    ir_hash = if (is.null(ir)) NA_character_ else artifact_hash(ir),
    # --- model parameters ---------------------------------------------------
    backend = if (scalar_text(backend)) backend else NA_character_,
    model = if (scalar_text(model)) model else NA_character_,
    seed = manifest_number(seed, "seed"),
    temperature = manifest_number(temperature, "temperature"),
    prompt_digest = manifest_text_digest(prompt, "prompt"),
    # --- was gating actually ENFORCED for this run? -------------------------
    # A historical run must be self-identifying as gated or ungated: the
    # policy can be switched off per call or per session, so an absent flag
    # would let an ungated run be mistaken for a gated one.
    gate_enforced = gate_required(require_gate),
    gate_id = if (is.null(g)) NA_character_ else g$gate_id
  )
  log_run("run_manifest", details, file = dest)
  invisible(details)
}

#' Recover run manifests from an audit log
#'
#' @description Returns the `details` of every `run_manifest` record in order.
#'   Call [verify_log()] first: this reads records, it does not vouch for them.
#' @param file Log file path.
#' @param run_id Optional run id to filter on.
#' @return A list of manifest detail lists (possibly empty).
#' @noRd
read_manifests <- function(file = aa_log_file(), run_id = NULL) {
  recs <- read_log_records(file, "run_manifest")
  out <- lapply(recs, function(r) r$details)
  if (is.null(run_id)) return(out)
  Filter(function(d) identical(d$run_id, run_id), out)
}

#' Run ids of the execution records in an audit log
#'
#' @description `execute_ir()` and `execute_study()` mint one `run_id` per call
#'   internally and already record that run's `run_manifest` automatically, so
#'   these ids are read back for INSPECTION - e.g. to filter [read_manifests()]
#'   or the `execute_variable` records of one run - not as a prelude to writing
#'   a manifest. Calling `log_run_manifest()` by hand for a run that executed
#'   through those entry points duplicates its manifest; the manual call is
#'   only for runs that did not go through them. Ids come out in first-seen
#'   order.
#' @param file Log file path.
#' @return A character vector of run ids (possibly empty).
#' @noRd
log_run_ids <- function(file = aa_log_file()) {
  ids <- vapply(
    read_log_records(file, "execute_variable"),
    function(r) if (scalar_text(r$details$run_id)) r$details$run_id else NA_character_,
    character(1)
  )
  unique(ids[!is.na(ids)])
}

# Shared reader for the JSONL log. Deliberately dumb: it parses, it does not
# verify. `verify_log()` remains the only thing that vouches for the chain.
read_log_records <- function(file, event = NULL) {
  if (is.null(file) || !file.exists(file)) stop("audit log not found: ", file, call. = FALSE)
  lines <- readLines(file, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  out <- list()
  for (line in lines) {
    rec <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(rec)) next
    if (!is.null(event) && !identical(rec$event, event)) next
    out[[length(out) + 1L]] <- rec
  }
  out
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
