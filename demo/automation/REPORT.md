# CDISC Pilot 5 Automation Showcase — admiralagent + DeepSeek

**Question:** given the real CDISC pilot 5 data and the real submission ADaM spec, how far does admiralagent (+ DeepSeek as the translation backend) get on its own — and where exactly is the boundary?

Datasets in this run: **ADSL, ADAE, ADLBC** (spec and oracle from the same pilot5 submission; `AA_DATASETS` env restricts the set).

Reproduce with one command from the package root:

```sh
Rscript demo/automation/run_all.R            # cached LLM results reused
AA_FORCE_LLM=1 Rscript demo/automation/run_all.R   # re-spend on DeepSeek
```

Every number below is read from a machine-readable file under `demo/automation/out/` (cited per section). Generated: 2026-10-01 21:49:05 UTC.

## 1. Inputs (`out/ingest_manifest.json`)

- **Spec**: `adam-pilot-5.xlsx` (sha256 `aaee79438d93…`) — the pilot5 submission's P21-style define workbook. `read_spec()` cannot parse it (not metacore layout), so spec rows were derived by joining `Variables$Method` → `Methods$Description`. Derivation text is verbatim from the workbook; the only mechanical templating is `Copied directly from <DS.VAR>` for variables with nothing but a Predecessor pointer.
- **ADSL**: 49 spec variables (derivation provenance: method=47, predecessor=2); oracle `adsl.xpt`; executable metacore for `codelist_var`: `mc_adsl.rds` (35 workbook codelists).
- **ADAE**: 55 spec variables (derivation provenance: method=53, predecessor=2); oracle `adae.xpt`; executable metacore for `codelist_var`: `mc_adae.rds` (35 workbook codelists).
- **ADLBC**: 46 spec variables (derivation provenance: label_fallback=2, method=22, predecessor=22); oracle `adlbc.xpt`; executable metacore for `codelist_var`: `mc_adlbc.rds` (35 workbook codelists).
- **SDTM inputs**: 10 xpt files (dm/ex/vs/ae/sv/ds/sc/mh/qs/lb), sha256 recorded in the manifest.
- The workbook's `Codelists` sheet (long table ID/Term/Decoded Value) is converted into `mock_metacore()` codelists at ingest, so `metatools::create_var_from_codelist()` steps execute against the submission's own terminology (fix for finding F-02).

## 2. Automation funnel per dataset and backend

Sources: `out/gate_report.json`, `out/exec_status_<backend>[_<ds>].csv`, `out/validation_<backend>[_<ds>].csv`.

### ADSL

| backend | spec_vars | needs_human | gate | executed | exec_error | review | val_PASS | val_FAIL | val_MANUAL |
|---|---|---|---|---|---|---|---|---|---|
| rules | 49 | 32 | PASS | 16 | 1 | 32 | 18 | 1 | 32 |
| llm | 49 | 27 | PASS | 20 | 2 | 27 | 24 | 2 | 27 |
| consensus | 12 |  5 | PASS |  6 | 1 |  5 |  8 | 1 |  5 |

### ADAE

| backend | spec_vars | needs_human | gate | executed | exec_error | review | val_PASS | val_FAIL | val_MANUAL |
|---|---|---|---|---|---|---|---|---|---|
| rules | 55 | 16 | PASS | 27 | 12 | 16 | 22 | 17 | 16 |
| llm | 55 |  8 | PASS | 32 | 15 |  8 | 28 | 33 |  8 |

### ADLBC

| backend | spec_vars | needs_human | gate | executed | exec_error | review | val_PASS | val_FAIL | val_MANUAL |
|---|---|---|---|---|---|---|---|---|---|
| rules | 46 | 14 | PASS | 15 | 17 | 14 | 16 | 16 | 14 |
| llm | 46 | 13 | PASS | 22 | 11 | 13 | 23 | 27 | 13 |

`consensus` covers only the 12-variable subset of section 5, so its denominators differ from the full-spec backends by design.

Gate policy: package default is gate-required; this showcase writes programs with `require_gate = FALSE` (no human approver in an unattended run). All programs therefore carry the UNGATED DRAFT banner and `release_grade="ungated-draft"` in their sidecars (`out/gate_report.json` mirrors this). The opt-out is explicit and recorded, never silent.

## 3. Accuracy vs the submitted oracle (`out/accuracy_<backend>[_<ds>].csv`, `out/accuracy_summary.json`)

Join on the dataset's row-identity keys (ADSL: USUBJID; ADAE: USUBJID+AESEQ; ADLBC: USUBJID+LBSEQ). Dates compared exactly after `as.Date`; numerics within 1e-6 (0.5 for ratio-derived BMIBL/AVGDD); characters exact. Produced datasets are built from the full SDTM base domain (**no population/parameter subsetting** — the pipeline automates derivations, not the decision of which records belong to the analysis population), so they have more rows than the oracles; agreement is computed on joined records.

### ADSL (oracle 254 rows × 49 cols)

- **rules**: 15/49 spec variables compared, 15 fully matching, 0 partial, mean value agreement 100.0% (produced 306 rows).
- **llm**: 19/49 spec variables compared, 16 fully matching, 3 partial, mean value agreement 90.9% (produced 306 rows).

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

### ADAE (oracle 1191 rows × 55 cols)

- **rules**: 20/55 spec variables compared, 20 fully matching, 0 partial, mean value agreement 100.0% (produced 1191 rows).
- **llm**: 27/55 spec variables compared, 25 fully matching, 2 partial, mean value agreement 96.3% (produced 1191 rows).

| variable | rules_status | rules_agree% | llm_status | llm_agree% | llm_agree%@oracle_prec |
|---|---|---|---|---|---|
| STUDYID | compared | 100 | compared | 100.0 | NA |
| SITEID | not_produced | NA | compared | 100.0 | NA |
| USUBJID | compared | 100 | compared | 100.0 | NA |
| TRTA | not_produced | NA | compared | 100.0 | NA |
| TRTAN | not_produced | NA | not_produced | NA | NA |
| AGE | not_produced | NA | compared | 100.0 | NA |
| AGEGR1 | not_produced | NA | not_produced | NA | NA |
| AGEGR1N | not_produced | NA | not_produced | NA | NA |
| RACE | not_produced | NA | compared | 100.0 | NA |
| RACEN | not_produced | NA | not_produced | NA | NA |
| SEX | not_produced | NA | compared | 100.0 | NA |
| SAFFL | not_produced | NA | not_produced | NA | NA |
| TRTSDT | not_produced | NA | not_produced | NA | NA |
| TRTEDT | not_produced | NA | not_produced | NA | NA |
| ASTDT | not_produced | NA | compared |  99.1 | NA |
| ASTDTF | not_produced | NA | compared |   1.3 | NA |
| ASTDY | not_produced | NA | not_produced | NA | NA |
| AENDT | not_produced | NA | not_produced | NA | NA |
| AENDY | not_produced | NA | not_produced | NA | NA |
| ADURN | not_produced | NA | not_produced | NA | NA |
| ADURU | not_produced | NA | not_produced | NA | NA |
| AETERM | compared | 100 | compared | 100.0 | NA |
| AELLT | compared | 100 | compared | 100.0 | NA |
| AELLTCD | all_missing | NA | all_missing | NA | NA |
| AEDECOD | compared | 100 | compared | 100.0 | NA |
| AEPTCD | all_missing | NA | all_missing | NA | NA |
| AEHLT | compared | 100 | compared | 100.0 | NA |
| AEHLTCD | all_missing | NA | all_missing | NA | NA |
| AEHLGT | compared | 100 | compared | 100.0 | NA |
| AEHLGTCD | all_missing | NA | all_missing | NA | NA |
| AEBODSYS | compared | 100 | compared | 100.0 | NA |
| AESOC | compared | 100 | compared | 100.0 | NA |
| AESOCCD | all_missing | NA | all_missing | NA | NA |
| AESEV | compared | 100 | compared | 100.0 | NA |
| AESER | compared | 100 | compared | 100.0 | NA |
| AESCAN | compared | 100 | compared | 100.0 | NA |
| AESCONG | compared | 100 | compared | 100.0 | NA |
| AESDISAB | compared | 100 | compared | 100.0 | NA |
| AESDTH | compared | 100 | compared | 100.0 | NA |
| AESHOSP | compared | 100 | compared | 100.0 | NA |
| AESLIFE | compared | 100 | compared | 100.0 | NA |
| AESOD | compared | 100 | compared | 100.0 | NA |
| AEREL | compared | 100 | compared | 100.0 | NA |
| AEACN | compared | 100 | compared | 100.0 | NA |
| AEOUT | compared | 100 | compared | 100.0 | NA |
| AESEQ | join_key | NA | join_key | NA | NA |
| TRTEMFL | not_produced | NA | not_produced | NA | NA |
| AOCCFL | not_produced | NA | not_produced | NA | NA |
| AOCCSFL | not_produced | NA | not_produced | NA | NA |
| AOCCPFL | not_produced | NA | not_produced | NA | NA |
| AOCC02FL | not_produced | NA | not_produced | NA | NA |
| AOCC03FL | not_produced | NA | not_produced | NA | NA |
| AOCC04FL | not_produced | NA | not_produced | NA | NA |
| CQ01NAM | not_produced | NA | not_produced | NA | NA |
| AOCC01FL | not_produced | NA | not_produced | NA | NA |

### ADLBC (oracle 37132 rows × 46 cols)

- **rules**: 14/46 spec variables compared, 12 fully matching, 2 partial, mean value agreement 85.8% (produced 59580 rows).
- **llm**: 21/46 spec variables compared, 19 fully matching, 2 partial, mean value agreement 90.5% (produced 59580 rows).

| variable | rules_status | rules_agree% | llm_status | llm_agree% | llm_agree%@oracle_prec |
|---|---|---|---|---|---|
| STUDYID | compared | 100.0 | compared | 100.0 | NA |
| SUBJID | not_produced | NA | compared | 100.0 | NA |
| USUBJID | compared | 100.0 | compared | 100.0 | NA |
| TRTP | not_produced | NA | compared | 100.0 | NA |
| TRTPN | not_produced | NA | not_produced | NA | NA |
| TRTA | not_produced | NA | compared | 100.0 | NA |
| TRTAN | not_produced | NA | not_produced | NA | NA |
| TRTSDT | not_produced | NA | not_produced | NA | NA |
| TRTEDT | not_produced | NA | not_produced | NA | NA |
| AGE | not_produced | NA | compared | 100.0 | NA |
| AGEGR1 | not_produced | NA | not_produced | NA | NA |
| AGEGR1N | not_produced | NA | not_produced | NA | NA |
| RACE | not_produced | NA | compared | 100.0 | NA |
| RACEN | not_produced | NA | not_produced | NA | NA |
| SEX | not_produced | NA | compared | 100.0 | NA |
| COMP24FL | not_produced | NA | not_produced | NA | NA |
| DSRAEFL | not_produced | NA | not_produced | NA | NA |
| SAFFL | not_produced | NA | not_produced | NA | NA |
| AVISIT | not_produced | NA | not_produced | NA | NA |
| AVISITN | not_produced | NA | not_produced | NA | NA |
| ADY | compared | 100.0 | compared | 100.0 | NA |
| ADT | compared | 100.0 | not_produced | NA | NA |
| VISIT | compared | 100.0 | compared | 100.0 | NA |
| VISITNUM | compared | 100.0 | compared | 100.0 | NA |
| PARAM | not_produced | NA | not_produced | NA | NA |
| PARAMCD | compared | 100.0 | compared | 100.0 | NA |
| PARAMN | not_produced | NA | not_produced | NA | NA |
| PARCAT1 | not_produced | NA | not_produced | NA | NA |
| AVAL | compared | 100.0 | compared | 100.0 | NA |
| BASE | compared |   0.4 | compared |   0.4 | NA |
| CHG | compared |   0.4 | compared |   0.4 | NA |
| A1LO | compared | 100.0 | compared | 100.0 | NA |
| A1HI | compared | 100.0 | compared | 100.0 | NA |
| R2A1LO | not_produced | NA | compared | 100.0 | NA |
| R2A1HI | not_produced | NA | compared | 100.0 | NA |
| BR2A1LO | not_produced | NA | not_produced | NA | NA |
| BR2A1HI | not_produced | NA | not_produced | NA | NA |
| ANL01FL | not_produced | NA | not_produced | NA | NA |
| ALBTRVAL | not_produced | NA | not_produced | NA | NA |
| ANRIND | not_produced | NA | not_produced | NA | NA |
| BNRIND | not_produced | NA | not_produced | NA | NA |
| ABLFL | compared | 100.0 | compared | 100.0 | NA |
| AENTMTFL | not_produced | NA | not_produced | NA | NA |
| LBSEQ | join_key | NA | join_key | NA | NA |
| LBNRIND | compared | 100.0 | compared | 100.0 | NA |
| LBSTRESN | compared | 100.0 | compared | 100.0 | NA |

`llm_agree%@oracle_prec` is only populated for HEIGHTBL/WEIGHTBL: the oracle stores these rounded to 1 decimal while the spec text never mentions rounding, so agreement at the oracle's own storage precision is reported alongside the raw figure (finding F-05).

## 4. Rules vs LLM layer-chain agreement (`out/rules_vs_llm_layers[_<ds>].csv`)

**ADSL**: identical layer chains on **40/49** variables (82%).

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

**ADAE**: identical layer chains on **32/55** variables (58%).

| variable | rules | llm | agree |
|---|---|---|---|
| STUDYID | assign | merge_var | FALSE |
| SITEID | assign | merge_var | FALSE |
| USUBJID | assign | needs_human | FALSE |
| TRTA | assign | merge_var | FALSE |
| TRTAN | assign | merge_var | FALSE |
| AGE | assign | merge_var | FALSE |
| AGEGR1 | assign | merge_var | FALSE |
| AGEGR1N | assign | merge_var | FALSE |
| RACE | assign | merge_var | FALSE |
| RACEN | assign | merge_var | FALSE |
| SEX | assign | merge_var | FALSE |
| SAFFL | assign | merge_var | FALSE |
| TRTSDT | assign | merge_var | FALSE |
| TRTEDT | assign | merge_var | FALSE |
| ASTDT | needs_human | impute_dtc | FALSE |
| ADURN | needs_human | compute_var | FALSE |
| AOCCFL | needs_human | extreme_flag | FALSE |
| AOCCSFL | needs_human | extreme_flag | FALSE |
| AOCCPFL | needs_human | extreme_flag | FALSE |
| AOCC02FL | needs_human | extreme_flag | FALSE |
| AOCC03FL | needs_human | extreme_flag | FALSE |
| AOCC04FL | needs_human | extreme_flag | FALSE |
| AOCC01FL | needs_human | extreme_flag | FALSE |

**ADLBC**: identical layer chains on **26/46** variables (57%).

| variable | rules | llm | agree |
|---|---|---|---|
| STUDYID | assign | merge_var | FALSE |
| SUBJID | assign | merge_var | FALSE |
| TRTP | assign | merge_var | FALSE |
| TRTPN | assign | merge_var | FALSE |
| TRTA | assign | merge_var | FALSE |
| TRTAN | assign | merge_var | FALSE |
| TRTSDT | assign | merge_var | FALSE |
| TRTEDT | assign | merge_var | FALSE |
| AGE | assign | merge_var | FALSE |
| AGEGR1 | assign | merge_var | FALSE |
| AGEGR1N | assign | merge_var | FALSE |
| RACE | assign | merge_var | FALSE |
| RACEN | assign | merge_var | FALSE |
| SEX | assign | merge_var | FALSE |
| COMP24FL | assign | merge_var | FALSE |
| DSRAEFL | assign | merge_var | FALSE |
| SAFFL | assign | merge_var | FALSE |
| ADT | assign | needs_human | FALSE |
| R2A1LO | needs_human | compute_var | FALSE |
| R2A1HI | needs_human | compute_var | FALSE |

This is IR-level agreement between two translators reading the same spec text — it is **not** double programming and says nothing about correctness against the oracle (DESIGN.md section 11, item 1).

## 5. Multi-sample consensus (`out/consensus[_<ds>].csv`)

**ADSL** subset: 12 derived-origin variables (first 12 in spec order, deterministic), 3 samples, majority vote. Unanimous on **12/12** variables.

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

### ADSL

- **full**: cached; last measured run: 84.2s, 5,505 in / 7,083 out tokens, est. cost $0.0093 (rate assumption: $0.27/M in, $1.10/M out, 2025 price sheet).
- **consensus**: cached; last measured run: 84.9s, 4,951 in / 7,827 out tokens, est. cost $0.0099 (rate assumption: $0.27/M in, $1.10/M out, 2025 price sheet).
- **rules baseline**: 0.101s, zero cost.

### ADAE

- **full**: 67.0s, 7,179 in / 7,799 out tokens, est. cost $0.0105 (rate assumption: $0.27/M in, $1.10/M out, 2025 price sheet).
- **consensus**: skipped — cost cap: 3x sampling reserved for ADSL; AA_CONSENSUS_ALL=1 opts in.
- **rules baseline**: 0.029s, zero cost.

### ADLBC

- **full**: 50.2s, 5,483 in / 6,326 out tokens, est. cost $0.0084 (rate assumption: $0.27/M in, $1.10/M out, 2025 price sheet).
- **consensus**: skipped — cost cap: 3x sampling reserved for ADSL; AA_CONSENSUS_ALL=1 opts in.
- **rules baseline**: 0.009s, zero cost.


## 7. Failure taxonomy (`out/exec_status_<backend>[_<ds>].csv`)

### ADSL / rules: 1 execution errors

| variable | status | note |
|---|---|---|
| BMIBLGR1 | ERROR | [duplicate_records] admiral::derive_param_computed() [step 1/2, layer compute_param]: message redacted (may contain data values); enable options(admiralagent.error_detail = TRUE) and read aa_last_error_detail() |

### ADSL / llm: 2 execution errors

| variable | status | note |
|---|---|---|
| TRTDURD | ERROR | column 'TRTEDT' is missing from source dataset 'ADSL' |
| AVGDD | ERROR | upstream derivation failed; stale inputs are not used |

### ADAE / rules: 12 execution errors

| variable | status | note |
|---|---|---|
| SITEID | ERROR | column 'SITEID' is missing from source dataset 'ADAE' |
| TRTA | ERROR | column 'TRT01A' is missing from source dataset 'ADAE' |
| TRTAN | ERROR | column 'TRT01AN' is missing from source dataset 'ADAE' |
| AGE | ERROR | column 'AGE' is missing from source dataset 'ADAE' |
| AGEGR1 | ERROR | column 'AGEGR1' is missing from source dataset 'ADAE' |
| AGEGR1N | ERROR | column 'AGEGR1N' is missing from source dataset 'ADAE' |
| RACE | ERROR | column 'RACE' is missing from source dataset 'ADAE' |
| RACEN | ERROR | column 'RACEN' is missing from source dataset 'ADAE' |
| SEX | ERROR | column 'SEX' is missing from source dataset 'ADAE' |
| SAFFL | ERROR | column 'SAFFL' is missing from source dataset 'ADAE' |
| TRTSDT | ERROR | column 'TRTSDT' is missing from source dataset 'ADAE' |
| TRTEDT | ERROR | column 'TRTEDT' is missing from source dataset 'ADAE' |

### ADAE / llm: 15 execution errors

| variable | status | note |
|---|---|---|
| TRTAN | ERROR | column 'TRT01AN' is missing from source dataset 'adsl' |
| AGEGR1 | ERROR | column 'AGEGR1' is missing from source dataset 'adsl' |
| AGEGR1N | ERROR | column 'AGEGR1N' is missing from source dataset 'adsl' |
| RACEN | ERROR | column 'RACEN' is missing from source dataset 'adsl' |
| SAFFL | ERROR | column 'SAFFL' is missing from source dataset 'adsl' |
| TRTSDT | ERROR | column 'TRTSDT' is missing from source dataset 'adsl' |
| TRTEDT | ERROR | column 'TRTEDT' is missing from source dataset 'adsl' |
| AOCCFL | ERROR | column 'TRTEMFL' is missing from source dataset 'ADAE' |
| AOCCSFL | ERROR | column 'TRTEMFL' is missing from source dataset 'ADAE' |
| AOCCPFL | ERROR | column 'TRTEMFL' is missing from source dataset 'ADAE' |
| AOCC02FL | ERROR | column 'TRTEMFL' is missing from source dataset 'ADAE' |
| AOCC03FL | ERROR | column 'TRTEMFL' is missing from source dataset 'ADAE' |
| AOCC04FL | ERROR | column 'TRTEMFL' is missing from source dataset 'ADAE' |
| AOCC01FL | ERROR | column 'CQ01NAM' is missing from source dataset 'ADAE' |
| ADURN | ERROR | column 'AENDT' is missing from source dataset 'ADAE' |

### ADLBC / rules: 17 execution errors

| variable | status | note |
|---|---|---|
| SUBJID | ERROR | column 'SUBJID' is missing from source dataset 'ADLBC' |
| TRTP | ERROR | column 'TRT01P' is missing from source dataset 'ADLBC' |
| TRTPN | ERROR | column 'TRT01PN' is missing from source dataset 'ADLBC' |
| TRTA | ERROR | column 'TRT01A' is missing from source dataset 'ADLBC' |
| TRTAN | ERROR | column 'TRT01AN' is missing from source dataset 'ADLBC' |
| TRTSDT | ERROR | column 'TRTSDT' is missing from source dataset 'ADLBC' |
| TRTEDT | ERROR | column 'TRTEDT' is missing from source dataset 'ADLBC' |
| AGE | ERROR | column 'AGE' is missing from source dataset 'ADLBC' |
| AGEGR1 | ERROR | column 'AGEGR1' is missing from source dataset 'ADLBC' |
| AGEGR1N | ERROR | column 'AGEGR1N' is missing from source dataset 'ADLBC' |
| RACE | ERROR | column 'RACE' is missing from source dataset 'ADLBC' |
| RACEN | ERROR | column 'RACEN' is missing from source dataset 'ADLBC' |
| SEX | ERROR | column 'SEX' is missing from source dataset 'ADLBC' |
| COMP24FL | ERROR | column 'COM01P24FL' is missing from source dataset 'ADLBC' |
| DSRAEFL | ERROR | column 'DSR01AEFL' is missing from source dataset 'ADLBC' |
| SAFFL | ERROR | column 'SAF01FL' is missing from source dataset 'ADLBC' |
| PARAMCD | ERROR | column 'TESTCD' is missing from source dataset 'ADLBC' |

### ADLBC / llm: 11 execution errors

| variable | status | note |
|---|---|---|
| TRTPN | ERROR | column 'TRT01PN' is missing from source dataset 'adsl' |
| TRTAN | ERROR | column 'TRT01AN' is missing from source dataset 'adsl' |
| TRTSDT | ERROR | column 'TRTSDT' is missing from source dataset 'adsl' |
| TRTEDT | ERROR | column 'TRTEDT' is missing from source dataset 'adsl' |
| AGEGR1 | ERROR | column 'AGEGR1' is missing from source dataset 'adsl' |
| AGEGR1N | ERROR | column 'AGEGR1N' is missing from source dataset 'adsl' |
| RACEN | ERROR | column 'RACEN' is missing from source dataset 'adsl' |
| COMP24FL | ERROR | column 'COM01P24FL' is missing from source dataset 'adsl' |
| DSRAEFL | ERROR | column 'DSR01AEFL' is missing from source dataset 'adsl' |
| SAFFL | ERROR | column 'SAF01FL' is missing from source dataset 'adsl' |
| PARAMCD | ERROR | column 'TESTCD' is missing from source dataset 'ADLBC' |


## 8. needs_human inventory (from the IR objects)

### ADSL / rules: 32 variables abstained

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

### ADSL / llm: 27 variables abstained

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

### ADAE / rules: 16 variables abstained

| variable | rationale |
|---|---|
| ASTDT | rule: no matching pattern, routed to human review |
| ASTDTF | rule: no matching pattern, routed to human review |
| ASTDY | rule: no matching pattern, routed to human review |
| AENDT | rule: no matching pattern, routed to human review |
| AENDY | rule: no matching pattern, routed to human review |
| ADURN | rule: no matching pattern, routed to human review |
| ADURU | rule: no matching pattern, routed to human review |
| TRTEMFL | rule: no matching pattern, routed to human review |
| AOCCFL | rule: no matching pattern, routed to human review |
| AOCCSFL | rule: no matching pattern, routed to human review |
| AOCCPFL | rule: no matching pattern, routed to human review |
| AOCC02FL | rule: no matching pattern, routed to human review |
| AOCC03FL | rule: no matching pattern, routed to human review |
| AOCC04FL | rule: no matching pattern, routed to human review |
| CQ01NAM | rule: no matching pattern, routed to human review |
| AOCC01FL | rule: no matching pattern, routed to human review |

### ADAE / llm: 8 variables abstained

| variable | rationale |
|---|---|
| USUBJID | USUBJID is copied directly from ADSL. However, USUBJID is normally the key already present in ae and cannot be merged from adsl on itself without duplicate-record risk; if ae carries USUBJID this should be an assign on t |
| ASTDTF | ASTDTF is the day-imputation flag ('D') produced by the impute_dtc call that creates ASTDT; it is not independently derivable without that producer and its presence depends on day imputation, so it is flagged for human r |
| ASTDY | ASTDY is a conditional study-day computation (ASTDT>=TRTSDT then ASTDT-TRTSDT+1 else ASTDT-TRTSDT). The compute_var layer allows arithmetic and grouping parentheses only, so the conditional/missing-value guarded logic ca |
| AENDT | AENDT is derived from AE.AEENDTC. The spec text does not state an imputation rule for partial end dates, whereas impute_dtc requires an explicit highest_imputation and date_imputation. A conservative 'first' day imputati |
| AENDY | AENDY is a conditional study-day computation (AENDT>=TRTSDT then AENDT-TRTSDT+1 else AENDT-TRTSDT). The compute_var layer allows arithmetic and grouping parentheses only, so the conditional/missing-value guarded logic ca |
| ADURU | ADURU is conditional on ADURN being non-missing ('DAYS' when ADURN present). A pure literal assign loses the conditional guard on ADURN, and the conditional form is not expressible with the allowed arithmetic-only vocabu |
| TRTEMFL | TRTEMFL requires a conditional assignment (Y when ASTDT >= TRTSDT and non-missing, else N). The assign layer only supports a direct copy or a literal constant; the conditional/missing-guarded logic is not expressible wit |
| CQ01NAM | CQ01NAM requires a multi-condition string-matching rule (contains any of a list of substrings, OR SOC match with an excluded PT list). Substring/contains matching and the compound conditional with NULL default are not ex |

### ADLBC / rules: 14 variables abstained

| variable | rationale |
|---|---|
| AVISIT | rule: no matching pattern, routed to human review |
| AVISITN | rule: no matching pattern, routed to human review |
| PARAM | rule: no matching pattern, routed to human review |
| PARAMN | rule: no matching pattern, routed to human review |
| PARCAT1 | rule: categorisation breakpoints require human decision |
| R2A1LO | rule: no matching pattern, routed to human review |
| R2A1HI | rule: no matching pattern, routed to human review |
| BR2A1LO | rule: no matching pattern, routed to human review |
| BR2A1HI | rule: no matching pattern, routed to human review |
| ANL01FL | rule: no matching pattern, routed to human review |
| ALBTRVAL | rule: no matching pattern, routed to human review |
| ANRIND | rule: no matching pattern, routed to human review |
| BNRIND | rule: no matching pattern, routed to human review |
| AENTMTFL | rule: no matching pattern, routed to human review |

### ADLBC / llm: 13 variables abstained

| variable | rationale |
|---|---|
| AVISIT | Derivation describes a complex last-observation/last-assessment analyte-specific flag rule that requires human interpretation; no unambiguous layer mapping. |
| AVISITN | Derivation text is only the variable label with no source or rule; ambiguous mapping requires human review. |
| ADT | ADT is derived from LB.LBDTC, a character date; conversion requires an explicit imputation rule which is not provided in the spec. |
| PARAM | PARAM requires string concatenation of LBTEST, literal parentheses and LBSTRESU; string concatenation is not representable by the available layer vocabulary (no function calls permitted). |
| PARAMN | PARAMN requires an external numeric parameter-code lookup/codelist not provided in the spec. |
| PARCAT1 | Derivation text is only the variable label with no source or rule; ambiguous mapping requires human review. |
| BR2A1LO | BR2A1LO requires the ADY/BASE selection of the baseline AVAL and A1LO records (a filter-scoped ratio), which is not expressible with a plain column-wise compute_var; requires human decision on baseline record selection. |
| BR2A1HI | BR2A1HI requires the baseline-scoped ratio (AVAL / A1HI at baseline), needing filter-based baseline record selection not expressible with plain column-wise compute_var; requires human decision. |
| ANL01FL | ANL01FL is a max-value extreme flag on a non-standard analyte-specific variable (ALBTRVAL) with 'Y' true value; the flag logic could map to extreme_flag but the by_vars and analyte scoping are ambiguous, requiring human  |
| ALBTRVAL | ALBTRVAL requires max() over two arithmetic expressions involving LBSTRESN, ULN and LLN; function calls are rejected by compute_var and the layer vocabulary cannot express this, requiring human review. |
| ANRIND | ANRIND is a conditional (if/else) derivation mapping to 'L'/'H'/'N' categories; conditionals are not supported by the layer vocabulary, requiring human review. |
| BNRIND | BNRIND is a conditional (if/else) derivation mapping to 'L'/'H'/'N' categories over BASE; conditionals are not supported by the layer vocabulary, requiring human review. |
| AENTMTFL | Derivation describes a complex last-observation/last-assessment analyte-specific flag rule requiring human interpretation; no unambiguous layer mapping. |


## 9. Findings registered (`out/findings.json`)

Per the AGENTS.md improvement-loop convention, every ERROR/FAIL/MANUAL class observed gets a numbered finding with evidence. `severity`: **package** = code defect to fix; **demo** = pipeline configuration; **spec** = source-spec ambiguity; **oracle** = oracle convention the spec text does not mention. Resolved findings keep their record with `status`/`resolved_by`.

- **F-01 (package) [resolved by ee0f748] — impute_dtc dtc referencing a renamed-away column passes validate_ir() but fails at execution.** LLM/consensus chains for TRTSDT: merge_var(source=SVSTDTC -> target=TRTSDT) then impute_dtc(target=TRTSDT, dtc=SVSTDTC). After the merge, SVSTDTC no longer exists on ADSL (it landed as TRTSDT), so execution fails with 'column SVSTDTC is missing from source dataset ADSL'. validate_ir() does not track column provenance across steps, so this is only caught at execution - the fail-closed execution layer caught it, but the semantic gate could catch it earlier. _Evidence: out/exec_status_llm.csv (TRTSDT), out/exec_status_consensus.csv (TRTSDT)._
  - Suggested fix: Extend the semantic checks (ir_dependency_report / validate_ir) to flag step args that reference columns neither in the base nor produced by earlier steps under their referenced name.
  - Resolution: validate_ir() now runs renamed_column_problems(): merge_var/lookup_join renames (source != target) are tracked across steps, and later steps referencing the renamed-away column are rejected at the gate with the new column name in the message. Regression coverage: tests/testthat/test-renamed-columns.R. Same-class IRs are now caught inside the gate instead of at execution.
- **F-02 (demo) [resolved by this commit (pending hash)] — codelist_var executions fail without sources$mc (metacore object).** LLM chose codelist_var for RACEN/TRT01PN/TRT01AN; the layer renders metatools::create_var_from_codelist() which needs a metacore object named mc in the execution sources. The showcase did not build one from the define workbook, so these variables error at execution. This is a pipeline configuration gap, not an IR error - the IR is valid; the execution context was incomplete. _Evidence: out/exec_status_llm.csv (RACEN), out/exec_status_consensus.csv (TRT01PN, TRT01AN)._
  - Suggested fix: Build a metacore object from adam-pilot-5.xlsx codelists sheet in 00_ingest and pass it as sources$mc; or document codelist_var as out-of-scope for this showcase.
  - Resolution: 00_ingest now converts the workbook's Codelists sheet (long table ID/Term/Decoded Value) into mock_metacore() codelists and saves one executable metacore per dataset (out/mc_<ds>.rds, recorded in ingest_manifest.json); 03_execute passes it as sources$mc. Verified end to end: hand-built codelist_var IRs for RACEN/TRT01PN/TRT01AN execute against DM and match the oracle adsl.xpt on 100% of the 254 joined subjects. Note: the current cached ADSL LLM/consensus IRs abstain (needs_human) on these variables - LLM run-to-run variance (limitation 8) - so the fix is exercised by a direct probe and stands ready for any IR that selects codelist_var.
- **F-03 (package) — rules backend maps BMIBLGR1 categorisation text to compute_param->merge_var.** The rules classifier matched BMI keywords in 'BMIBLGR1="<25" if . < BMIBL <25...' and emitted compute_param+merge_var instead of categorize; execution then failed inside derive_param_computed (duplicate_records). Concrete instance of the documented keyword-fragility limitation: the rules backend is a zero-cost baseline, not a semantic parser. _Evidence: out/exec_status_rules.csv (BMIBLGR1), out/rules_vs_llm_layers.csv (BMIBLGR1 row)._
  - Suggested fix: Optional: add a categorisation keyword rule with higher priority than the BMI compute_param pattern; low value vs LLM backend, recorded for transparency.
- **F-04 (spec) — AGEGR1N boundary: all 11 mismatches are subjects aged exactly 80.** Spec text: 'AGEGR1 = 2 if AGE 65-80. AGEGR1 = 3 if AGE >80.' The LLM encoded breaks [0,65,80,Inf) right=FALSE, mapping AGE==80 to group 3; the oracle maps 80 to group 2 (reading '65-80' as inclusive). The spec text is self-contradictory at the boundary ('65-80' vs '>80'); 11/254 subjects sit exactly on it. This is spec ambiguity a human programmer would also have to query, not a clear package error. _Evidence: out/accuracy_llm.csv (AGEGR1N 95.7%), demo/_probe_mismatch.R output (all 11 mismatches at AGE==80)._
- **F-05 (oracle) — HEIGHTBL/WEIGHTBL disagreement is the oracle's undocumented 1-decimal rounding.** Raw agreement is 19.7%/8.7%, but both values trace to the same VS records the spec names (HEIGHT VISITNUM=1, WEIGHT VISITNUM=3 - both exist and match). The oracle stores 1-decimal rounded values; at oracle precision agreement is 98.8%/94.9%. The residual (~1-5%) is round-half edge cases. The derivation is semantically correct; the spec text never mentions rounding. _Evidence: out/accuracy_llm.csv (value_agree vs value_agree_oracle_prec columns), demo/_probe_rounding.R output._
- **F-06 (package) [resolved by this commit (pending hash)] — build_context() never states the target dataset, so LLM batches for non-ADSL datasets echo the wrong dataset token and fail alignment.** build_context() sends variable/label/type/origin/derivation/source pointers but NOT the spec's dataset column, and the system prompt's only example object says "dataset":"ADSL". For ADAE/ADLBC variables whose derivation text reads 'ADSL.TRT01A' etc., the model copies 'ADSL' into the dataset field; align_batch() then rejects the whole batch ('must contain exactly one matching dataset/variable for every requested row') and the demo's resilient fallback records those variables needs_human. The model literally cannot know the expected dataset token for batches of ADSL-sourced variables. On the ADAE full-spec run this degraded 14 variables in 4 batches (all the ADSL-sourced ones); AE-sourced variables were correctly tagged ADAE by the model and classified fine. Not fixed here because the fix is in R/classify_llm.R (package code, out of demo scope). _Evidence: out/llm_telemetry.json (ADAE runs.full.failed_batches: 4 batches, 14 variables, align/validation errors); demo/automation pilot run output (ADAE and ADLBC 8-variable probes both failed alignment with dataset=ADSL in the reply)._
  - Suggested fix: Include the target dataset in build_context()'s per-variable payload (or once in batch_prompt), so the model can emit the correct dataset token for non-ADSL datasets.
  - Resolution: build_context() now includes the spec's dataset column in every variable's payload (one-line change; batch_prompt() needed no change since it serializes build_context()). Regression tests: build_context carries the target dataset per variable, and align_batch accepts a non-ADSL batch when dataset tokens match while still rejecting mismatches (tests/testthat/test-classify.R); full suite FAIL=0 PASS=4815. Measured benefit on the ADAE full-spec rerun: needs_human 21 -> 8, LLM failed batches 4 -> 0 (the 14 ADSL-sourced variables that previously fell back are now classified); ADLBC: needs_human 46 -> 25, failed batches 16 -> 0. Execution of the newly classified variables surfaces a separate translation-semantics boundary - see F-10 (ADAE llm EXECUTED 26 -> 7 is not a regression of this fix).
- **F-07 (demo) [resolved by this commit (pending hash)] — DeepSeek chat-completions endpoint instability during the ADLBC expansion window; ADLBC LLM IR is a transport-failure fallback, not a classification.** The first ADLBC full-spec LLM run hit 'HTTP 400 Invalid assistant message' on every request from the first batch (a poisoned chat history cannot be retried usefully), so all 46 variables fell back to needs_human via the demo's resilient path. Minutes later the endpoint stopped responding to chat completions at all (repeated 300s timeouts with ~336 bytes received, while GET /models stayed 200). The cached out/ir_llm_adlbc.rds is therefore an API-outage artifact: needs_human=46 measures the outage, not translatability. Token accounting recorded 0 tokens / $0.0000 for the run. Mitigations now in place: 01_classify resets the chat (fresh history) on transport-level 'ellmer chat failed' errors before splitting chunks (chat_resets reported in telemetry), so transient chat-level failures self-heal on rerun. To redo the ADLBC LLM run once the endpoint is stable: delete out/ir_llm_adlbc.rds and rerun stage 01 with AA_DATASETS=ADLBC (cache-miss reruns only ADLBC). _Evidence: out/llm_telemetry.json (ADLBC runs.full: failed_batches=16 all 'ellmer chat failed: HTTP 400', tokens 0/0, cost_usd 0); out/ir_llm_adlbc.rds (all 46 rationale 'LLM batch failed IR validation after max_attempts'); connectivity probes during the run window (2x 300s timeout on chat completions, HTTP 200 on /models)._
  - Resolution: Chat completions stayed down through 6 classification probes between 2026-10-01 15:47 and 17:13 UTC (all 300s timeouts, ~336 bytes received, while GET /models returned 200), then recovered at 17:26 UTC. The caches were then deleted and the pipeline rerun: ADLBC full-spec LLM completed with 0 failed batches and 0 chat resets in 91.3s ($0.0135), needs_human 46 -> 25, EXECUTED 0 -> 4, oracle 9/9 compared variables at 100%. The current out/ir_llm_adlbc.rds is a real classification; the remaining needs_human count reflects genuine BDS/value-level abstentions (baseline flags, ratio-to-range derivations, PARAM semantics), not the outage.
- **F-08 (demo) — oracle compare reported 0% agreement for variables unpopulated on both sides.** ADAE MedDRA code variables (AELLTCD/AEPTCD/AEHLTCD/AEHLGTCD/AESOCCD) are entirely unpopulated in the pilot5 SDTM ae.xpt, so both the produced ADAE and the oracle carry all-NA columns. mean(equal) over zero non-NA pairs is 0, which rendered as '0.0% agreement' - visually a total disagreement when there were in fact no value pairs to compare (na_agree was 1.0). 04_oracle_compare now reports these as status 'all_missing' with no agreement figure. _Evidence: out/accuracy_llm_adae.csv (*CD rows before the fix: compared, 0.0%, note na_agree=1.00); NA-rate probe: 0/1191 non-NA in sdtm ae.xpt, produced ADAE and oracle adae.xpt alike._
- **F-09 (spec) — ADLBC BASE derivation text in the workbook is literally 'LB.LBSTNRHI'.** The Methods sheet text for ADLBC.BASE says 'LB.LBSTNRHI' (normal range high), and CHG is 'AVAL - BASE'. Executed literally, BASE receives the record's own upper normal limit (e.g. ALB 49.0) while the oracle's BASE is the baseline AVAL (38.0) - agreement 0.4%. The derivation text is verbatim from the submission workbook; the literal reading is almost certainly not the intended semantics, but the pipeline executes what the spec says and reports the disagreement. A human programmer would raise a query here. _Evidence: out/spec_adlbc.csv (BASE row, derivation 'LB.LBSTNRHI'), out/accuracy_rules_adlbc.csv (BASE 0.4%, CHG 0.4%); value probe: ours BASE=LBSTNRHI vs oracle BASE=baseline AVAL on the same records._
- **F-10 (package) [resolved by this commit (pending hash)] — post-F-06 LLM translates same-domain copies as merge_var(dataset_add=<base domain>), which fails closed on occurrence-level targets.** With the dataset token fixed, the model follows the system rule 'to bring a value from another dataset ALWAYS use merge_var' literally: ADAE variables copied from AE (AETERM, AELLT, AESEQ, 25 variables) became merge_var(dataset_add="ae", by_vars=STUDYID+USUBJID, mode=first) instead of assign. But ADAE's base IS ae, the by-keys are duplicated on occurrence-level data, and no order arg was given, so admiral::derive_vars_merged() fails closed with duplicate_records (25 execution errors). A second class (7 errors) merges columns from sources$adsl that the ADSL llm backend itself abstained on (TRTSDT, TRT01AN, RACEN, SAFFL, AGEGR1, AGEGR1N, TRTEDT) - cross-dataset variables can only be as complete as the producing backend's ADSL. Net effect on ADAE llm: needs_human 21 -> 8 but EXECUTED 26 -> 7 (validation FAIL 13 -> 58). Contrast: the rules backend's naive assign is semantically right for same-domain copies (ADAE rules EXECUTED=27, 20/20 compared variables at 100%). The model cannot see which domain seeds the target, so it cannot know assign was correct here. Recorded, not worked around: 03_execute now also supplies the base domain under its own name so these IRs execute as far as admiral's own duplicate-key guard allows. _Evidence: out/exec_status_llm_adae.csv (25x duplicate_records merge_var dataset_add=ae, 7x 'column ... missing from source dataset adsl'), out/ir_llm_adae.rds (AETERM/AESEQ merge_var steps), out/exec_status_llm_adlbc.csv, comparison with out/exec_status_rules_adae.csv (assign, EXECUTED=27)._
  - Suggested fix: Tell the model which domain seeds the target dataset (e.g. a base_domain field in build_context()/batch_prompt), so same-domain copies map to assign and merge_var is reserved for genuinely foreign datasets; optionally add an order arg requirement hint for occurrence-level merges.
  - Resolution: Fixed at the prompt-rule layer (vocabulary and golden hashes untouched): new numbered hard rule 5 in build_system_prompt() states that when source_dataset is the domain seeding the target (ADSL<-dm, ADAE<-ae, ADLBC<-lb) the column is already in the base and MUST be copied with assign, that merging a dataset into a target built from that same domain is forbidden (duplicate by-keys on occurrence data, duplicate_records), and that merge_var/lookup_join are reserved for OTHER datasets with by_vars(+order) uniquely identifying records in dataset_add. Placed in the numbered region (structural contract), not the convention block, so the neutral/minimal voter variants keep it - regression test asserts its key sentences in all three variants; full suite FAIL=0 PASS=4820. Measured on the ADAE/ADLBC reruns (0 failed batches, $0.0105/$0.0084): ADAE llm EXECUTED 7 -> 32, ERROR 40 -> 15, validation FAIL 58 -> 33, oracle 27 compared / 25 full-match / 96.3% mean; ADLBC llm needs_human 25 -> 13, EXECUTED 4 -> 22, oracle 21 compared / 19 full-match / 90.5% mean. duplicate_records errors: 25 -> 0. Remaining ADAE errors are honest dependency cascades (7x ADSL-llm-abstained columns, AOCC*/ADURN upstreams abstained); remaining ADLBC errors include 3 hallucinated source column names (SAF01FL/DSR01AEFL/COM01P24FL) that the fail-closed execution layer caught.

## 10. Limitations (read this before quoting any number above)

1. **Population/parameter subsetting is not automated.** Each produced dataset starts from its full SDTM base domain (ADSL from DM: all screened subjects; ADAE from AE: all collected events; ADLBC from LB: all 43 lab test codes); the oracles are subsetted (ADSL 254 randomized subjects, ADAE/ADLBC correspondingly). Row-level agreement is only computed on the join.
2. **Vocabulary gaps are hard boundaries.** The layer vocabulary has no conditional/windowing layers; derivations like COMP8FL/COMP16FL/COMP24FL (visit-window existence checks), EFFFL (cross-dataset existence), CUMDOSE (arm-conditional dose logic), ADAE occurrence flags (AOCCFL and siblings: subset-sort-first-record logic) or ADTTE-style CNSR can only abstain or be approximated. More LLM voters cannot fix a vocabulary hole (DESIGN.md section 11, item 5).
3. **The rules backend is keyword-fragile.** It matches English phrases; paraphrase the spec and its output changes. It is a zero-cost baseline, not a claim of understanding.
4. **The evals corpus is self-scoring** (`inst/evals/spec-to-ir.jsonl` expected values were generated by the rules backend). It pins current behavior as contract; it is not an oracle (DESIGN.md section 11, item 2).
5. **IR agreement ≠ double programming.** Rules/LLM agreement and 3-sample consensus measure translation consistency before execution, with all voters reading the same spec text (DESIGN.md section 11, item 1).
6. **Oracle differences may be spec ambiguity, not package error.** Where a produced value disagrees with the oracle, the spec text itself is often ambiguous (e.g. CUMDOSE's arm-conditional rule, ADAE imputation rules described only in prose); a human programmer would also have to ask. Disagreement rates here are not error rates.
7. **Programs are UNGATED DRAFTs.** No human approval gate covers these artifacts; they are demonstration output, not release-grade deliverables (DESIGN.md section 11, item 4).
8. **Single model, three datasets, and stochastic.** Numbers are for DeepSeek `deepseek-chat` on pilot5 ADSL/ADAE/ADLBC only; they do not transfer to other models or datasets without re-measurement. LLM output also varies run to run at temperature defaults: across the two full ADSL runs behind this report's development, the full-spec needs_human count moved 24 -> 22 and the rules/LLM layer-chain agreement 78% -> 71% — run-to-run translation variance is exactly what the consensus mode in section 5 exists to measure and contain.
9. **Value-level metadata is out of scope.** The workbook's `ValueLevel` sheet (15 rows, all ADADAS) carries where-clause derivations (`PARAMCD EQ ...`) that the flat spec extraction cannot express; no dataset in this run uses it, and ADADAS/ADQSADAS/ADTTE are not attempted.
