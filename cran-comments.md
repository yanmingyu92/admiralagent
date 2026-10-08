## Test environments

- local: Windows 11, R 4.6.0 (ucrt), 64-bit — `R CMD check --as-cran --no-manual`
  (all Suggests installed; `_R_CHECK_FORCE_SUGGESTS_=false` not needed locally)
- GitHub Actions: ubuntu-latest, R release, `r-lib/actions` check-r-package,
  `error-on: "warning"` (R-CMD-check workflow, run on every push to main)
- win-builder: to be run at submission time (r-devel, r-release, r-oldrelease)

## R CMD check results (local, 0.1.0)

0 errors | 0 warnings | 1 NOTE

- New submission (first CRAN release).
- win-builder first round flagged 2 vignette WARNINGs caused by
  prebuilt-vignette omission in the uploaded tarball; fixed by building
  with pandoc available and by converting the three pkgdown-style
  articles in `vignettes/articles/` to plain Rmd (vignette headers
  removed — they are rendered as pkgdown articles, not R vignettes).
  Local re-check after the fix: 0 errors, 0 warnings, 1 NOTE.
- "Possibly misspelled words in DESCRIPTION: ADaM" (if flagged on
  win-builder) is the CDISC Analysis Data Model acronym, used
  deliberately throughout clinical reporting.

## Reverse dependencies

None (first release; confirmed via `tools::package_dependencies(reverse=TRUE)`
at submission time).

## Comments for the CRAN team

- The optional LLM path (`backend = "llm"`, via Suggests 'ellmer') is
  never exercised in examples, tests, or vignettes: all model calls
  require an explicit API key from the interactive user, and the test
  suite (4911 assertions) runs fully offline with
  `Sys.setenv(NOT_CRAN=true)` guards where needed. R CMD check performs
  no network access.
- Generated-code disclaimer: functions whose output is user-facing R
  code emit a DISCLAIMER header and `# CHECK:` validation comments by
  design; this is functional behavior, not leftover development
  scaffolding.
- Package names 'admiral' and 'metatools' appear in the Description as
  the target code-generation frameworks; 'ellmer', 'jsonlite' et al.
  quoted per policy.
