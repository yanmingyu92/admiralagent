## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE, comment = "#>", error = FALSE
)

## ----setup--------------------------------------------------------------------
library(admiralagent)

## ----classify-----------------------------------------------------------------
spec <- mock_spec_adsl()
ir <- classify_variables(spec, dataset = "ADSL", backend = "rules")

## ----validate-----------------------------------------------------------------
problems <- validate_ir(ir)
length(problems) == 0L

## ----abstain------------------------------------------------------------------
vapply(ir, function(v) isTRUE(v$needs_human), logical(1))

## ----render-------------------------------------------------------------------
prog <- render_program(ir, backend_label = "rules")
cat(strsplit(prog, "\n")[[1]][1:16], sep = "\n")

## ----evals, eval = FALSE------------------------------------------------------
# res <- run_evals(backend = "rules", dataset = "ADSL")
# evals_accuracy(res)  # must stay 1.0

