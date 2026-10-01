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

