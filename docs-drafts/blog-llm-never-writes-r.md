# LLM Never Writes R Code: What Happened When We Fed a Real CDISC Submission to admiralagent

*Draft for R-bloggers / Posit Blog guest post. Every number below comes from a
one-command, re-runnable pipeline (`Rscript demo/automation/run_all.R`) against
the public CDISC pilot 5 data; the evidence trail is `demo/automation/REPORT.md`
plus machine-readable files under `demo/automation/out/` in the repo.*

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
stopped asserting it and measured it.

## The experiment: real data, real spec, one command

We pointed the pipeline at the **CDISC pilot 5 submission**: the real
P21-style ADaM define workbook (`adam-pilot-5.xlsx`, 49 ADSL variables, 47
with verbatim derivation methods), the original SDTM `.xpt` files as
execution inputs, and the submitted `adsl.xpt` as the accuracy oracle. Six
staged scripts — ingest, classify, gate+render, execute, oracle-compare,
report — run end-to-end from one command and are fully re-runnable.

We classified the same spec twice: a zero-dependency **rules backend**
(keyword baseline) and **DeepSeek** (`deepseek-chat`, via `{ellmer}`). A
12-variable subset additionally ran 3 samples with majority vote.

## The numbers

| backend | spec vars | abstained (`needs_human`) | executed | exec errors | oracle: compared | oracle: full match |
|---|---|---|---|---|---|---|
| rules | 49 | 32 | 16 | 1 | 15 | **15 (100%)** |
| DeepSeek | 49 | 27 | 20 | 2 | 19 | **16 (mean agreement 90.9%)** |

- The rules baseline abstains on two-thirds of a real spec — but everything
  it did derive matched the submitted ADSL **exactly**.
- DeepSeek automated more (20 vs 16 variables), rules-vs-LLM layer chains
  agreed on 82%, and the 3-sample consensus was unanimous on 12/12.
- Marginal cost of the LLM: **84 seconds and $0.009** for all 49 variables
  (5.5k input / 7.1k output tokens; rate assumption recorded in the repo).

But the headline number is the abstention column, not the accuracy column.

## The boundary is the story

DeepSeek declined 27 of 49 variables — and when you read the inventory, it is
not random. It is the vocabulary boundary, stated out loud:

- **No conditional layer exists**, so every `Y if <condition>` flag (SAFFL,
  ITTFL, DISCONFL, the COMP8/16/24 visit-window flags, EOSSTT) is abstained
  on — the model cannot invent `ifelse` because `ifelse` is not in the
  vocabulary.
- **External references** (SAP sections, unstated codelists, undocumented
  grouping schemes) are abstained on: SITEGR1, DCSREAS, TRT01PN.
- **Cross-dataset existence checks** (EFFFL, VISNUMEN) and **multi-branch
  clinical logic** (CUMDOSE's arm-conditional dosing intervals) are abstained
  on.

A system that hallucinated these would be strictly worse than one that
abstains. In a GxP narrative, "the machine said *I don't know* 27 times, with
a stated reason each time" is a feature you can defend in an audit.

## Where it was wrong — and what kind of wrong

The residual disagreements are more interesting than the clean matches:

- **HEIGHTBL/WEIGHTBL: raw agreement 19.7%/8.7% — and 98.8%/94.5% at the
  oracle's own precision.** The values trace to exactly the VS records the
  spec names; the oracle stores them rounded to 1 decimal, a convention the
  spec text never mentions. The derivation is right; the metadata was silent.
- **AGEGR1N: every mismatch (11/254) is a subject aged exactly 80.** The spec
  says both "65–80" and ">80". The model picked one reading, the submission
  picked the other. A human programmer would have had to query the same
  boundary.
- **One genuine package defect found**: an LLM chain that merges `SVSTDTC`
  into `TRTSDT` and then imputes from `SVSTDTC` passes the IR gate but fails
  at execution — the merge renamed the column away, and the semantic gate
  doesn't track that yet. The fail-closed execution layer caught it
  (transactional rollback, downstream variables refused stale inputs), and
  it's now a registered finding with a proposed fix.

This is why the pipeline compares against an oracle instead of asserting
correctness: the honest output of an automation showcase is a *failure
taxonomy*, not a victory lap.

## What we are not claiming

The report's limitations section is verbatim and non-negotiable:

1. Population subsetting is not automated (produced ADSL starts from DM; the
   oracle is the 254-subject randomized population).
2. Vocabulary gaps are hard boundaries — more LLM voters cannot fix a
   missing layer.
3. The rules backend is keyword-fragile; it's a baseline, not understanding.
4. The bundled evals corpus is self-scoring (its expected values were
   generated by the rules backend) — a regression corpus, not an oracle.
5. IR agreement ≠ double programming. Every voter reads the same spec text.
6. Oracle differences may be spec ambiguity, not package error.
7. The generated programs are UNGATED DRAFTs — no human approval gate covers
   them; they are demonstration output, never release-grade.
8. Single model, single dataset, and stochastic: across three runs the
   needs-human count moved 24 → 22 → 27. That variance is why the
   consensus-voting mode exists.

## Why constrain the LLM at all?

Because the constraint is what makes everything else cheap. A closed
vocabulary means the LLM's output is schema-validatable, hashable,
diff-able, and signable. It means "the model's answer" is a small JSON object
a reviewer can actually read, instead of 200 lines of R they must audit. And
it means the failure mode shifts from *silent wrongness* to *loud
abstention* — which is the only failure mode regulated programming can
afford.

The LLM is a translator, not an author. The compiler writes the code. The
gate decides what ships. And when the spec is ambiguous, the system says so —
in the run above, 27 times out of 49, with receipts.

---

*admiralagent is MIT-licensed:
`pak::pak("yanmingyu92/admiralagent")`. The full showcase (pipeline +
REPORT.md + evidence files) lives in `demo/automation/`; the narrative
version is on the
[package site](https://yanmingyu92.github.io/admiralagent/articles/cdisc-pilot-showcase.html).*
