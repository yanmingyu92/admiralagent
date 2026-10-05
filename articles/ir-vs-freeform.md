# Constrained IR vs Free-Form Code Generation

> **Question:** is constraining the LLM to a closed IR vocabulary worth
> anything, versus letting the same model — with the same inputs and a
> skill-quality prompt — simply write the
> [admiral](https://pharmaverse.github.io/admiral/) code itself?

This article is the narrative version of `demo/automation/REPORT.md` §11
and `demo/automation/out/compare_summary.json` in the [package
repository](https://github.com/yanmingyu92/admiralagent). Every number
below is transcribed from machine-readable files under
`demo/automation/out/` (named per section). The comparison is explicitly
against **free-form code generation as a translation strategy** — *not*
against skills or MCP as distribution channels (admiralagent itself
ships an MCP server and a `SKILL.md`).

> **Honesty boundaries (read before quoting any number here; repeated in
> the last section).** Single model (`deepseek-chat`), single study
> (pilot5 ADSL, 49 spec variables), single run per arm — run-to-run LLM
> variance is documented in `REPORT.md` limitation 8. Arm A numbers come
> from the cached 2026-10-01 run; arm B is a fresh run. Oracle agreement
> is not double programming (DESIGN.md §11.1). Review burden is a
> mechanical proxy, not measured human effort. Spec-ambiguity
> disagreements (findings F-04/F-09) are not scored as errors for either
> arm. Arm B’s static sandbox gate is an experiment scaffold, not a
> package feature. Variables an arm did not derive are scored
> `not_produced` even though the DM seed every arm starts from already
> carries the column (verified a no-op for arm A: its 20 compared
> variables are all EXECUTED).

## Design and fairness

Design doc: `.agents/freeform-comparison-design.md`. Same spec (ADSL, 49
variables), same model (`deepseek-chat`), same oracle (the submitted
`original-adamdata/adsl.xpt`), same schema-level inputs for both arms —
[`build_context()`](https://yanmingyu92.github.io/admiralagent/reference/build_context.md)
JSON + SDTM column schemas + workbook codelists; **no patient data
appears in either arm’s prompts**.

- **Arm A (constrained IR).** The LLM only translates spec free text
  into the closed-vocabulary Layer IR (JSON); a deterministic compiler
  renders the [admiral](https://pharmaverse.github.io/admiral/) code;
  [`validate_ir()`](https://yanmingyu92.github.io/admiralagent/reference/validate_ir.md)
  is a fail-closed gate. Numbers read from the cached run’s evidence
  files (`out/accuracy_llm.csv`, `out/exec_status_llm.csv`,
  `out/gate_report.json`, `out/llm_telemetry.json`), cache date
  2026-10-01, zero new LLM spend.
- **Arm B (free-form, CONTROL ARM).** The LLM writes executable R
  directly. Its prompt was written to the standard of a careful skill
  author: the same
  [`build_context()`](https://yanmingyu92.github.io/admiralagent/reference/build_context.md)
  JSON, SDTM column schemas, and workbook codelists, plus concrete
  guidance on the admiral API. Generated code is sandboxed (a static
  gate before execution, a separate R process, `tryCatch` + time limit),
  lives only in `demo/automation/freeform/` — each file banner-marked
  `CONTROL ARM - free-form generation experiment. NOT package output. Do not ship.`
  — and never enters the package or any release surface. Evidence:
  `out/compare_freeform_gen.csv`, `out/compare_exec_status.csv`,
  `out/compare_accuracy_freeform.csv`,
  `out/compare_freeform_telemetry.json`.

## The headline table

Transcribed from `out/compare_summary.json` and `REPORT.md` §11:

| metric | constrained IR (A) | free-form (B) |
|----|----|----|
| abstained (needs_human / ABSTAIN+blocked+parse_fail) | 25 | 0 |
| executed (coverage) | 21 | 28 |
| execution errors | 3 | 21 |
| oracle: compared | 20 | 26 |
| oracle: full match (100%) | 16 | 22 |
| oracle: mean value agreement | 91.4% | 90.9% |
| **silent errors** (wrong answer, nothing flagged) | 4 | 4 |
| fail-closed intercepts (abstain + validation FAIL + exec ERROR) | 31 | 21 |
| review burden proxy: total LOC (variables with code) | 233 (24) | 1067 (49) |
| review burden proxy: bare logic points | 56 | 561 |
| LLM cost (USD) | \$0.0114 | \$0.0139 |

Metric definitions are machine-readable under
`compare_summary.json$definitions`. A *silent error* is: executed,
**nothing flagged the variable** (arm A: validation PASS; arm B: no
warning captured), oracle compared, value agreement \< 100%. Arm B
executed with warnings: 0 — sandbox-captured warnings are “loud” and
excluded from silent errors by definition.

## Who wins what

Stated plainly: **free-form wins coverage.** It executed 28 variables to
arm A’s 21, compared 26 against the oracle to arm A’s 20, and produced
22 full matches to arm A’s 16. Mean value agreement on compared
variables is a wash (91.4% vs 90.9%). Arm A abstained on 25 of 49
variables; arm B abstained on none and generated code for 49/49.

None of that is the axis that matters in a GxP context. The axes that
matter are what happens when the model is **wrong** — is the failure
loud, abstained, or silent — and what a reviewer has to read. The next
three sections are those axes.

## The silent-error anatomy

Both arms produced exactly 4 silent errors. Same count, fundamentally
different composition.

**Arm A’s four** (`out/compare_summary.json$silent_error_detail`,
`out/accuracy_llm.csv`):

| variable | value agreement | at oracle precision |
|----------|-----------------|---------------------|
| BMIBL    | 99.6%           | —                   |
| BMIBLGR1 | 99.2%           | —                   |
| HEIGHTBL | 19.7%           | 98.8%               |
| WEIGHTBL | 8.7%            | 94.5%               |

All four are the documented **F-05 family** (`out/findings.json`): the
oracle stores 1-decimal rounded values and the spec text never mentions
rounding. HEIGHTBL/WEIGHTBL trace to the same VS records the spec names
and agree at 98.8%/94.5% at the oracle’s own storage precision (the
residual is round-half edge cases); the two BMI variables inherit the
rounding. The derivations are semantically correct; the “silence” is an
oracle convention nobody wrote down.

**Arm B’s four** (`out/compare_summary.json`,
`out/compare_accuracy_freeform.csv`):

| variable | value agreement | arm A’s disposition of the same variable |
|----|----|----|
| VISNUMEN | 0.0% | abstained |
| DCSREAS | 55.5% | abstained |
| SITEGR1 | 87.8% | abstained |
| HEIGHTBL | 19.7% (98.8% at oracle precision) | also silent (same F-05 rounding) |

The contrast cases, verified variable by variable against arm A’s
abstention rationales (`REPORT.md` §8) and arm B’s accuracy rows
(`out/compare_accuracy_freeform.csv`):

- **VISNUMEN.** Arm A abstained: the derivation needs a DS-conditioned
  existence/windowing check (`DS.VISITNUM` with a conditional `13 -> 12`
  remap and a `DSTERM = 'PROTOCOL COMPLETED'` filter) that no layer
  expresses — a genuine vocabulary hole. Arm B silently emitted a flag
  that agrees with the oracle on **0.0% of the 254 joined subjects**
  (`na_agree=0.00`). Nothing warned. It executed, it looked plausible,
  and it was wrong on every single subject.
- **DCSREAS.** Arm A abstained: the derivation is a grouping of DCDECOD
  values requiring an external mapping table the spec does not provide.
  Arm B invented a grouping and silently produced 55.5% agreement.
- **SITEGR1.** Arm A abstained: the pooling rule defers to SAP §7.1 and
  an external pooling specification — not encodable from spec text
  alone. Arm B guessed a pooling and silently produced 87.8% agreement —
  the most dangerous of the four, because 87.8% looks nearly right.

Three of arm B’s four silent errors are variables where the constrained
arm said, out loud and with a stated rationale, “a human must decide
this.” One wrong-but-plausible number in a submission is exactly the
failure mode double programming exists to catch. That is the
experiment’s core finding (registered as F-12 in `out/findings.json`):
the silent-error **counts** are equal (4 vs 4 — the coverage/credibility
hypothesis predicted a gap here and was wrong on count); the
**composition** is not — rounding conventions nobody documented on one
side, genuinely invented semantics on the other.

## Loud failures, and the API-drift story

21 of arm B’s 49 variables — 43% — errored at execution
(`out/compare_exec_status.csv`). Loud errors are the **good** outcome:
they fail closed, someone looks at them, nobody ships them. The
interesting part is *why* they failed.

Seven of the 21 trace to a single repeated cause: the model wrote
admiral’s deprecated `vars()` where admiral 1.5 requires `exprs()` —
every one failing with the same message:

    Each element of the list in argument `by_vars` must be class/type <symbol>.
    ℹ But, element 1 is a <quosure> object

(TRTSDT, TRTEDT, ETHNIC, COMP16FL, WEIGHTBL, EDUCLVL, VISIT1DT —
`out/compare_exec_status.csv`.) Most of the rest are
`mutate()`/`case_when()` errors cascading from missing upstream columns
(`object 'TRTSDT' not found`, `object 'DCREASCD' not found`, …).

This is stale training knowledge arriving in production code, and it is
structural, not incidental. admiralagent’s own `AGENTS.md` history note
says it in the context of the IR architecture: admiral major versions
rename arguments (1.5 renamed `new_vars_prefix` and changed formulas
inside `set_values_to`) — and when that happens, the constrained arm
absorbs it by **editing one template in `R/layers.R` without touching
the IR**. The IR has no admiral API surface at all; API drift is a
one-file template change, insulated by construction. Free-form code
carries the model’s stale training knowledge into every file it writes,
one variable at a time.

One honest footnote on the sandbox: arm B’s static gate fired once in 49
variables, and the single firing was a **false positive** — the pattern
`source[ ]*[(]` matched a prose comment (`source (DM.SITEID)`), not code
(SITEID, `attempts = 2`, `out/compare_freeform_gen.csv`). Recorded as
F-13, because the gate is part of the experiment’s safety story and its
record should be stated as measured.

## The audit-chain difference

Arm A’s artifacts carry provenance by construction. Every rendered
variable is accompanied by a sidecar JSON (`out/artifacts/llm/`)
recording the IR, the model, `ir_hash`, `code_digest`, `release_grade`,
and `gate_enforced`; every rendered program carries mandated CHECK
comments and the spec-origin/rationale provenance from the IR. Execution
appends to a hash-chained audit log (`out/execute_llm.jsonl`), one
record per event, schema `admiralagent-audit-1`, each record carrying
`prev` and `digest` — the first record chains from 64 zeroes, `sha256`
mode.

Arm B’s artifacts are prose code with comments. There is nothing wrong
with prose code as code — but a reviewer must reconstruct intent, spec
origin, and correctness from the text alone. The mechanical
review-burden proxy in the headline table (non-blank LOC / comment lines
/ bare logic points of generated code; arm A’s LOC includes the mandated
CHECK comments and DISCLAIMER header) puts that at 1067 LOC / 561 bare
logic points over 49 coded variables for arm B, vs 233 LOC / 56 bare
logic points over 24 for arm A (`compare_summary.json`,
`out/compare_review_burden.csv`). The proxy caveat stands — this is not
measured human review effort — but the direction is not ambiguous.

## Honesty boundaries (summary)

Everything in the box at the top, restated because it bounds every
number in this article:

- Single model (`deepseek-chat`), single study (pilot5 ADSL), single run
  per arm. Arm A from the 2026-10-01 cache, arm B fresh; run-to-run
  variance is documented (`REPORT.md` limitation 8). Do not generalize
  these numbers to other models, studies, or runs.
- Oracle agreement is not double programming (DESIGN.md §11.1) — one
  produced dataset compared against one submitted oracle.
- Review burden is a mechanical proxy.
- Spec-ambiguity disagreements (F-04/F-09) are not scored as errors for
  either arm.
- Arm B’s static sandbox gate is an experiment scaffold, not a package
  feature.
- Scoring gate: variables an arm did not derive are scored
  `not_produced` even though the DM seed carries the column (verified a
  no-op for arm A: its 20 compared variables are all EXECUTED).

## Reproduce

Three staged scripts extend the automation pipeline
(`demo/automation/`):

``` sh
Rscript demo/automation/06_freeform_generate.R   # arm B generation (spends on DeepSeek)
Rscript demo/automation/07_freeform_execute.R    # arm B sandboxed execution
Rscript demo/automation/08_compare.R             # writes out/compare_summary.json
```

Stage 06 pilots a subset with `AA_FREEFORM_VARS="AGE,TRTSDT,..."` and
stops at a budget breaker (`AA_FREEFORM_BUDGET`, default **\$0.50**);
`AA_FREEFORM_FORCE=1` regenerates existing files. A `DEEPSEEK_API_KEY`
is needed for stage 06 only. Full evidence trail:
`demo/automation/REPORT.md` §11,
`demo/automation/out/compare_summary.json`, and the CONTROL ARM code
under `demo/automation/freeform/` — marked, per file, “CONTROL ARM — not
package output”.
