# admiralagent 系统性改进与推广路线图

> 目标：把「架构 A+、交付 C」的现状，系统推进为可开源、可复核、可被
> agent 生态采纳的成熟包。 节奏：工程优先，后推广。推广启动门槛 = P0 +
> P1 完成。 定位：开源社区 + pharmaverse 为主线。

## 现状判词

- 架构（IR-first、fail-closed、三层 agent
  接口、诚实性边界）：保持，不动。
- 交付面：无 git、CI 未实证、helper.R 遮蔽安装产物、docs drift
  慢性病、DESCRIPTION 卫生问题。
- 推广面：README 自述 “not yet”，HANDOFF.md 注明开源前需删除，无
  pkgdown。

------------------------------------------------------------------------

## P0 — 交付面止血（第 1 周）

目标：版本控制 + 可独立复核的测试 + 元数据卫生。

E1 `git init` + 初始提交；`.gitignore`（Output/、.Rhistory、.Renviron
等）

E2 DESCRIPTION 卫生：删除空值 `Config/Depends:` 尾字段；改标准
`RoxygenNote:` 字段

E3 `.Rbuildignore` 增加 `^\.agents$`（避免审计快照打进 tarball）

E4 `tests/testthat/helper.R` 修复：`test_check()` 路径下不再全量 source
`R/*.R` 遮蔽已安装命名空间；dev 模式由 `ADMIRALAGENT_DEV_SOURCE=1`
显式开启（testthat.yaml 已同步）

E5 drift
三处即修：[`build_system_prompt()`](https://yanmingyu92.github.io/admiralagent/reference/build_system_prompt.md)
双 “5.” 编号；`demo/mcp_setup.md` 已删除的 `warnings`
字段；`R-CMD-check.yaml` 头部过时注释

E6 `AGENTS.md` 规则 1 同步：已涵盖第二种 IR（`aa_analysis_ir` /
`aa_operations()`）

E7 用 Rscript 全量跑测试，确认修复后仍全绿（FAIL 0 \| WARN 7 \| SKIP 2
\| PASS 4766，与基线一致）

## P1 — Drift 根治 + 门禁收紧（第 2 周）

目标：单一事实源原则从代码贯彻到文档与 prompt。

D1 单一事实源核查与 drift 门禁：词汇表本就由
[`build_system_prompt()`](https://yanmingyu92.github.io/admiralagent/reference/build_system_prompt.md)
经
[`layer_docs()`](https://yanmingyu92.github.io/admiralagent/reference/layer_docs.md)
运行时注入（无手抄副本需生成）；落地为机器校验——新增
`tests/testthat/test-docs-consistency.R`：SKILL.md/AGENTS.md/README/mcp_setup.md
引用的 `admiralagent::fn` 必须已导出；mcp_setup.md 工具名与 inputSchema
字段必须与
[`mcp_tool_specs()`](https://yanmingyu92.github.io/admiralagent/reference/mcp_tool_specs.md)
一致；输出字段钉住现行契约

D2 golden hash
版本无关化：[`artifact_hash()`](https://yanmingyu92.github.io/admiralagent/reference/artifact_hash.md)
输入去掉 `pkg_ver()`（版本改由 sidecar/manifest 溯源），golden
`84a18650` → `6aea851a` 同 commit 显式迁移；DESIGN.md §11.3 第 3
条标记已解决；全量测试全绿（4766 PASS）

D3 CI 门禁收紧至 `error-on: "warning"`：实证清零两个真实
WARNING（`classify_variables_llm` 的 `prompt_variant` 缺 @param；tests
未声明 dplyr/haven/pharmaversesdtm/pharmaverseadam 依赖，已入
Suggests）；其余为本地无 pandoc 的构建伪影，CI 不出现

D4 接入 covr（test-coverage.yaml，覆盖安装产物路径，Codecov 待配
secret）+ lintr（差异门禁：只 lint 变更文件，`.lintr`
记录豁免理由，全树清零列为 P2 目标）

D5 pkgdown 站点骨架（`_pkgdown.yml` + workflow；仓库公开前为手动触发，见
M2 门禁注释）

## P2 — 架构轻装（第 3–4 周）

目标：降低维护面，把私有实现换成生态标准组件。

A1 MCP 层评估迁移到 mcptools + 可复用加固
wrapper（入站限制、错误目录、`mcp_redact_ir()`
抽为独立组件）；若保留私有 server，须写明理由

A2 API 面收敛：43 个导出审查，内部函数收回；IR 对象评估 S7
化（工具签名自描述）

A3 `R/artifacts.R`（1230 行）拆分为 sidecar / audit-log / gate /
manifest 四个模块

A4 `.agents/`（HANDOFF + 快照）从 git
全历史移除（filter-branch，开源前置条件）；本地保留、`.gitignore`
防再入库。注：因私有仓库 Actions 计费阻塞，仓库于 P1 后提前公开（ROADMAP
节奏调整，经用户确认）

## P3 — 差异化资产（第 2 个月）

目标：把别人最难抄的东西做成公开资产。

V1 evals 从内部回归语料升级为公开可执行的验证器 API + 文档（L4 资产）

V2 真实 P21 vendor spec 适配（当前仅 mock spec + CDISC pilot1）

V3 TLF 域对接评估：与 cards/gtsummary 的 ARD 衔接（ARD 是天然 sink，见
.agents/ARS-SPIKE.md 结论）

V4 起草「agent-ready R 包成熟度模型 L0–L4」白皮书——生态话语权的支点

## P4 — 推广（P0+P1 完成后启动，soft-launch → hard-launch）

### Soft-launch（P1 完成时）

M1 GitHub 仓库公开（提前至 P1 后：私有 Actions 计费阻塞所致）：README 加
badges（R-CMD-check、testthat）+ GitHub 安装说明；demo GIF 待补

M2 pkgdown
站点上线：[https://yanmingyu92.github.io/admiralagent/（gh-pages](https://yanmingyu92.github.io/admiralagent/%EF%BC%88gh-pages)
自动部署，push 触发已启用）

M3 个人 r-universe 准备：`yanmingyu92/universe` 仓库 + packages.json
已建；**待用户操作**：安装 R-universe GitHub
App（[https://github.com/apps/r-universe）到该仓库后](https://github.com/apps/r-universe%EF%BC%89%E5%88%B0%E8%AF%A5%E4%BB%93%E5%BA%93%E5%90%8E)
<https://yanmingyu92.r-universe.dev> 生效；pharmaverse 收录列入 M7

### Hard-launch（P2 完成时）

M4 英文博客：「LLM Never Writes R Code: Constrained IR for GxP Code
Generation」——主打架构主张 + 诚实性边界（投 R-bloggers / Posit Blog
客座）

M5 中文内容：知乎/小红书/公众号同步（架构故事 +
精度表诚实叙事，差异化记忆点）

M6 会议投稿：R/Pharma（通常 10–11
月）、posit::conf、useR!——主题即「agent-ready 临床编程」

M7 pharmaverse 社区渗透：Slack 自我介绍、admiral Discussions
发设计帖、申请列入 pharmaverse 包清单

M8 LinkedIn 英文帖 + 作者个人叙事（design doc 双语优势）

### 北极星指标

- GitHub stars / 外部 issue 与 PR 数 / r-universe 下载量
- 被其他包或 skill 引用（agent 生态采纳度）
- 会议接受 / 药企试点线索数

------------------------------------------------------------------------

## 红线（全程不变）

- LLM 永远不写 R 代码；IR 是唯一被校验签署的对象
- fail-closed：校验失败不猜不修
- 患者数据永不进 prompt/日志/sidecar
- 诚实性边界：不夸大 agreement、evals、覆盖率（DESIGN.md §11）
