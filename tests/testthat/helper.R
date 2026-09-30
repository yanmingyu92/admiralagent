# Two test modes:
#
# - ADMIRALAGENT_DEV_SOURCE=1 (development, via testthat::test_dir() on the
#   source tree): source R/*.R into the test environment so tests exercise the
#   working copy, including unexported functions.
# - Otherwise (test_check() under R CMD check): source nothing. testthat runs
#   the tests in a clone of the installed package namespace, so exported and
#   internal functions already resolve against the installed package.
if (identical(Sys.getenv("ADMIRALAGENT_DEV_SOURCE"), "1")) {
  for (f in list.files(file.path("..", "..", "R"), pattern = "[.]R$", full.names = TRUE)) {
    source(f, local = environment())
  }
}
