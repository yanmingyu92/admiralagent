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
