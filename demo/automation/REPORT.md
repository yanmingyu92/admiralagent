# CDISC Pilot 5 Automation Showcase — admiralagent + DeepSeek

**Question:** given the real CDISC pilot 5 data and the real submission ADaM spec, how far does admiralagent (+ DeepSeek as the translation backend) get on its own — and where exactly is the boundary?

Reproduce with one command from the package root:

```sh
Rscript demo/automation/run_all.R            # cached LLM results reused
AA_FORCE_LLM=1 Rscript demo/automation/run_all.R   # re-spend on DeepSeek
```

Every number below is read from a machine-readable file under `demo/automation/out/` (cited per section). Generated: 2026-10-01 17:22:45 UTC.

## 1. Inputs (`out/ingest_manifest.json`)

- **Spec**: `adam-pilot-5.xlsx` (sha256 `aaee79438d93…`) — the pilot5 submission's P21-style define workbook. `read_spec()` cannot parse it (not metacore layout), so spec rows were derived by joining `Variables$Method` → `Methods$Description`. Derivation text is verbatim from the workbook; the only mechanical templating is `Copied directly from <DS.VAR>` for variables with nothing but a Predecessor pointer.
- Derivation provenance: method=47, predecessor=2 (of 49 ADSL variables).
- **SDTM inputs**: 9 xpt files (dm/ex/vs/ae/sv/ds/sc/mh/qs), sha256 recorded in the manifest.
- **Oracle**: `original-adamdata/adsl.xpt` (254 rows × 49 cols).

## 2. Automation funnel per backend

Sources: `out/gate_report.json`, `out/exec_status_<backend>.csv`, `out/validation_<backend>.csv`.

| backend | spec_vars | needs_human | gate | executed | exec_error | review | val_PASS | val_FAIL | val_MANUAL |
|---|---|---|---|---|---|---|---|---|---|
| rules | 49 | 32 | PASS | 16 | 1 | 32 | 18 | 1 | 32 |
| llm | 49 | 27 | PASS | 20 | 2 | 27 | 24 | 2 | 27 |
| consensus | 12 |  5 | PASS |  6 | 1 |  5 |  8 | 1 |  5 |

`consensus` covers only the 12-variable subset of section 5, so its denominators differ from the full-spec backends by design.

Gate policy: package default is gate-required; this showcase writes programs with `require_gate = FALSE` (no human approver in an unattended run). All programs therefore carry the UNGATED DRAFT banner and `release_grade="ungated-draft"` in their sidecars (`out/gate_report.json` mirrors this). The opt-out is explicit and recorded, never silent.

## 3. Accuracy vs the submitted oracle (`out/accuracy_<backend>.csv`, `out/accuracy_summary.json`)

Join on USUBJID. Dates compared exactly after `as.Date`; numerics within 1e-6 (0.5 for ratio-derived BMIBL/AVGDD); characters exact. The produced ADSL is built from DM (**no population subsetting** — the pipeline automates derivations, not the decision to keep only randomized subjects), so it has more rows than the 254-subject oracle; agreement is computed on joined subjects.

- **rules**: 15/49 spec variables compared, 15 fully matching, 0 partial, mean value agreement 100.0%.
- **llm**: 19/49 spec variables compared, 16 fully matching, 3 partial, mean value agreement 90.9%.

### Per-variable table

| variable | rules_status | rules_agree% | llm_status | llm_agree% | llm_agree%@oracle_prec |
|---|---|---|---|---|---|
| STUDYID | compared | 100 | compared | 100.0 | NA |
| USUBJID | compared |  83 | compared |  83.0 | NA |
| SUBJID | compared | 100 | compared | 100.0 | NA |
| SITEID | compared | 100 | compared | 100.0 | NA |
| SITEGR1 | not_produced | NA | not_produced | NA | NA |
| ARM | compared | 100 | compared | 100.0 | NA |
| TRT01P | compared | 100 | compared | 100.0 | NA |
| TRT01PN | not_produced | NA | not_produced | NA | NA |
| TRT01A | compared | 100 | compared | 100.0 | NA |
| TRT01AN | not_produced | NA | not_produced | NA | NA |
| TRTSDT | not_produced | NA | not_produced | NA | NA |
| TRTEDT | not_produced | NA | not_produced | NA | NA |
| TRTDURD | not_produced | NA | not_produced | NA | NA |
| AVGDD | not_produced | NA | not_produced | NA | NA |
| CUMDOSE | not_produced | NA | not_produced | NA | NA |
| AGE | compared | 100 | compared | 100.0 | NA |
| AGEGR1 | not_produced | NA | not_produced | NA | NA |
| AGEGR1N | not_produced | NA | not_produced | NA | NA |
| AGEU | compared | 100 | compared | 100.0 | NA |
| RACE | compared | 100 | compared | 100.0 | NA |
| RACEN | not_produced | NA | not_produced | NA | NA |
| SEX | compared | 100 | compared | 100.0 | NA |
| ETHNIC | compared | 100 | compared | 100.0 | NA |
| SAFFL | not_produced | NA | not_produced | NA | NA |
| ITTFL | not_produced | NA | not_produced | NA | NA |
| EFFFL | not_produced | NA | not_produced | NA | NA |
| COMP8FL | not_produced | NA | not_produced | NA | NA |
| COMP16FL | not_produced | NA | not_produced | NA | NA |
| COMP24FL | not_produced | NA | not_produced | NA | NA |
| DISCONFL | not_produced | NA | not_produced | NA | NA |
| DSRAEFL | not_produced | NA | not_produced | NA | NA |
| DTHFL | compared | 100 | compared | 100.0 | NA |
| BMIBL | not_produced | NA | compared |  99.6 | NA |
| BMIBLGR1 | not_produced | NA | not_produced | NA | NA |
| HEIGHTBL | not_produced | NA | compared |  19.7 | 98.8 |
| WEIGHTBL | not_produced | NA | compared |   8.7 | 94.5 |
| EDUCLVL | not_produced | NA | compared | 100.0 | NA |
| DISONSDT | not_produced | NA | not_produced | NA | NA |
| DURDIS | not_produced | NA | not_produced | NA | NA |
| DURDSGR1 | not_produced | NA | not_produced | NA | NA |
| VISIT1DT | not_produced | NA | not_produced | NA | NA |
| RFSTDTC | compared | 100 | compared | 100.0 | NA |
| RFENDTC | compared | 100 | compared | 100.0 | NA |
| VISNUMEN | not_produced | NA | not_produced | NA | NA |
| RFENDT | compared | 100 | not_produced | NA | NA |
| DCDECOD | not_produced | NA | compared | 100.0 | NA |
| EOSSTT | not_produced | NA | not_produced | NA | NA |
| DCSREAS | not_produced | NA | not_produced | NA | NA |
| MMSETOT | not_produced | NA | not_produced | NA | NA |

`llm_agree%@oracle_prec` is only populated for HEIGHTBL/WEIGHTBL: the oracle stores these rounded to 1 decimal while the spec text never mentions rounding, so agreement at the oracle's own storage precision is reported alongside the raw figure (finding F-05).

## 4. Rules vs LLM layer-chain agreement (`out/rules_vs_llm_layers.csv`)

Identical layer chains on **40/49** variables (82%). This is IR-level agreement between two translators reading the same spec text — it is **not** double programming and says nothing about correctness against the oracle (DESIGN.md section 11, item 1).

Disagreements:

| variable | rules | llm | agree |
|---|---|---|---|
| TRTDURD | needs_human | compute_var | FALSE |
| AVGDD | needs_human | compute_var | FALSE |
| BMIBL | needs_human | compute_var | FALSE |
| BMIBLGR1 | compute_param->merge_var | needs_human | FALSE |
| HEIGHTBL | needs_human | merge_var | FALSE |
| WEIGHTBL | needs_human | merge_var | FALSE |
| EDUCLVL | needs_human | merge_var | FALSE |
| RFENDT | impute_dtc | needs_human | FALSE |
| DCDECOD | needs_human | merge_var | FALSE |

## 5. Multi-sample consensus (`out/consensus.csv`)

Subset: 12 derived-origin variables (first 12 in spec order, deterministic), 3 samples, majority vote. Unanimous on **12/12** variables.

| variable | signature_votes | chosen | unanimous |
|---|---|---|---|
| SUBJID | assign@130366af:3 | assign | TRUE |
| SITEID | assign@479f3af1:3 | assign | TRUE |
| SITEGR1 | needs_human@e4a67c77:3 | needs_human | TRUE |
| ARM | assign@be0d2f24:3 | assign | TRUE |
| TRT01P | assign@6a34d7e5:3 | assign | TRUE |
| TRT01PN | needs_human@e4a67c77:3 | needs_human | TRUE |
| TRT01A | assign@4f057cb5:3 | assign | TRUE |
| TRT01AN | needs_human@e4a67c77:3 | needs_human | TRUE |
| TRTSDT | merge_var->impute_dtc@8e7ceeab:1 | merge_var->impute_dtc | TRUE |
| TRTEDT | needs_human@70e5bb3f:1 | needs_human | TRUE |
| TRTDURD | compute_var@3103dfd0:1 | compute_var | TRUE |
| AVGDD | needs_human@2674cf1d:1 | needs_human | TRUE |

Caveat (DESIGN.md section 11): all voters read the *same* spec text, so spec errors are shared by every voter; consensus measures translation variance, not correctness. Vocabulary gaps (e.g. conditional/windowing layers) push all voters into the same abstention or the same wrong mapping — more voters cannot fix a vocabulary hole.

## 6. DeepSeek latency / cost (`out/llm_telemetry.json`)

- **full**: 84.2s, 5,505 in / 7,083 out tokens, est. cost $0.0093 (rate assumption: $0.27/M in, $1.10/M out, 2025 price sheet).
- **consensus**: 84.9s, 4,951 in / 7,827 out tokens, est. cost $0.0099 (rate assumption: $0.27/M in, $1.10/M out, 2025 price sheet).
- **rules baseline**: 0.262s, zero cost.

## 7. Failure taxonomy (`out/exec_status_<backend>.csv`)

### rules: 1 execution errors

| variable | status | note |
|---|---|---|
| BMIBLGR1 | ERROR | [duplicate_records] admiral::derive_param_computed() [step 1/2, layer compute_param]: message redacted (may contain data values); enable options(admiralagent.error_detail = TRUE) and read aa_last_error_detail() |

### llm: 2 execution errors

| variable | status | note |
|---|---|---|
| TRTDURD | ERROR | column 'TRTEDT' is missing from source dataset 'ADSL' |
| AVGDD | ERROR | upstream derivation failed; stale inputs are not used |


## 8. needs_human inventory (from the IR objects)

### rules: 32 variables abstained

| variable | rationale |
|---|---|
| SITEGR1 | rule: no matching pattern, routed to human review |
| TRT01PN | rule: no matching pattern, routed to human review |
| TRT01AN | rule: no matching pattern, routed to human review |
| TRTSDT | rule: no matching pattern, routed to human review |
| TRTEDT | rule: no matching pattern, routed to human review |
| TRTDURD | rule: no matching pattern, routed to human review |
| AVGDD | rule: no matching pattern, routed to human review |
| CUMDOSE | rule: no matching pattern, routed to human review |
| AGEGR1 | rule: no matching pattern, routed to human review |
| AGEGR1N | rule: no matching pattern, routed to human review |
| RACEN | rule: no matching pattern, routed to human review |
| SAFFL | rule: no matching pattern, routed to human review |
| ITTFL | rule: no matching pattern, routed to human review |
| EFFFL | rule: no matching pattern, routed to human review |
| COMP8FL | rule: no matching pattern, routed to human review |
| COMP16FL | rule: no matching pattern, routed to human review |
| COMP24FL | rule: no matching pattern, routed to human review |
| DISCONFL | rule: no matching pattern, routed to human review |
| DSRAEFL | rule: no matching pattern, routed to human review |
| BMIBL | rule: no matching pattern, routed to human review |
| HEIGHTBL | rule: no matching pattern, routed to human review |
| WEIGHTBL | rule: no matching pattern, routed to human review |
| EDUCLVL | rule: no matching pattern, routed to human review |
| DISONSDT | rule: no matching pattern, routed to human review |
| DURDIS | rule: no matching pattern, routed to human review |
| DURDSGR1 | rule: no matching pattern, routed to human review |
| VISIT1DT | rule: no matching pattern, routed to human review |
| VISNUMEN | rule: no matching pattern, routed to human review |
| DCDECOD | rule: no matching pattern, routed to human review |
| EOSSTT | rule: no matching pattern, routed to human review |
| DCSREAS | rule: no matching pattern, routed to human review |
| MMSETOT | rule: no matching pattern, routed to human review |

### llm: 27 variables abstained

| variable | rationale |
|---|---|
| SITEGR1 | Derivation depends on external SAP pooling rules (Section 7.1) not fully specified; conditional site pooling decision is human-only. |
| TRT01PN | Numeric code for planned treatment requires an external codelist mapping (randomized dose); no explicit codelist provided in spec. |
| TRT01AN | Numeric code for actual treatment requires an external codelist mapping (randomized dose); no explicit codelist provided. |
| TRTSDT | TRTSDT is a date target pulled from SV.SVSTDTC at VISITNUM=3; the spec does not supply an explicit DTC imputation rule, and character-to-date conversion requires human review of the partial-date/imputation policy. |
| TRTEDT | Derivation contains a conditional fallback (missing final dose -> discontinuation date) requiring conditional selection logic and external CRF/DS references; ambiguous and human-only. |
| CUMDOSE | Derivation is a complex multi-branch conditional dependent on ARMN, scheduled visit dates (visit4date, visit12date), dosing intervals and discontinuation logic; not expressible with the allowed operations. |
| AGEGR1 | AGEGR1 is the character decode of AGEGR1N, but the exact label text (e.g. '<65', '65-80', '>80') is not given in the spec; the codelist decode mapping must be confirmed. |
| AGEGR1N | Age breakpoints: 1 if AGE<65, 2 if 65-80, 3 if >80. Breakpoints are explicit but boundary handling (closed/open at 65 and 80/81) requires confirmation; low boundary placeholder needed. |
| RACEN | Numeric code for RACE requires an external codelist mapping; no explicit codelist supplied in the spec. |
| SAFFL | SAFFL is a conditional flag (Y if ITTFL='Y' and TRTSDT not missing, else N); conditional logic is not expressible with the allowed operations. |
| ITTFL | Conditional flag (Y if ARMCD ne ' ', N otherwise); conditional logic is not expressible with allowed operations. |
| EFFFL | Multi-condition flag spanning SAFFL plus existence checks across QS records for ADAS-Cog and CIBIC+ with VISITNUM>3; requires complex conditional joins not expressible with allowed operations. |
| COMP8FL | Conditional flag requiring SV.VISITNUM=8 record and comparison of ENDDT to visit 8 date; external date lookups and conditional logic not expressible with allowed operations. |
| COMP16FL | Conditional flag requiring SV.VISITNUM=10 record and comparison of ENDDT to visit 10 date; external date lookups and conditional logic not expressible with allowed operations. |
| COMP24FL | Conditional flag requiring SV.VISITNUM=12 record and comparison of ENDDT to visit 12 date; external date lookups and conditional logic not expressible with allowed operations. |
| DISCONFL | Conditional flag (Y if DCREASCD ^= 'Completed', Null otherwise); conditional logic not expressible with allowed operations. |
| DSRAEFL | Conditional flag (Y if DCREASCD='Adverse Event', Null otherwise); conditional logic not expressible with allowed operations. |
| BMIBLGR1 | Breakpoints 25 and 30 are explicit, but handling of missing/negative lower boundary requires confirmation of the low breakpoint placeholder. |
| DISONSDT | DISONSDT is a date target pulled from MH.MHSTDTC; spec gives no explicit DTC imputation rule and character-to-date conversion requires an imputation policy, so human review is needed. |
| DURDIS | Duration in months between VISIT1DT and DISONSDT; VISIT1DT is not defined in this spec and must be confirmed as a valid date endpoint in the base dataset. |
| DURDSGR1 | Breakpoint at 12 is explicit but the lower boundary placeholder and missing handling require confirmation of low breakpoint. |
| VISIT1DT | VISIT1DT is a date target pulled from SV.SVSTDTC at VISITNUM=1; spec gives no explicit DTC imputation rule and character-to-date conversion requires an imputation policy. |
| VISNUMEN | Conditional derivation (VISITNUM=13 remapped to 12, else DS.VISITNUM) with DSTERM filter; branching conditional logic not expressible with allowed operations. |
| RFENDT | RFENDTC character date converted to a SAS date; no explicit imputation rule given, and DTC imputation policy must be confirmed by human review. |
| EOSSTT | Conditional mapping of DCDECOD to COMPLETED/DISCONTINUED; conditional logic not expressible with allowed operations. |
| DCSREAS | Grouping of DCDECOD values into standardized discontinuation reasons requires an external mapping/codelist not provided. |
| MMSETOT | MMSETOT is a subject-level sum of QS.QSORRES (character) values where QSCAT='MINI-MENTAL STATE'; requires filtering, character-to-numeric conversion, and aggregation across QS records not expressible with the allowed ope |


## 9. Findings registered this run (`out/findings.json`)

Per the AGENTS.md improvement-loop convention, every ERROR/FAIL/MANUAL class observed gets a numbered finding with evidence. `severity`: **package** = code defect to fix; **demo** = pipeline configuration; **spec** = source-spec ambiguity; **oracle** = oracle convention the spec text does not mention.

- **F-01 (package) — impute_dtc dtc referencing a renamed-away column passes validate_ir() but fails at execution.** LLM/consensus chains for TRTSDT: merge_var(source=SVSTDTC -> target=TRTSDT) then impute_dtc(target=TRTSDT, dtc=SVSTDTC). After the merge, SVSTDTC no longer exists on ADSL (it landed as TRTSDT), so execution fails with 'column SVSTDTC is missing from source dataset ADSL'. validate_ir() does not track column provenance across steps, so this is only caught at execution - the fail-closed execution layer caught it, but the semantic gate could catch it earlier. _Evidence: out/exec_status_llm.csv (TRTSDT), out/exec_status_consensus.csv (TRTSDT)._
  - Suggested fix: Extend the semantic checks (ir_dependency_report / validate_ir) to flag step args that reference columns neither in the base nor produced by earlier steps under their referenced name.
- **F-02 (demo) — codelist_var executions fail without sources$mc (metacore object).** LLM chose codelist_var for RACEN/TRT01PN/TRT01AN; the layer renders metatools::create_var_from_codelist() which needs a metacore object named mc in the execution sources. The showcase did not build one from the define workbook, so these variables error at execution. This is a pipeline configuration gap, not an IR error - the IR is valid; the execution context was incomplete. _Evidence: out/exec_status_llm.csv (RACEN), out/exec_status_consensus.csv (TRT01PN, TRT01AN)._
  - Suggested fix: Build a metacore object from adam-pilot-5.xlsx codelists sheet in 00_ingest and pass it as sources$mc; or document codelist_var as out-of-scope for this showcase.
- **F-03 (package) — rules backend maps BMIBLGR1 categorisation text to compute_param->merge_var.** The rules classifier matched BMI keywords in 'BMIBLGR1="<25" if . < BMIBL <25...' and emitted compute_param+merge_var instead of categorize; execution then failed inside derive_param_computed (duplicate_records). Concrete instance of the documented keyword-fragility limitation: the rules backend is a zero-cost baseline, not a semantic parser. _Evidence: out/exec_status_rules.csv (BMIBLGR1), out/rules_vs_llm_layers.csv (BMIBLGR1 row)._
  - Suggested fix: Optional: add a categorisation keyword rule with higher priority than the BMI compute_param pattern; low value vs LLM backend, recorded for transparency.
- **F-04 (spec) — AGEGR1N boundary: all 11 mismatches are subjects aged exactly 80.** Spec text: 'AGEGR1 = 2 if AGE 65-80. AGEGR1 = 3 if AGE >80.' The LLM encoded breaks [0,65,80,Inf) right=FALSE, mapping AGE==80 to group 3; the oracle maps 80 to group 2 (reading '65-80' as inclusive). The spec text is self-contradictory at the boundary ('65-80' vs '>80'); 11/254 subjects sit exactly on it. This is spec ambiguity a human programmer would also have to query, not a clear package error. _Evidence: out/accuracy_llm.csv (AGEGR1N 95.7%), demo/_probe_mismatch.R output (all 11 mismatches at AGE==80)._
- **F-05 (oracle) — HEIGHTBL/WEIGHTBL disagreement is the oracle's undocumented 1-decimal rounding.** Raw agreement is 19.7%/8.7%, but both values trace to the same VS records the spec names (HEIGHT VISITNUM=1, WEIGHT VISITNUM=3 - both exist and match). The oracle stores 1-decimal rounded values; at oracle precision agreement is 98.8%/94.9%. The residual (~1-5%) is round-half edge cases. The derivation is semantically correct; the spec text never mentions rounding. _Evidence: out/accuracy_llm.csv (value_agree vs value_agree_oracle_prec columns), demo/_probe_rounding.R output._

## 10. Limitations (read this before quoting any number above)

1. **Population subsetting is not automated.** Produced ADSL starts from DM (all screened subjects); the oracle has 254 randomized subjects. Row-level agreement is only computed on the join.
2. **Vocabulary gaps are hard boundaries.** The layer vocabulary has no conditional/windowing layers; derivations like COMP8FL/COMP16FL/COMP24FL (visit-window existence checks), EFFFL (cross-dataset existence), CUMDOSE (arm-conditional dose logic) or ADTTE-style CNSR can only abstain or be approximated. More LLM voters cannot fix a vocabulary hole (DESIGN.md section 11, item 5).
3. **The rules backend is keyword-fragile.** It matches English phrases; paraphrase the spec and its output changes. It is a zero-cost baseline, not a claim of understanding.
4. **The evals corpus is self-scoring** (`inst/evals/spec-to-ir.jsonl` expected values were generated by the rules backend). It pins current behavior as contract; it is not an oracle (DESIGN.md section 11, item 2).
5. **IR agreement ≠ double programming.** Rules/LLM agreement and 3-sample consensus measure translation consistency before execution, with all voters reading the same spec text (DESIGN.md section 11, item 1).
6. **Oracle differences may be spec ambiguity, not package error.** Where a produced value disagrees with the oracle, the spec text itself is often ambiguous (e.g. CUMDOSE's arm-conditional rule); a human programmer would also have to ask. Disagreement rates here are not error rates.
7. **Programs are UNGATED DRAFTs.** No human approval gate covers these artifacts; they are demonstration output, not release-grade deliverables (DESIGN.md section 11, item 4).
8. **Single model, single dataset, and stochastic.** Numbers are for DeepSeek `deepseek-chat` on pilot5 ADSL only; they do not transfer to other models or datasets without re-measurement. LLM output also varies run to run at temperature defaults: across the two full runs behind this report's development, the full-spec needs_human count moved 24 -> 22 and the rules/LLM layer-chain agreement 78% -> 71% — run-to-run translation variance is exactly what the consensus mode in section 5 exists to measure and contain.
