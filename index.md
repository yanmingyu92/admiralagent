# admiralagent

[![R-CMD-check](https://github.com/yanmingyu92/admiralagent/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/yanmingyu92/admiralagent/actions/workflows/R-CMD-check.yaml)
[![testthat](https://github.com/yanmingyu92/admiralagent/actions/workflows/testthat.yaml/badge.svg)](https://github.com/yanmingyu92/admiralagent/actions/workflows/testthat.yaml)

Spec-driven ADaM code generation with LLM-translated layers.

**Idea**: the LLM never writes R code. It only translates each spec
variable’s free-text derivation into a *layer IR* drawn from a closed
vocabulary; a deterministic compiler then emits executable
[admiral](https://pharmaverse.github.io/admiral/) code with `# CHECK:`
validation comments, plus a provenance sidecar.

``` r

# install.packages("pak"); pak::pak("yanmingyu92/admiralagent")   # GitHub
spec <- mock_spec_adsl()

ir <- classify_variables(spec, "ADSL", backend = "rules")   # zero-dependency baseline
# ir <- classify_variables_llm(spec, "ADSL", chat)           # ellmer upgrade path

validate_ir(ir)                       # schema + semantic gate
cat(render_program(ir))               # executable admiral script + CHECK comments
write_artifact(ir, dir = "gen")       # script + JSON sidecar (model/IR/hash)
```

Generated block example:

``` r

# ---- TRTSDTM | step 2/2: impute_dtc ----------------------------------
# Spec origin: "Earliest EXSTDC among EX records with EXDOSE > 0, impute to first"
# CHECK: TRTSDTF flag exists; NA only when year component missing
adsl <- adsl |>
  admiral::derive_vars_dtm(
    new_vars_dtm = exprs(TRTSDTM),
    dtc = EXSTDTC,
    highest_imputation = "M",
    date_imputation = "first"
  )
```

Executing an IR is self-auditing:
[`execute_ir()`](https://yanmingyu92.github.io/admiralagent/reference/execute_ir.md)
writes a hash-chained audit log with one record per variable plus one
`run_manifest` per run, automatically — no manual manifest step. The
artifact that is validated, approved and archived is the IR itself; the
LLM never writes R code.

Design & architecture: see `DESIGN.md`. Development conventions:
`AGENTS.md`.
