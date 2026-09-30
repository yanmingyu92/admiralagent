# admiralagent 设计文档

Spec-Driven ADaM Code Generation with LLM-Translated Layers

## 1. 核心思想

**LLM 不写代码。LLM 只做翻译：把 spec 的自然语言派生描述翻译成封闭词汇表内的"层"（Layer IR），由确定性编译器生成可执行 admiral 代码与验证注释。**

```
┌─────────┐   ┌──────────────┐   ┌──────────────┐   ┌───────────────┐
│ P21 spec │ → │ 确定性解析    │ → │ LLM 逐变量翻译 │ → │ 确定性编译     │
│ (xlsx)   │   │ metacore     │   │ spec文本→IR   │   │ IR→admiral R  │
└─────────┘   └──────────────┘   └──────────────┘   └───────────────┘
                                     │  JSON (封闭词汇)   │ 脚本+CHECK注释
                                     ↓                   ↓
                                validate_ir()       run_validation()
                                (schema+语义)        (确定性验证门)
                                     └────────┬──────────┘
                                              ↓
                                    write_artifact() → 脚本 + sidecar(JSONL 审计)
```

为什么这样切分：

| 职责 | 承担者 | 理由 |
|---|---|---|
| 理解 spec 自由文本 | LLM | 唯一非确定性的部分，LLM 擅长 |
| 选 admiral 函数 + 参数 | LLM → 封闭 IR | 词汇表受控，可 schema 校验，可审计 |
| 写 R 代码（含 exprs() 等易错点） | 确定性模板 | 消灭 LLM 语法幻觉；同 IR 必得同代码 |
| 验证 | 确定性检查 | PASS/FAIL 可证明，GxP 叙事成立 |
| 隐私 | schema-only 上下文 | LLM 永远看不到患者数据 |

## 2. Layer IR（中间表示）

每个 spec 变量 → 一个 Variable IR：

```json
{
  "dataset": "ADSL",
  "variable": "TRTSDTM",
  "steps": [
    {"layer": "merge_var",   "args": {"target": "TRTSDTM", "source": "EXSTDTM", "dataset_add": "ex", "by_vars": ["STUDYID","USUBJID"], "order": ["EXSTDTC"], "mode": "first", "filter": "EXDOSE > 0"}},
    {"layer": "impute_dtc",  "args": {"target": "TRTSDTM", "dtc": "EXSTDTC", "output_class": "dtm", "highest_imputation": "M", "date_imputation": "first"}}
  ],
  "confidence": 0.9,
  "needs_human": false,
  "rationale": "First dose datetime per spec derivation text",
  "spec_origin": "<spec 原文，逐字保留（进程内 API）；MCP 入口处替换为 origin:<hex> 摘要>"
}
```

要点：
- `steps` 是层管线（先 merge 后 impute 是常见链）
- `confidence` + `needs_human`：低置信/歧义变量进入人工队列，**宁可弃权不可编造**
- `spec_origin` 逐字保留 spec 原文，写进产物注释与 sidecar（溯源）。注意这条逐字保留
  只适用于进程内 API（`classify_variables` → `render_program` → sidecar），在那里它是
  溯源的承重结构；在 MCP 边界上，`spec_origin` 与 `rationale` 两个自由文本字段都在
  入口处（`mcp_redact_ir()`）被固定长度摘要替换——`origin:<16 位 xxhash64>` /
  `rationale:<hex>`——客户端自由文本不会回显进响应、生成代码或 sidecar
- LLM 的输出空间 = 层注册表的笛卡尔积，除此之外的一切都会被 `validate_ir()` 拒绝

## 3. 层注册表（单一事实源）

`R/layers.R` 中的 `aa_layers()` 是唯一事实源，每层定义：

- `fn`: admiral/metatools 函数
- `args` / `required`: 参数及类型（JSON-schema 语义）
- `render(args, dataset)`: 确定性代码渲染
- `checks`: 该层触发的验证检查 id（→ CHECK 注释 + 可执行检查）
- `rank`: 程序内排序优先级（merge → impute → duration → compute → flag → codelist → assign）

### 层词汇表 v1

| layer | admiral 函数 | 典型场景 |
|---|---|---|
| `assign` | `dplyr::mutate` | CRF 直拷 / 常量 |
| `merge_var` | `derive_vars_merged` | 从 SDTM 拉值（首次给药日期） |
| `lookup_join` | `derive_vars_merged_lookup` | VSTESTCD→PARAMCD 查表 |
| `impute_dtc` | `derive_vars_dtm/dt` | --DTC → *DTM/*DT 插补 |
| `duration` | `derive_vars_duration` | AGE、治疗时长 |
| `compute_param` | `derive_param_computed` | BMI/MAP（公式 token ⊆ parameters 白名单） |
| `summary_record` | `derive_summary_records` | AVERAGE 汇总记录 |
| `extreme_flag` | `derive_var_extreme_flag`（可包 `restrict_derivation`） | ABLFL 基线标记 |
| `codelist_var` | `metatools::create_var_from_codelist` | RACE→RACEN |
| `obs_number` | `derive_var_obs_number` | 分析序号 |

## 4. 生成产物形态

每个变量一个产物文件（vibe-widget 模式：确定性哈希 + sidecar）：

```
gen/
├── adsl__trtsdtm__a1b2c3d4.R        ← 可执行 admiral 代码 + CHECK 注释
├── adsl__trtsdtm__a1b2c3d4.json     ← sidecar: backend/model/IR/验证结果
└── adsl__program__e5f6a7b8.R        ← 组装后的完整程序（含 finalize 链）
```

代码块样例（产物正文）：

```r
# ---- TRTSDTM | step 1/2: merge_var -----------------------------------
# Spec origin: "Earliest EXSTDTC among EX records with EXDOSE > 0"
# Agent rationale: first qualifying exposure datetime
# Confidence: 0.90
# CHECK: 关键键合并后行数不增加（USUBJID 唯一性保持）
# CHECK: TRTSDTM 无全缺失
adsl <- adsl |>
  admiral::derive_vars_merged(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(EXSTDTC),
    mode = "first",
    new_vars = exprs(TRTSDTM = EXSTDTM),
    filter_add = EXDOSE > 0
  )
```

sidecar 字段（`sidecar_fields()` 的完整输出）：`artifact`, `package_version`,
`backend`（"llm"|"rules"）, `model`, `ir`, `validation`, `created_at`, `disclaimer`。
审计日志 `admiralagent_log.jsonl` 追加每次运行（哈希链式 JSONL，篡改可由 `verify_log()`
检出）。`execute_ir()` / `execute_study()` 在日志开启时每次调用**自动**追加恰好一条
`run_manifest` 记录（R/包版本及其来源、操作者、源数据摘要、模型参数、gate 是否强制），
与该次运行的逐变量 `execute_variable` 记录共享 `run_id`。对经由这两个入口执行的运行
再手动调用 `log_run_manifest()` 会产生重复记录；手动调用只用于未经它们执行的运行。

## 5. 双后端分类器（内置 A/B 评测）

- `backend = "rules"`：透明关键词启发式，零依赖、确定性、永远可用 → **基线 + 回退**
- `backend = "llm"`：ellmer 结构化抽取 + 校验-重试回路 → 上位替代

同一 spec 跑两个后端即可量化 LLM 增益（accuracy vs spec 评审员标注）。

## 6. 安全模型

1. **封闭词汇**：IR 校验失败 → 拒绝生成（不猜）
2. **弃权通道**：`needs_human` 变量不生成代码，进 review 队列（如分组切点必须人定）
3. **隐私**：`build_context()` 只发 schema + spec 文本，永不发数据行
4. **公式白名单**：compute_param 的公式 token 必须出现在 parameters 里
5. **确定性复现**：加载已提交产物零 LLM、零 API key；IR 相同 → 代码相同
6. **产物即草稿**：所有生成代码头部强制 DISCLAIMER：starting point, human review required before submission
7. **验证对象是 IR**：被校验、被签署、被归档的产物是 IR 本身——不是生成的代码，
   更不是 LLM 的轨迹。LLM 永远不写 R 代码；代码只是 IR 的确定性投影

## 7. 路线图

- v0.1 ✅：ADSL 10 层词汇表 + 双后端 + 产物/审计
- v0.2 ✅：真实数据闭环（pharmaversesdtm + oracle 精确度矩阵）、reviewer loop、
  evals 语料库（24 案例）、拓扑排序、admiral 版本守卫、幂等执行 execute_ir、
  mock_metacore（RACEN 闭环）、LLM 多采样共识、临时变量卫生
- v0.3 ✅：BDS/ADVS（oracle AVAL 100%）+ ADTTE 基础链、词汇 15 层
  （+compute_var/categorize/date_shift/dtm_to_dt）、MCP server
  （5 工具：classify/validate/render/dependency/evals）、CI workflows、
  R CMD check 0 error/0 warning/0 note、roxygen 全文档 + vignette
- v0.4（待办）：真实 P21 vendor spec 适配、ADLB/ADTTE 完整（derive_param_tte）、
  LLM evals 后端标定（多模型）、GitHub 开源发布（push 后 CI 生效）
- v0.5 ✅：语义规范化层 `R/canonical.R` —— `canonical_variable_ir()` 给出"一个派生
  一个语义形式"，私有中间列做 alpha 重命名（rules 的 EXST_TRTSDTM 与 LLM 的 EXSTDTM
  视为同一语义）；层注册表新增 `defaults` 字段，省略参数与显式写出的同一参数比较相等
  （`apply_layer_defaults()`）；`ir_fingerprint()` 提供三级指纹（abstention /
  layer_chain / full）用于跨后端投票与分歧定位；`canonical_ir()` 对参数名排序，
  `artifact_hash()` 不再随参数书写顺序变化

## 8. MCP 表面：响应模式与自由文本摘要

MCP server（stdio，5 工具）与进程内 API 共享全部确定性门，但在边界上有三条
自己的响应规则（实现见 `R/mcp.R`，工具描述字符串与之同步）：

1. **自由文本摘要**：所有接受或产出 IR 的工具都经过 `mcp_redact_ir()`，
   `spec_origin` 被替换为 `origin:<16 位 xxhash64>`、`rationale` 被替换为
   `rationale:<hex>`。生成代码注释里的 "Spec origin" / "Agent rationale" 因此
   携带摘要而非提交文本；`artifact_hash()` 也是对摘要后的 IR 计算的。
2. **`aa_render_program` 响应没有 `warnings` 字段**：`render_program()` 在
   `check_admiral_compat()` 报告版本冲突时直接报错（设计如此），该字段只可能
   永远为空，因此被删除，而不是留下一个客户端会错误信任的信号。
3. **`aa_classify` 在 `problems` 非空时返回 `ir = NULL`**：未过门的 IR 是诊断
   材料，不是交付物；不给客户端把被拒 IR 当可用输出的机会。

## 9. 渲染器接缝（多语言，A12）

- `render_program(ir, backend_label, finalize, language = "r", gate)`：
  `language` 是第 4 个参数，默认 `"r"`；`"sas"` / `"python"` 是已注册但未实现的
  目标，渲染时报 `NotImplemented` 并逐个点名该 IR 中没有对应渲染器的层。
- `quote_literal(x, language)` 取代了旧的 `q_chr()`：字面量引号规则是逐语言决策
  （R 用 `encodeString()`，SAS 单引号加倍，Python 反斜杠转义），不再是 JSON
  序列化的副作用。
- 层注册表新增 `products()`（该层产出哪些列/参数）与 `predicates` 钩子；filter
  类参数在文本之外还能给出语言中立的谓词 AST（`step_predicates()`，由注册表 +
  step args 派生，IR schema 不变）。
- `aa_layers()[[l]]$render` 是带类闭包（`aa_renderset`）：既可像从前一样直接调用
  （R 路径 byte-identical），也可按语言下标取渲染器（`$render[["sas"]]`）。
- `render_study()` 存在但为内部函数（@noRd）：按 `deliverable_order()` 拓扑序
  每个 deliverable 渲染一个程序，外加一个 driver 脚本；deliverable 环报错点名。

## 10. 第二种 IR 类型：分析结果（A14）

- `aa_analysis_ir`（TLF 统计结果）与 `aa_variable_ir`（ADaM 派生）并列，拥有
  自己的封闭运算词汇表 `aa_operations()`（n/count/pct/mean/sd/median/q1/q3/
  min/max），如同 `aa_layers()` 之于派生（AGENTS.md 规则 1 的镜像）。
- 调度器通过 S3 泛型 `ir_products()` / `ir_refs()` / `ir_rank()` 与 IR 类型解耦：
  `dependency_graph()` 只问"产出什么键、消费什么键、rank 多少"。ADaM 方法委托
  原有闭包，ADaM 路径与接缝出现前 bit-identical。
- `aa_layers()` **刻意未扩展**：分析产生新的结果对象，不是对输入表的列变换，
  硬塞成层需要改写全部 15 个渲染闭包。CDISC ARS 是序列化目标（sink format），
  不是 IR 的来源。全部内部（no @export）。

## 11. 诚实性边界（读者必须知道的五件事）

1. **IR 级 agreement 不是双程编程**：`run_agreement()`（R/evals.R）度量的是
   执行之前、多个 voter 对同一段 spec 自由文本的独立**翻译**一致性。每个 voter
   读的是同一段文本，spec 本身的错误为所有 voter 共享；它不能替代对输出数据的
   独立双程编程。夸大这一点会摧毁监管可信度。
2. **evals 语料是回归语料，不是 oracle**：`inst/evals/spec-to-ir.jsonl` 全部
   24 个案例的 `expected_args` 由当时的 `rules` 后端输出生成，钉住的是"当前
   行为即契约"。引用它作为 validation 证据，等于系统在给自己打分。
3. **golden hash 与版本号耦合**：`pkg_ver()` 的 fallback `"0.1.0"`
   （`R/utils.R`）当前恰好等于 DESCRIPTION 的 Version，而测试中的 golden
   `artifact_hash` `84a18650` 是在包未安装（helper.R source R/*.R，走 fallback）
   时算出的。下一次版本号提升会移动 golden——即使没人碰哈希逻辑。run manifest
   记录 `package_version_source`，使历史运行自我标识"版本已知/版本猜测"。
4. **审批 gate 默认开启**：`AA_GATE_REQUIRED_DEFAULT <- TRUE`
   （R/artifacts.R）。开箱即强制拦截：无 gate 的 `write_program_artifact()`
   被拒绝，且拒绝本身写入审计日志。写未 gate 的产物需要显式退出——单次调用
   传 `require_gate = FALSE` 参数，或会话级
   `options(admiralagent.require_gate = FALSE)`。未 gate 的产物仍永久自我
   标识——.R 头部 UNGATED DRAFT banner、sidecar 与审计记录中的
   `release_grade` / `gate_enforced`、`read_artifact()` 拒绝自称已批准却无
   批准的 sidecar。默认姿态是"强制开，退出记录在案"。
5. **共模上限**：词汇表里没有条件/时间窗（conditional / windowing）层，像
   ADTTE 的 CNSR 这类派生会把所有 voter 逼进同样的弃权或同样的错映射。
   词汇覆盖是安全属性；voter 数量再多也补不了词汇表的洞。
