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

- [ ] E1 `git init` + 初始提交；`.gitignore`（Output/、.Rhistory、.Renviron 等）
- [ ] E2 DESCRIPTION 卫生：删除空值 `Config/Depends:` 尾字段；`Config/roxygen2/version` 改标准 `RoxygenNote: 7.3.x`
- [ ] E3 `.Rbuildignore` 增加 `^\.agents$`（避免审计快照打进 tarball）
- [ ] E4 `tests/testthat/helper.R` 修复：`test_check()` 路径下不得全量 source `R/*.R` 遮蔽已安装命名空间；保留 `test_dir` 开发模式开关（如环境变量 `ADMIRALAGENT_DEV_SOURCE=1`）
- [ ] E5 drift 三处即修：`build_system_prompt()` 双 "5." 编号（R/classify_llm.R:80,84）；`demo/mcp_setup.md` 已删除的 `warnings` 字段；`.github/workflows/R-CMD-check.yaml` 头部过时注释
- [ ] E6 `AGENTS.md` 规则 1 同步：A14 后已有第二种 IR（`aa_analysis_ir` / `aa_operations()`），「唯一事实源」表述需更新
- [ ] E7 用 Rscript（HANDOFF 记录的绝对路径）全量跑测试，确认修复后仍全绿

## P1 — Drift 根治 + 门禁收紧（第 2 周）

目标：单一事实源原则从代码贯彻到文档与 prompt。

- [ ] D1 `SKILL.md` / `AGENTS.md` / MCP 工具描述 / `build_system_prompt()` 的词汇表部分，全部从 `aa_layers()` 在构建时生成；加 CI 一致性测试（生成物 vs 源码，仿 roxygen2 `document()` 检查）
- [ ] D2 golden hash 改 `expect_snapshot()` + 版本无关规范化，消除版本耦合脆弱性（DESIGN.md §11.3 自述项）
- [ ] D3 CI 门禁评估收紧至 `error-on: "warning"`（先清零现有 7 个 warning，再收紧）
- [ ] D4 接入 covr 覆盖率 + lintr，纳入 CI
- [ ] D5 pkgdown 站点骨架（`_pkgdown.yml` + GitHub Pages workflow）

## P2 — 架构轻装（第 3–4 周）

目标：降低维护面，把私有实现换成生态标准组件。

- [ ] A1 MCP 层评估迁移到 mcptools + 可复用加固 wrapper（入站限制、错误目录、`mcp_redact_ir()` 抽为独立组件）；若保留私有 server，须写明理由
- [ ] A2 API 面收敛：43 个导出审查，内部函数收回；IR 对象评估 S7 化（工具签名自描述）
- [ ] A3 `R/artifacts.R`（1230 行）拆分为 sidecar / audit-log / gate / manifest 四个模块
- [ ] A4 删除 `.agents/snapshot-*`（有 git 后冗余，HANDOFF 自述可删）；开源前处理 `.agents/HANDOFF.md`（自述 "Delete this file before open-sourcing"）

## P3 — 差异化资产（第 2 个月）

目标：把别人最难抄的东西做成公开资产。

- [ ] V1 evals 从内部回归语料升级为公开可执行的验证器 API + 文档（L4 资产）
- [ ] V2 真实 P21 vendor spec 适配（当前仅 mock spec + CDISC pilot1）
- [ ] V3 TLF 域对接评估：与 cards/gtsummary 的 ARD 衔接（ARD 是天然 sink，见 .agents/ARS-SPIKE.md 结论）
- [ ] V4 起草「agent-ready R 包成熟度模型 L0–L4」白皮书——生态话语权的支点

## P4 — 推广（P0+P1 完成后启动，soft-launch → hard-launch）

### Soft-launch（P1 完成时）

- [ ] M1 GitHub 仓库公开：README 加 badges（R-CMD-check、coverage）、demo GIF、5 分钟 quickstart
- [ ] M2 pkgdown 站点上线（GitHub Pages）
- [ ] M3 提交至 r-universe（个人或 pharmaverse）

### Hard-launch（P2 完成时）

- [ ] M4 英文博客：「LLM Never Writes R Code: Constrained IR for GxP Code Generation」——主打架构主张 + 诚实性边界（投 R-bloggers / Posit Blog 客座）
- [ ] M5 中文内容：知乎/小红书/公众号同步（架构故事 + 精度表诚实叙事，差异化记忆点）
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
