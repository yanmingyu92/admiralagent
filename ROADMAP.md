# admiralagent 系统性改进与推广路线图

> 目标：把「架构 A+、交付 C」的现状，系统推进为可开源、可复核、可被 agent 生态采纳的成熟包。
> 节奏：工程优先，后推广。推广启动门槛 = P0 + P1 完成。
> 定位：开源社区 + pharmaverse 为主线。

## 现状判词

- 架构（IR-first、fail-closed、三层 agent 接口、诚实性边界）：保持，不动。
- 交付面：无 git、CI 未实证、helper.R 遮蔽安装产物、docs drift 慢性病、DESCRIPTION 卫生问题。
- 推广面：README 自述 "not yet"，HANDOFF.md 注明开源前需删除，无 pkgdown。

---

## P0 — 交付面止血（第 1 周）

目标：版本控制 + 可独立复核的测试 + 元数据卫生。

- [x] E1 `git init` + 初始提交；`.gitignore`（Output/、.Rhistory、.Renviron 等）
- [x] E2 DESCRIPTION 卫生：删除空值 `Config/Depends:` 尾字段；改标准 `RoxygenNote:` 字段
- [x] E3 `.Rbuildignore` 增加 `^\.agents$`（避免审计快照打进 tarball）
- [x] E4 `tests/testthat/helper.R` 修复：`test_check()` 路径下不再全量 source `R/*.R` 遮蔽已安装命名空间；dev 模式由 `ADMIRALAGENT_DEV_SOURCE=1` 显式开启（testthat.yaml 已同步）
- [x] E5 drift 三处即修：`build_system_prompt()` 双 "5." 编号；`demo/mcp_setup.md` 已删除的 `warnings` 字段；`R-CMD-check.yaml` 头部过时注释
- [x] E6 `AGENTS.md` 规则 1 同步：已涵盖第二种 IR（`aa_analysis_ir` / `aa_operations()`）
- [x] E7 用 Rscript 全量跑测试，确认修复后仍全绿（FAIL 0 | WARN 7 | SKIP 2 | PASS 4766，与基线一致）

## P1 — Drift 根治 + 门禁收紧（第 2 周）

目标：单一事实源原则从代码贯彻到文档与 prompt。

- [x] D1 单一事实源核查与 drift 门禁：词汇表本就由 `build_system_prompt()` 经 `layer_docs()` 运行时注入（无手抄副本需生成）；落地为机器校验——新增 `tests/testthat/test-docs-consistency.R`：SKILL.md/AGENTS.md/README/mcp_setup.md 引用的 `admiralagent::fn` 必须已导出；mcp_setup.md 工具名与 inputSchema 字段必须与 `mcp_tool_specs()` 一致；输出字段钉住现行契约
- [x] D2 golden hash 版本无关化：`artifact_hash()` 输入去掉 `pkg_ver()`（版本改由 sidecar/manifest 溯源），golden `84a18650` → `6aea851a` 同 commit 显式迁移；DESIGN.md §11.3 第 3 条标记已解决；全量测试全绿（4766 PASS）
- [x] D3 CI 门禁收紧至 `error-on: "warning"`：实证清零两个真实 WARNING（`classify_variables_llm` 的 `prompt_variant` 缺 @param；tests 未声明 dplyr/haven/pharmaversesdtm/pharmaverseadam 依赖，已入 Suggests）；其余为本地无 pandoc 的构建伪影，CI 不出现
- [x] D4 接入 covr（test-coverage.yaml，覆盖安装产物路径，Codecov 待配 secret）+ lintr（差异门禁：只 lint 变更文件，`.lintr` 记录豁免理由，全树清零列为 P2 目标）
- [x] D5 pkgdown 站点骨架（`_pkgdown.yml` + workflow；仓库公开前为手动触发，见 M2 门禁注释）

## P2 — 架构轻装（第 3–4 周）

目标：降低维护面，把私有实现换成生态标准组件。

- [x] A1 MCP 层评估迁移到 mcptools + 可复用加固 wrapper（入站限制、错误目录、`mcp_redact_ir()` 抽为独立组件）；若保留私有 server，须写明理由 — **评估完成，结论 hybrid：保留私有 server**（加固即产品：预解析字节上限/参数树限额/固定错误目录/IR 脱敏都活在 JSON-RPC 层，mcptools 无对应钩子；且其 Imports 含 ellmer/nanonext，违反零强依赖红线；517 行进程内安全契约测试会退化为进程级集成测试）。完整理由清单与复评触发条件见 `.agents/mcptools-assessment.md`（本地笔记）
- [ ] A2 API 面收敛：导出审查，内部函数收回；IR 对象评估 S7 化（工具签名自描述）— **审查完成，收回未实施**：NAMESPACE 实测 45 个 export + 1 个 S3method（"43" 是 P3 V1 前的旧数）；四档分类（A 核心 16 / B 合理 13 / C 收回候选 8 / D 需讨论 8）、C 档每候选的文档同步清单见 `.agents/p2-a2-export-review.md`（本地笔记）；S7 化评估结论**不建议列入 A2**（与 fail-closed 一次报全语义冲突、破 Imports 最小化红线、golden hash 稳定性风险；重开触发条件已记录）。收回实施属公开 API 变更，待用户确认后按清单执行
- [x] A3 `R/artifacts.R`（1230 行）拆分为 sidecar / audit-log / gate / manifest 四个模块 — 已完成机械拆分（`R/artifact_write.R` / `R/audit_log.R` / `R/gate.R` / `R/manifest.R`），61 个符号逐一核对各定义一次，零行为变更，全量测试 4801 绿
- [x] A4 `.agents/`（HANDOFF + 快照）从 git 全历史移除（filter-branch，开源前置条件）；本地保留、`.gitignore` 防再入库。注：因私有仓库 Actions 计费阻塞，仓库于 P1 后提前公开（ROADMAP 节奏调整，经用户确认）

## P3 — 差异化资产（第 2 个月）

目标：把别人最难抄的东西做成公开资产。

- [x] V1 evals 从内部回归语料升级为公开可执行的验证器 API + 文档（L4 资产）— `run_agreement()` / `agreement_overstatement()` 已导出（含 `print.aa_agreement()`），roxygen 内置诚实性边界（自评分语料 ≠ oracle、IR agreement ≠ 双程编程），NAMESPACE +3、man +3、测试 +12（4801 绿）
- [ ] V2 真实 P21 vendor spec 适配 — **部分达成**：showcase 已跑通 pilot5 真实递交 define 工作簿（P21 风格 xlsx）的 ADSL/ADAE/ADLBC 三数据集（spec 构建 `build_spec_from_define_xlsx()`，codelist 摄取 `mock_metacore()`）。距"真实 P21 vendor spec 适配"仍缺：① define.xml 直接摄取（当前仅 xlsx 工作簿一种 layout，`R/define.R`）；② 多家 vendor spec 的 layout 差异覆盖；③ value-level metadata 机器化表达（ValueLevel 表，showcase 记录为边界 F-09/REPORT 限制 9）；④ 第二项研究复现（当前仅 pilot5 单一研究）
- [ ] V3 TLF 域对接评估：与 cards/gtsummary 的 ARD 衔接（ARD 是天然 sink，见 .agents/ARS-SPIKE.md 结论）
- [ ] V4 起草「agent-ready R 包成熟度模型 L0–L4」白皮书——生态话语权的支点
- [ ] V5 条件层（conditional）词汇 — **评估完成，未实施**（词汇扩张 = 攻击面扩张，实施前需用户确认）：showcase 实测 9 个 `Y if <condition>` 类弃权（SAFFL/ITTFL/DISCONFL/DSRAEFL/EOSSTT/COMP*FL），候选层 `assign_conditional`（复用 filter 子语言、纯增量、golden `6aea851a` 无需迁移）确定可转 4/9，另 5 个需存在性/missingness 原语（建议阶段 2 独立评估）；完整设计/安全分析/实测清单见 `.agents/conditional-layer-assessment.md`（本地笔记）

## P4 — 推广（P0+P1 完成后启动，soft-launch → hard-launch）

### Soft-launch（P1 完成时）

- [x] M1 GitHub 仓库公开（提前至 P1 后：私有 Actions 计费阻塞所致）：README 加 badges（R-CMD-check、testthat）+ GitHub 安装说明；demo GIF 待补
- [x] M2 pkgdown 站点上线：https://yanmingyu92.github.io/admiralagent/（gh-pages 自动部署，push 触发已启用）
- [x] M2b CDISC pilot5 自动化 showcase：`demo/automation/` 一键管线（00 ingest → 05 report，rules + DeepSeek 双后端，真实递交 spec/SDTM/oracle），`REPORT.md` 真实数字 + findings 登记；pkgdown article `articles/cdisc-pilot-showcase.html` + README 入口（"See it run on real CDISC pilot data"）。**已扩域**：ADSL → ADSL/ADAE/ADLBC 三数据集（`AA_DATASETS` 驱动）；findings F-01~F-10，其中 F-01（validate_ir 列改名追踪，`ee0f748`）/F-02（define 工作簿 Codelists → metacore）/F-06（build_context 带 dataset）/F-07（chat 重置韧性）/F-10（同域基座列 assign 规则）已修复并回归，F-03~F-05/F-08/F-09 为如实记录的边界
- [x] M3 个人 r-universe 准备：`yanmingyu92/universe` 仓库 + packages.json 已建；**待用户操作**：安装 R-universe GitHub App（https://github.com/apps/r-universe）到该仓库后 https://yanmingyu92.r-universe.dev 生效；pharmaverse 收录列入 M7

### Hard-launch（P2 完成时）

- [ ] M4 英文博客：「LLM Never Writes R Code: Constrained IR for GxP Code Generation」——主打架构主张 + 诚实性边界（投 R-bloggers / Posit Blog 客座）。**终稿已落盘** `docs-drafts/blog-llm-never-writes-r.md`（数字与 pilot5 三数据集 showcase REPORT.md 一致，含 F-01 门前移叙事与 F-06→F-10 改进回路案例；文末 R-bloggers/Posit 投稿路径，用户操作步骤已标注 [USER ACTION]，待投稿）
- [ ] M5 中文内容：知乎/小红书/公众号同步（架构故事 + 精度表诚实叙事，差异化记忆点）。**知乎成稿已落盘** `docs-drafts/m5-zhihu-article.md`（大纲 `docs-drafts/m5-zh-content-outline.md`，数字与最新 REPORT.md 一致，待发布）
- [ ] M6 会议投稿：R/Pharma（通常 10–11 月）、posit::conf、useR!——主题即「agent-ready 临床编程」
- [ ] M7 pharmaverse 社区渗透：Slack 自我介绍、admiral Discussions 发设计帖、申请列入 pharmaverse 包清单
- [ ] M8 LinkedIn 英文帖 + 作者个人叙事（design doc 双语优势）

### 北极星指标

- GitHub stars / 外部 issue 与 PR 数 / r-universe 下载量
- 被其他包或 skill 引用（agent 生态采纳度）
- 会议接受 / 药企试点线索数

---

## 红线（全程不变）

- LLM 永远不写 R 代码；IR 是唯一被校验签署的对象
- fail-closed：校验失败不猜不修
- 患者数据永不进 prompt/日志/sidecar
- 诚实性边界：不夸大 agreement、evals、覆盖率（DESIGN.md §11）
