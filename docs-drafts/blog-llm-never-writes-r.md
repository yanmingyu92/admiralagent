# LLM Never Writes R Code: What Happened When We Fed a Real CDISC Submission to admiralagent

*Draft for R-bloggers / Posit Blog guest post. Every number below comes from a
one-command, re-runnable pipeline (`Rscript demo/automation/run_all.R`) against
the public CDISC pilot 5 data; the evidence trail is `demo/automation/REPORT.md`
plus machine-readable files under `demo/automation/out/` in the repo — cited per
section below (`out/gate_report.json`, `out/accuracy_summary.json`,
`out/llm_telemetry.json`, `out/findings.json`).*

---

There is a genre of demo where an LLM "writes the analysis code" and everyone
applauds. In regulated clinical programming that genre is a dead end: code an
LLM emits is code a human must review line by line, because the failure mode
is not "it doesn't run" — it's "it runs and is silently wrong."

[admiralagent](https://github.com/yanmingyu92/admiralagent) takes a different
bet: **the LLM never writes R code.** It does exactly one job — translating
each spec variable's free-text derivation into a *Layer IR*, a JSON object
drawn from a closed vocabulary of derivation layers (`assign`, `merge_var`,
`impute_dtc`, `categorize`, `compute_param`, …). A deterministic compiler
renders that IR into `{admiral}` code with `# CHECK:` validation comments. A
schema+semantic gate (`validate_ir()`) rejects anything outside the
vocabulary, fail-closed: no guessing, no repair. What gets validated,
approved, hashed and archived is the IR — not prose, not code.

That's the architecture claim. This post is about what happened when we
stopped asserting it and measured it — and then kept measuring, because the
measurement loop started finding real bugs.

## The experiment: real data, real spec, one command

We pointed the pipeline at the **CDISC pilot 5 submission**: the real
P21-style ADaM define workbook (`adam-pilot-5.xlsx`), the original SDTM `.xpt`
files as execution inputs, and the submitted `adsl.xpt` / `adae.xpt` /
`adlbc.xpt` as accuracy oracles. What started as a single-dataset (ADSL)
showcase now covers **three datasets from the same submission**: ADSL (49
spec variables), ADAE (55), ADLBC (46) — source: `out/ingest_manifest.json`.
Six staged scripts — ingest, classify, gate+render, execute, oracle-compare,
report — run end-to-end from one command and are fully re-runnable.

We classified the same specs twice: a zero-dependency **rules backend**
(keyword baseline) and **DeepSeek** (`deepseek-chat`, via `{ellmer}`). A
deterministic 12-variable subset per dataset additionally ran 3 samples with
majority vote.

## The numbers

Accuracy is computed against the submitted oracle on joined records only
(dates exact, numerics within 1e-6, characters exact). Two caveats travel
with every figure below: the produced datasets are built from the full SDTM
base domain with **no population subsetting** (produced ADSL has 306 rows vs
the oracle's 254 randomized subjects; produced ADLBC has 59,580 rows vs
37,132), and agreement here is a self-comparison against one oracle — **not
double programming**. Source: `out/accuracy_<backend>[_<ds>].csv`,
`out/accuracy_summary.json`.

| dataset | backend | spec vars | abstained (`needs_human`) | executed | oracle: compared | oracle: full match | mean agreement |
|---|---|---|---|---|---|---|---|
| ADSL | rules | 49 | 32 | 16 | 15 | **15 (100%)** | 100.0% |
| ADSL | DeepSeek | 49 | 25 | 21 | 20 | **16** | 91.4% |
| ADAE | rules | 55 | 16 | 27 | 20 | **20 (100%)** | 100.0% |
| ADAE | DeepSeek | 55 | 6 | 33 | 27 | **25** | 96.3% |
| ADLBC | rules | 46 | 14 | 15 | 14 | **12** | 85.8% |
| ADLBC | DeepSeek | 46 | 15 | 19 | 19 | **19** | **100.0%** |

- The rules baseline abstains on two-thirds of the ADSL spec — but everything
  it did derive matched the oracle exactly where it produced values at all
  (ADSL 15/15, ADAE 20/20; ADLBC's 85.8% is dominated by a spec-text defect,
  see below).
- DeepSeek automated more on ADSL and ADAE (ADAE: 33 executed vs the rules
  backend's 27, with only 6 abstentions out of 55). On ADLBC this run its
  coverage moved *down* (19 executed vs 22 last run) while accuracy moved up
  to **19/19 full match** — run-to-run translation variance, not a regression
  (limitation 8); among other things the model this run refused to execute
  the spec's literally-broken BASE derivation (see F-09 below).
- Rules-vs-LLM layer chains agreed on 80% (ADSL), 58% (ADAE) and 52% (ADLBC)
  of variables — translation consistency between two readers of the same
  text, explicitly *not* a correctness claim. The 3-sample consensus vote was
  unanimous on 12/12 variables on each dataset's subset; measured against the
  oracle, the consensus backend compares at 15/15 (100%) on ADSL, 26/26
  (100%) on ADAE and 12/14 (85.8%) on ADLBC (`out/accuracy_summary.json`;
  the consensus comparison spans the full spec with the subset's voted
  choices applied, so its denominators differ from the 12-variable funnel by
  design).
- Marginal cost of the LLM: a single full-spec dataset is **91–126 seconds
  and $0.010–0.013**; the measured run behind this post re-spent on
  everything (three full-spec runs + three consensus runs) for **≈ $0.053
  total** (rate assumption recorded in the repo; the rules baseline runs in
  ~0.1s for free). Source: `out/llm_telemetry.json`.

But the headline column is still the abstention column, not the accuracy
column.

## The boundary is the story

DeepSeek declined 25 of 49 ADSL variables — and the inventory is not random.
It is the vocabulary boundary, stated out loud, and it repeats with different
accents on the other datasets:

- **Record-existence and windowing logic is still inexpressible** — ADSL's
  COMP8/16/24FL visit-window flags, EFFFL (cross-dataset existence over QS),
  VISNUMEN. These remain genuine vocabulary holes.
- **Missingness checks are inexpressible** — SAFFL (`Y` if TRTSDT
  non-missing) abstains because the filter sublanguage has no `is.na()`.
- **External references** (SAP sections, unstated codelists) are abstained
  on: SITEGR1, DCSREAS, TRT01PN, ADLBC's PARAMN.
- **Missing vocabulary, honestly reported**: ADLBC's PARAM needs string
  concatenation ("LBTEST (LBSTRESU)") and abstains because the vocabulary has
  no function calls; its ALBTRVAL needs `max()` over arithmetic expressions
  and abstains for the same reason.
- **Multi-branch clinical logic** (CUMDOSE's arm-conditional dosing
  intervals) is abstained on.

A system that hallucinated these would be strictly worse than one that
abstains. In a GxP narrative, "the machine said *I don't know*, with a stated
reason each time" is a feature you can defend in an audit.

## We added a conditional layer. One variable landed.

The most recent change to the vocabulary was its 15th layer,
`assign_conditional` — a guarded `Y if <condition> else <N>` assignment, the
single most common abstention family in the runs above. The evaluation note
predicted it would confidently convert 4 of the 9 conditional-family
variables (ITTFL directly; EOSSTT, DISCONFL, DSRAEFL via a shared upstream
chain). We then forced a full re-measurement and registered what actually
happened as finding F-11:

- **ITTFL converted, executed, and matched the oracle at 100%.** The layer
  works.
- **EOSSTT converted but failed closed at execution**: its IR conditions on
  DCDECOD, which the LLM happened to abstain on in this run — so the chain
  broke at a stochastic upstream, exactly as the transactional guard is
  designed to break it (last run, DCDECOD was derived at 100% agreement).
- **DISCONFL and DSRAEFL never converted.** The 4/9 prediction was
  over-optimistic given run-to-run variance, and the findings register says
  so in those words.

So: 2 of 9 converted, 1 of 9 landed end-to-end. We considered not leading
with this, and decided it is the most useful paragraph in the post. A new
layer changes what is *expressible*; it does not change what any single
stochastic run *chooses* — which is precisely why the consensus-voting mode
and the findings register exist. (The rules backend deliberately ignores the
new layer: the evals corpus pins its abstention as contract. A zero-cost
baseline staying put is a feature of the regression suite, not an oversight.)

## The showcase audits itself: probe, finding, fix, regression

The least expected outcome of expanding from ADSL to three datasets is that
the pipeline started catching its own bugs — and the findings register
(`out/findings.json`, F-01 through F-11) documents a working improvement
loop, not a one-shot demo. Four resolved findings are worth the space:

**F-01 — the fail-closed line moved forward.** An LLM-generated IR for ADSL's
TRTSDT merged `SVSTDTC` into a new column `TRTSDT`, then tried to impute from
`SVSTDTC` — which no longer existed under that name after the merge. The old
semantic gate passed it; execution failed. The fail-closed execution layer
caught it (transactional rollback, downstream variables refused stale
inputs), but the right place to catch it was the gate. `validate_ir()` now
tracks merge renames across steps and rejects the same class of IR **inside
the gate, naming the new column in the error message** — with regression
tests pinning the behavior. Architecturally this is the story of the whole
package in miniature: a defense that used to live at execution time moved
forward into the semantic gate, closer to where the mistake is made.

**F-02 — codelists became executable.** DeepSeek chose the `codelist_var`
layer for codelist-backed variables (RACEN, TRT01PN, TRT01AN), but the
showcase had never built a metacore object, so those IRs errored at
execution. The pipeline now converts the submission workbook's own
`Codelists` sheet into one executable metacore per dataset
(`out/mc_<ds>.rds`), and a direct probe confirms hand-built `codelist_var`
IRs execute and match the oracle on 100% of the 254 joined subjects.
Honesty footnote: the *cached* LLM run still abstains on those variables
(run-to-run variance, limitation 8) — the fix is verified by probe and ready
for any IR that selects the layer.

**F-06 — one missing context field silently degraded a whole dataset.** The
classification context never told the model which dataset it was translating
for, and the only example in the system prompt said `"dataset":"ADSL"`. For
ADAE variables whose derivation text reads "ADSL.TRT01A", the model dutifully
echoed `ADSL`, the alignment check rejected entire batches, and 14 ADAE
variables fell back to abstention. A one-line fix — put the spec's dataset
column into every variable's payload — took ADAE's `needs_human` from 21 to
8 and failed batches from 4 to 0 (ADLBC: 46 to 25, 16 to 0). Full test suite:
4,815 passing.

**F-10 — fixing F-06 exposed the next layer down.** With the dataset token
fixed, the model followed the rule "to bring a value from another dataset,
always merge" too literally: it merged AE into ADAE — whose base *is* AE —
producing duplicate by-keys and 25 fail-closed `duplicate_records` errors.
The fix landed at the prompt layer (vocabulary untouched): a new hard rule
states that a column from the domain seeding the target must be copied with
`assign`, and that merging a dataset into its own child is forbidden.
Measured on rerun: **ADAE executed variables went 7 → 32, duplicate-record
errors 25 → 0**; the current run (with `assign_conditional` also available)
executes 33 of 55, and the oracle comparison stands at 27 compared / 25 full
match / 96.3% mean.

That sequence — probe, registered finding, fix, regression test, re-measure —
is the point. The numbers in this post are post-loop numbers, and the loop is
part of the product.

## Where it was wrong — and what kind of wrong

The residual disagreements are more interesting than the clean matches:

- **HEIGHTBL/WEIGHTBL: raw agreement 19.7%/8.7% — and 98.8%/94.5% at the
  oracle's own precision** (finding F-05). The values trace to exactly the VS
  records the spec names; the oracle stores them rounded to 1 decimal, a
  convention the spec text never mentions. The derivation is right; the
  metadata was silent.
- **AGEGR1N: in the run that derived it, every mismatch (11/254) was a
  subject aged exactly 80** (finding F-04). The spec says both "65–80" and
  ">80". The model picked one reading, the submission picked the other. A
  human programmer would have had to query the same boundary. In the current
  cached run the model abstains on this variable instead — run-to-run
  variance, recorded as limitation 8.
- **ADLBC BASE/CHG is a defect in the spec text** (finding F-09). The
  workbook's derivation for BASE is literally `LB.LBSTNRHI` — the record's
  own upper normal limit, not the baseline value. The rules backend still
  executes it verbatim and lands at 0.4% agreement; the LLM this run
  *abstained* on BASE as a "likely improper mapping" — which is exactly the
  query a human programmer would raise at this spot.
- **Honest dependency cascades.** Most remaining ADAE/ADLBC execution errors
  are variables that merge ADSL columns the ADSL backend itself abstained on
  (TRTSDT, TRT01AN, RACEN, SAFFL, …) — cross-dataset derivations can only be
  as complete as their upstreams.

This is why the pipeline compares against an oracle instead of asserting
correctness: the honest output of an automation showcase is a *failure
taxonomy*, not a victory lap.

## What we are not claiming

The report's limitations section is verbatim and non-negotiable:

1. Population subsetting is not automated (produced datasets start from the
   full SDTM base domain; the ADSL oracle is the 254-subject randomized
   population). Agreement is computed on joined records only.
2. Vocabulary gaps are hard boundaries — more LLM voters cannot fix a
   missing layer. A narrow `assign_conditional` layer now exists, but
   record-existence/windowing, missingness checks, and multi-branch logic
   remain holes.
3. The rules backend is keyword-fragile; it's a baseline, not understanding.
4. The bundled evals corpus is self-scoring (its expected values were
   generated by the rules backend) — a regression corpus, not an oracle.
5. IR agreement ≠ double programming. Every voter reads the same spec text.
6. Oracle differences may be spec ambiguity, not package error.
7. The generated programs are UNGATED DRAFTs — no human approval gate covers
   them; they are demonstration output, never release-grade.
8. Single model, three datasets, and stochastic: across the full-spec ADSL
   runs behind this report's development, the `needs_human` count moved
   24 → 22 → 27 → 25 and rules/LLM layer-chain agreement 78% → 71% → 82% →
   80%. That variance is why the consensus-voting mode exists.
9. Value-level metadata is out of scope (the workbook's `ValueLevel` sheet is
   all ADADAS, which this run does not attempt).

## Why constrain the LLM at all?

Because the constraint is what makes everything else cheap. A closed
vocabulary means the LLM's output is schema-validatable, hashable,
diff-able, and signable. It means "the model's answer" is a small JSON object
a reviewer can actually read, instead of 200 lines of R they must audit. And
it means the failure mode shifts from *silent wrongness* to *loud
abstention* — which is the only failure mode regulated programming can
afford. When we widened the vocabulary this month, we did it one layer at a
time, measured the result, and published the gap between prediction and
outcome (F-11) next to the win.

The LLM is a translator, not an author. The compiler writes the code. The
gate decides what ships. And when the spec is ambiguous, the system says so —
across three real submission datasets, with receipts, and with a findings
register showing the gate getting sharper because we measured it.

---

*admiralagent is MIT-licensed:
`pak::pak("yanmingyu92/admiralagent")`. The full showcase (pipeline +
REPORT.md + evidence files) lives in `demo/automation/`; the narrative
version is on the
[package site](https://yanmingyu92.github.io/admiralagent/articles/cdisc-pilot-showcase.html).*

---

## Submission notes (not part of the article)

R-bloggers is an RSS aggregator — it does not accept articles directly; it
re-publishes posts from registered blog feeds.

- [USER ACTION] Publish this post on a blog you control that exposes an
  RSS/Atom feed (e.g. a personal Quarto blog, or the pkgdown site above if it
  has a blog section with a feed).
- [USER ACTION] Submit the feed URL to R-bloggers via their "add your blog"
  page (https://www.r-bloggers.com/add-your-blog/). The feed must be
  R-focused and approval is manual.
- Alternative path — Posit Blog guest post: there is no self-serve
  submission form; guest posts are arranged by pitching Posit's developer
  relations / blog editors. [USER ACTION] Send the pitch (this draft + a one
  paragraph summary) through Posit's contact channels and agree timing with
  the editors before publishing elsewhere, since cross-posting terms should
  be confirmed with them.
