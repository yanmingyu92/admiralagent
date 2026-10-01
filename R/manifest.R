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
