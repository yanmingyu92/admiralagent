# admiralagent

Spec-driven ADaM code generation with LLM-translated layers.

**Idea**: the LLM never writes R code. It only translates each spec variable's
free-text derivation into a *layer IR* drawn from a closed vocabulary; a
deterministic compiler then emits executable `{admiral}` code with `# CHECK:`
validation comments, plus a provenance sidecar.

```r
# install.packages(c("admiralagent"))          # not yet; dev use: source R/
spec <- mock_spec_adsl()

ir <- classify_variables(spec, "ADSL", backend = "rules")   # zero-dependency baseline
# ir <- classify_variables_llm(spec, "ADSL", chat)           # ellmer upgrade path

validate_ir(ir)                       # schema + semantic gate
cat(render_program(ir))               # executable admiral script + CHECK comments
write_artifact(ir, dir = "gen")       # script + JSON sidecar (model/IR/hash)
```

Generated block example:

```r
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

Design & architecture: see `DESIGN.md`. Development conventions: `AGENTS.md`.
