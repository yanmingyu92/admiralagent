# 第二轮对抗性审计：交叉检查与修复

本轮对上一轮结果重新验证，确实发现了此前遗漏的注入与数据正确性问题。源码快照保存在 `before-src/`；以下复现均使用合成数据，没有执行恶意命令。工作目录没有 Git 元数据，因此使用 commit 式描述记录实际修改，不虚构提交号。

## 分级发现与修复

| 编号 / 级别 | 修复前可复现证据 | 已实施修复 |
|---|---|---|
| R2-01 BLOCKER | 合法父 IR 搭配另一个 `on='ex'` 的 step，`render_step()` 会输出 `system(...)`。外部数据集错误被过滤后，token 校验被绕过。 | `fix(codegen): bind each rendered step to its validated parent`：step 必须与 `v$steps[[i]]` 完全一致，i 必须在有效范围内。内部渲染仅由完整验证后的入口调用。 |
| R2-02 BLOCKER | sidecar 中字符串 `needs_human='true'` 被 `isTRUE()` 转成 FALSE，字符串 confidence 被转成数值；typed extraction 与 JSON、MCP、artifact 走不同归一化路径。 | `fix(ir): share lossless strict decoding across all ingress paths`：统一严格解码，不强制转换标量类型；拒绝重复/未知字段、冲突的 on、非同型数组；保持错误类型交由 gate 拒绝。 |
| R2-03 BLOCKER | 两行 spec 请求可接受只返回一个未请求的 X；部分多值/未知变量在 align_batch 中直接崩溃。 | `fix(llm): require exact dataset-variable batch identity`：先 gate，再检查条数、唯一性、完整键集合，合法重排按请求对齐；错误反馈到重试流程。 |
| R2-04 BLOCKER | 三次候选分别为 AGE+1、AGE+2、AGE+2，旧共识选择 AGE+1，因为只比较层名。 | `fix(consensus): vote on full derivation semantics`：签名包含所有 step 参数、过滤条件、模式、公式；参数字段排序规范化。不同规则不再伪装成一致，多数规则胜出，平票转人工复核。 |
| R2-05 BLOCKER | X=Y+1、Y=AGE+1，base 中 AGE=1、旧 Y=100；两项均 EXECUTED，X 却等于 101。 | `fix(dependencies): order every registry-declared input before consumption`：在 aa_layers 中登记输入，统一解析公式、过滤、日期、键及参数依赖；结果变成 Y=2、X=3。拒绝循环、重复变量和竞争输出，review-only 或尚未执行的变量不再充当可用输入。 |
| R2-06 BLOCKER | 即使 parent=baseenv()，缺失列 T 也会被当作 R 内置 TRUE，assign 成功返回错误数据。 | `fix(execute): check actual source columns before evaluation`：每步读取的列必须实际存在于显式 source data.frame；T/F/LETTERS 不能回退到环境常量。真正存在的同名列仍可用。 |
| R2-07 BLOCKER | 多步变量先写 TEMP，后一步报错，旧执行器仍保留 TEMP；后续变量可读旧的失败输出。 | `fix(execute): commit variable changes only after successful completion`：变量在临时环境内执行，全部成功才提交；失败回滚目标及源对象绑定，依赖失败输出的变量报告 ERROR。补充 imputation 旗标列与 dtc 冲突、computed paramcd 与输入参数冲突的拒绝规则。 |
| R2-08 BLOCKER | 阈值 1.23456789 被渲染成约 1.234568；边界两侧样本得到 a,a 而非 a,b。JSON 默认精度与 Inf→null 还会破坏 sidecar/MCP 往返。 | `fix(precision): preserve numeric boundaries across code and JSON`：代码数值使用 17 位精度；JSON 使用 digits=NA；仅在 breaks 采用明确的 Inf/-Inf 字符串哨兵；artifact 与 MCP 均保留有效数值。 |
| R2-09 BLOCKER | 非数字字符串默默变 NA；12:30+02:00 被读成 12:30 UTC，丢失两小时偏移；非标量单元格会取第一项。 | `fix(dataset-json): reject lossy cells and retain timezone instants`：非法数值、分数 integer、非法 boolean、嵌套单元格及重复列名明确拒绝；时区正确换算；部分/无法解析日期保持字符串。保留真实 pilot 的数值字符串和带空格 NA 哨兵兼容。 |
| R2-10 BLOCKER | 规则分类器把 X=AGE+1 截断成 X=AGE，产生可执行且错误的 IR。 | `fix(rules): require whole direct-assignment expressions`：赋值匹配覆盖完整表达式；算术或条件尾随转人工复核。只接受已识别的明确“实际与随机治疗无差异”说明，保住真实 TRT01A=TRT01P 回归。 |
| R2-11 BLOCKER | R 复数 confidence/days 被 is.numeric 接受，随后比较或 floor 发生异常；复数 step index 也产生晦涩错误。 | `fix(validation): reject complex and matrix-shaped numeric inputs`：数值字段使用实数向量校验，confidence/index 为有限实数标量；validate_ir 返回可读错误，拒绝复数表达式常量。 |
| R2-12 MAJOR | 改变变量顺序可改变生成程序/列顺序，但 artifact_hash 相同；sidecar 排序后不能恢复原程序顺序。 | `fix(artifacts): preserve execution-significant IR order`：canonical IR 保留变量与 step 顺序，hash 对顺序变化敏感；往返保持原顺序。 |
| R2-13 MAJOR | max_attempts/batch_size/samples 的 0、Inf、NA、非整数缺少一致边界；prompt 的低置信度人工复核要求未被 gate 实施。 | `fix(contracts): validate batch limits and enforce confidence review`：所有计数为有限正整数；confidence<0.7 且 needs_human=false 被拒绝。 |

关键证据：[最初探针](probes-before.log)、[通过修复前源码快照运行的扩展探针](extended-probes-before.log)。新回归位于 `tests/testthat/test-audit-round2.R`。所有相关规则同步进入 `build_system_prompt()`，语义/依赖检查和测试同步变更。

## 对抗性覆盖与交叉验证

- 新增 420 个固定种子样本，覆盖全部实际注册的 14 层。每个样本检查 validate_ir 不崩溃；接受的 IR 必须可渲染、可 parse，并经 canonical JSON 往返后保持渲染一致。
- 保留上一轮 320 个畸形 JSON 样本及全部注入测试。
- 检查 JSON、typed extraction、MCP、sidecar 的共同入口；额外验证 MCP classify 输出可被下一次 validate/render 正确读回。
- 验证真实数据列与 R 内置常量区分、完整变量事务、失败依赖阻断、partial variables 仍只运行选中变量。
- 原有测试中“接受遗漏批次”“层名一致就是规则一致”“缺失输入不报告”的错误预期已改为新合同，并保留各自原本要测试的功能。
- 保存修改前源码快照与修复前后日志。中间失败、精度问题和 TRT01A 回归均修复后再次跑全量，没有删除失败用例来达标。

这不是对任意输入的形式化安全证明。测试使用显式、可信的数据对象；不会将执行环境描述成任意 R 对象的安全沙箱。

## 验收结果

最终交付已修复 11 项 BLOCKER、2 项 MAJOR。验收指标如下：

| 指标 | 修复前 | 修复后 |
|---|---:|---:|
| testthat 测试块 | 163 | 181（+18） |
| 通过的测试断言 | 1989 | 3033（+1044） |
| 失败 / 错误 | 0 / 0 | 0 / 0 |
| testthat 警告 / 跳过 | 7 / 1 | 7 / 1 |
| TRT01P | 100% | 100% |
| TRTSDTM 非缺失匹配 | 254/254，100% | 254/254，100% |
| TRTSDTM 原始全行匹配 | 83% | 83% |
| define 真实矩阵达到 100% 的项数 | 14/16 | 14/16 |

最终 `rcmdcheck::rcmdcheck(args=c("--no-manual"), error_on="error")` 为 **0 errors / 0 warnings / 0 notes**。500 行 classify+render 耗时 **4.10 秒**，低于 5 秒。源码模式和安装模式的 MCP 均通过 initialize、5 个工具发现及恶意 IR 拒绝检查。`source-manifest.json` 确认交付的 85 个 R/man/tests/tools 文件与接受检查的源码完全一致。

最终数值见 `summary.txt`；最终全量日志为 `tests-delivery.log`，包检查为 `check-delivery.log`。上述日志以最终交付源码为准，早期 check-* 日志仅作为迭代记录。

Oracle 比较保持原口径：TRT01P 100%；TRTSDTM 原始全行匹配率 83%，非缺失 254/254 为 100%，另 52 条双方缺失；define 真实矩阵维持 14/16 项达到 100%。中间收紧赋值规则曾使 TRT01A 转 REVIEW，已明确记录、修复并恢复，没有把该回归算作通过。

500 行 classify+render 的性能记录在 `performance-delivery.log`。新增依赖检查一度使耗时超过 5 秒，已通过移除已验证路径上的重复 gate 恢复达标；公开入口的验证仍完整保留。

AGENTS.md 要求的真实数据与历史 LLM 产物探针日志为 `probe-real.log`、`probe-llm.log`；其中每条 ERROR/FAIL/MANUAL/REVIEW 归档于 `probe-findings.csv`。缺失原始输入、缺 mc、研究规则需人工确定等既有状态没有靠编造规则消除。


历史 `demo_llm_exec.R` 使用的旧 artifact 被新 gate 拒绝：多个变量竞争生成 `ex::column::EXSTDTM`、`EXSTDTF`、`EXSTTMF`，日志为 `Invalid IR: multiple variables produce the same output`。该探针没有成功执行，不能计作执行回归通过；这是预期的安全拦截。后续应使用互不冲突的临时输出重新生成旧 IR，再复核其真实数据结果，本轮未修改历史产物来绕过 gate。

## MINOR 与剩余范围（不修）

- 继承上一轮 MINOR：run_validation quiet 描述默认值、flag_rate 说明、mock spec 源元数据、impute_dtc fn 函数族描述等。
- JSON-RPC 协议版本及 id 格式可进一步严格化；本轮重点验证服务入口、IR 数据完整性和恶意输入拒绝。
- 部分函数的空集合返回策略不完全统一；未造成此次验证中的晦涩崩溃。
- 7 条既有 testthat 警告及 metacore 缺失场景的既有跳过保留；它们与 R CMD check 的 error/warning/note 计数分别统计。
- DTHFL、TRTEDTM、BMIBL 的既有源数据/生产口径差异仍需研究特定规则确认；本轮要求是保持其原始指标不退化，没有虚构临床派生规则。
- 文件日志含一次宿主工具长时间未返回及续跑记录；最终验收单独使用 delivery 文件，避免与尚未结束的早期进程争用日志。