#!/usr/bin/env Rscript
file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(file_arg) > 0L) {
  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = FALSE)
} else {
  ""
}
pkg_root <- if (nzchar(script_path)) dirname(dirname(script_path)) else ""

if (nzchar(pkg_root) && file.exists(file.path(pkg_root, "R", "mcp.R"))) {
  for (f in list.files(file.path(pkg_root, "R"), pattern = "[.]R$", full.names = TRUE)) {
    source(f, local = globalenv(), encoding = "UTF-8")
  }
  setwd(pkg_root)
  mcp_serve()
} else if (requireNamespace("admiralagent", quietly = TRUE)) {
  serve <- tryCatch(
    utils::getFromNamespace("mcp_serve", "admiralagent"),
    error = function(e) NULL
  )
  if (is.null(serve)) {
    stop(
      "admiralagent is installed but does not provide mcp_serve(); ",
      "reinstall the package from a source tree that includes R/mcp.R",
      call. = FALSE
    )
  }
  serve()
} else {
  stop(
    "could not load admiralagent: install the package, or run this script ",
    "from the package source tree via `Rscript tools/mcp_server.R`",
    call. = FALSE
  )
}
