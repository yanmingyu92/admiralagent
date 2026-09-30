#' @keywords internal
#' @importFrom glue glue
#' @importFrom jsonlite fromJSON
#' @importFrom jsonlite toJSON
#' @importFrom digest digest
#' @importFrom stats setNames
#' @importFrom utils packageVersion
"_PACKAGE"

`%||%` <- function(a, b) if (is.null(a)) b else a

pkg_ver <- function() {
  tryCatch(as.character(utils::packageVersion("admiralagent")), error = function(e) "0.1.0")
}
