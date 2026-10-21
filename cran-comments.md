## Test environments

- local: Windows 11, R 4.6.0 (ucrt), 64-bit — `R CMD check --as-cran
  --no-manual` with pandoc available: **0 errors | 0 warnings | 1 NOTE**
  (the NOTE is "New submission" only)
- GitHub Actions: ubuntu-latest, R release, `r-lib/actions` check-r-package,
  `error-on: "warning"` (R-CMD-check workflow, run on every push to main)
- win-builder: to be run at submission time (r-devel, r-release, r-oldrelease)

## R CMD check results (local, 0.1.1)

0 errors | 0 warnings | 1 NOTE

- New submission (first CRAN release).

## Response to the first review (Leonore Hochhauser, 2026-10)

1. **Explain all acronyms in the description.** Done: ADaM (Analysis Data
   Model), LLM (large language model), IR (intermediate representation),
   P21 (Pinnacle 21) and CDISC (Clinical Data Interchange Standards
   Consortium) are all expanded on first use in the Description field.

2. **References for the methods.** The specification structure this package
   parses follows the CDISC Analysis Data Model standard; the Description
   now links it in the requested form:
   <https://www.cdisc.org/standards/foundational/adam>. The package's own
   translation method (closed-vocabulary layer IR) is original and has no
   publication, so no further reference is claimed.

3. **Examples for unexported functions.** The example block was removed
   from the unexported `parse_define()` (its Rd now documents arguments and
   behaviour without examples).

4. **`\dontrun{}` usage.** Rewritten. Every example that can execute in
   under 5 seconds now runs (examples write only to `tempdir()`, e.g. by
   round-tripping a minimal define.xml / Dataset-JSON file). `\dontrun{}`
   remains only where execution is genuinely impossible for the user, with
   the reason stated in a comment: an LLM provider API key
   (`classify_variables_llm()`, `classify_variables_dual()`,
   `accept_model()`, `mock_metacore()` needs the optional 'metacore'
   package, `read_spec()` needs an external workbook plus
   'metacore'/'readxl'), or a blocking stdio server loop (`mcp_serve()`).

5. **Executable examples for exported functions.** Every exported function
   (and the exported S3 print method) now carries a small executable
   example; all 41 Rd example blocks were run locally with zero failures.

6. **Writing to the user's home filespace.** `write_artifact()` and
   `write_program_artifact()` no longer have a default `dir` argument: an
   explicit output directory is required, so no exported function writes
   anywhere by default. All examples and vignettes write only to
   `tempdir()` (the vignette performs no file writes in its chunks).

7. **Modifying the global environment.** The three closure-internal `<<-`
   assignments (an accumulator in `step_refs()`, a walker accumulator in
   `predicate_names()`, a node counter in the MCP ingress bound) were
   rewritten over explicit local environments. No function assigns to the
   global environment; the full test suite (4911+ assertions) passes
   unchanged.

## Reverse dependencies

None (first release; confirmed via `tools::package_dependencies(reverse=TRUE)`
at submission time).

## Comments for the CRAN team

- The optional LLM path (`backend = "llm"`, via Suggests 'ellmer') is
  never exercised in examples, tests, or vignettes: all model calls
  require an explicit API key from the interactive user, and the test
  suite runs fully offline with `Sys.setenv(NOT_CRAN=true)` guards where
  needed. R CMD check performs no network access.
- Generated-code disclaimer: functions whose output is user-facing R
  code emit a DISCLAIMER header and `# CHECK:` validation comments by
  design; this is functional behaviour, not leftover development
  scaffolding.
- Package names 'admiral' and 'metatools' appear in the Description as
  the target code-generation frameworks; 'ellmer', 'jsonlite' et al.
  quoted per policy.
