#' @keywords internal
#' @importFrom glue glue
#' @importFrom jsonlite fromJSON
#' @importFrom jsonlite toJSON
#' @importFrom digest digest
#' @importFrom stats setNames
#' @importFrom utils packageVersion
"_PACKAGE"

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------------------
# Package version: provenance, not identity
#
# `pkg_ver()` is recorded as METADATA (sidecars, run manifests, generated-code
# headers, MCP serverInfo) but is NOT an input to `artifact_hash()`: the hash
# covers `canonical_ir(ir)` only, so a Version bump in DESCRIPTION never
# silently renames artifacts or moves pinned golden hashes (DESIGN.md §11.3
# item 3, resolved in v0.1.0+).
#
# What remains important is not the value but its PROVENANCE. When
# admiralagent is not installed - a sourced source tree, a
# `devtools::load_all()` session - the version is GUESSED from the fallback.
# Two mechanisms keep that honest:
#   1. `pkg_ver_info()` reports where the version came from, and the run
#      manifest records it as `package_version_source`, so a historical run is
#      self-identifying as "version known" or "version guessed";
#   2. `options(admiralagent.strict_package_version = TRUE)` turns the guess
#      into a hard error, for a regulated run that must not record one.
# ---------------------------------------------------------------------------

PKG_VER_FALLBACK <- "0.1.0"

installed_pkg_version <- function() {
  tryCatch(as.character(utils::packageVersion("admiralagent")), error = function(e) NULL)
}

#' Resolve the package version together with its provenance
#'
#' @param installed Version string of the installed package, or `NULL` when it
#'   is not installed. Injected so the fallback path is reachable in tests.
#' @return List with `version`, `source` (`"installed"` or `"fallback"`) and
#'   `reliable`.
#' @noRd
pkg_ver_info <- function(installed = installed_pkg_version()) {
  if (!is.null(installed)) {
    return(list(version = installed, source = "installed", reliable = TRUE))
  }
  if (isTRUE(getOption("admiralagent.strict_package_version", FALSE))) {
    stop(
      "admiralagent is not installed, so its version cannot be resolved; ",
      "artifact_hash() would hash against the fallback '", PKG_VER_FALLBACK,
      "', which collapses distinct source trees onto one hash. Install the ",
      "package, or unset options(admiralagent.strict_package_version) to ",
      "accept the fallback (the run manifest then records it as a guess).",
      call. = FALSE
    )
  }
  list(version = PKG_VER_FALLBACK, source = "fallback", reliable = FALSE)
}

pkg_ver <- function() pkg_ver_info()$version
