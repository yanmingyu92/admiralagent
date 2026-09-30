# admiralagent 第三轮全面交叉审计报告

本轮以当前工作目录实测为准，保留前两轮安全修复，新增修复 1 项 BLOCKER、3 项 MAJOR。未使用 DeepSeek key，未发送患者数据，未执行恶意命令。没有创建 Git 提交；以下为 commit 式修改说明。修改前源码在 `before-src/`，修改文件清单为 [changed-files.txt](changed-files.txt)。

## 1. 基线与最终验收

| 项目 | 本轮修改前 | 本轮修改后 |
|---|---:|---:|
| 导出函数 | 43 | 43 |
| 实际注册层 | 14 | 14 |
| testthat 测试块 | 181 | 193（+12） |
| 通过断言 | 3033 | 3807（+774） |
| 失败 / 错误 | 0 / 0 | 0 / 0 |
| testthat 警告 / 跳过 | 7 / 1 | 7 / 1 |
| 500 行 classify+render | 2.88 秒 | 3.01 秒（<5 秒） |
| R CMD check | 前轮交付 0/0/0 | **0 errors / 0 warnings / 0 notes** |

任务书中的“15 层、约 800 断言、13/15 满分”与当前源码不同，未将旧口径冒充本轮实测。当前目录在新增本轮测试前为 17 个 R 源文件、22 个 test 文件及 helper.R；新增后为 23 个 test 文件及 helper.R。

证据：[计数和 Oracle 自动比对](summary.txt)、[最终全量测试](tests-fix2.log)、[最终包检查](check-delivery.log)、[性能](performance.txt)。7 条 testthat 警告为 3 条依赖包由 R 4.6.1 构建提示及 4 条既有 HEIGHT 筛选为空提示；1 条跳过是已安装 metacore，无法进入“未安装”分支。这些不等同于 R CMD check 的 warning 数。

## 2. 分级发现、证据与修复

| 编号 / 级别 | 可复现证据与影响 | 修复说明 |
|---|---|---|
| R3-01 BLOCKER | `output_class="dt"`、输入含 `DTC` 和 `XTMF="KEEP"`；执行状态 EXECUTED，但输出变成 DTC/XDT/XDTF，原 XTMF 无声丢失。 | `fix(execute): preserve unrelated time flags during date-only imputation`：仅 dtm 清理 TMF；dt 只清理 DT/DTF。与 dependency 的产物定义一致，测试首次运行和 partial 重跑均保留原列。 |
| R3-02 MAJOR | dt 模式同时给 `time_imputation="last"`，validate_ir 原先通过，渲染结果却完全不含 last。调用者指定的参数被静默忽略。 | `fix(ir): reject time rules for date-only imputation`：validate_ir 拒绝不适用的参数；注册表明确禁止，prompt 同步；dtm 模式仍支持 first/last。 |
| R3-03 MAJOR | `categorize.right=matrix(TRUE)` 原 gate 接受；canonical JSON 输出 `[[true]]`，重读后却被同一 gate 拒绝。有效 IR 无法保持序列化往返合同。 | `fix(schema): reject dimensioned IR scalar and vector fields`：needs_human 与所有 args 拒绝矩阵/数组形状。补逻辑标量、字符参数、矩阵往返相关回归，prompt 明确标量形状。 |
| R3-04 MAJOR | `render_program(finalize=NULL/list()/NA/c(TRUE,FALSE))` 报底层条件错误；installed、known_columns 等缺少公共参数合同；重复 spec 列名与嵌套单元格可越过入口。 | `fix(api): validate execution controls and spec cell shapes at entry`：统一逻辑标量守卫；校验 backend_label、版本号、known_columns；拒绝重复 spec 列名和 list/matrix 单元格。诊断明确指出参数/列名，prompt 和回归同步。 |

证据：[原始复现](probes-before.log)、[通过修改前源码快照运行的补充探针](extended-probes-before.log)、[新回归测试](../../tests/testthat/test-audit-round3.R)。每轮修改后执行全量 test_dir。首次回归发现新增的“render_program 仅支持单数据集”限制破坏原有跨数据集渲染测试，已撤回该限制，原测试未改；保留 [首次失败日志](tests-fix1.log)，最终全量通过。

本轮包检查首次已显示 Status: OK，但外围 PowerShell 计数命令转义失败；保存该日志为 `check-final.log`。最终改用独立 [check.R](check.R) 重跑，交付以 `check-delivery.log` 为准。

## 3. 注入面方案与白名单

沿用并重新验证现有 `R/safety.R` 的两级白名单：先 parse 获取 token 和 AST（不 eval），再逐个检查 token、标识符、常量、运算节点及深度。全部渲染/执行入口先过 validate_ir；render_step 还要求 step 与其父 IR 的对应 step 完全一致，防止替换绕过。

- 列名为 ASCII 大写标识符；compute_param 中额外允许 `AVAL.<PARAMCD>`，且 PARAMCD 必须列于 parameters。源对象名允许大小写 ASCII 标识符，不能用保留字。
- 常量为有限实数；filter 可使用引号包裹的字符值。单字符串上限 16384 字节，标识符上限 128 字节，AST 遍历深度上限 64。
- filter/restrict_filter 支持比较 `< <= > >= == !=`、逻辑 `& && | || !`、圆括号及算术 `+ - * / ^`；formula 只支持算术及圆括号。保留算术是为了 BMI、CHG 等已有公式能工作，不开放任意函数调用。
- 拒绝函数调用、赋值和超级赋值、反引号、命名空间、索引、`$`、花括号、注释、分号、管道及未列出的运算符。字符串内部类似代码的内容作为数据处理。
- literal 使用字符串转义；spec_origin、rationale 和 backend_label 写入注释前处理换行，防止逃逸。生成代码仍含 DISCLAIMER 与 CHECK 注释。

`system('rm -rf')` 等内容只作为拒绝测试输入，从未执行。现有注入回归全部通过。本轮新增 240 个固定种子畸形 JSON 样本，涵盖未知层、错类型、NULL 嵌套、空 steps、超长文本及 Unicode；加上保留的 320 个 JSON 模糊样本及 420 个跨层/往返对抗样本，共 980 个样本。全部执行无未捕获崩溃；这不是任意输入上的形式化安全证明。

## 4. 十项审计清单对应证据

| 项目 | 结果与证据 |
|---|---|
| 1 注入 | 白名单、公共入口、标识符/注释逃逸测试通过；见 test-audit-security.R、test-audit-round2.R 和本报告第 3 节。 |
| 2 模糊测试 | 本轮新增 240 个 JSON 样本，保留前两轮样本；全量日志通过。 |
| 3 单一事实源 | 全部实际 14 层的 args、required、inputs、render 参数引用、黄金代码 parse、prompt 逐层比对通过；[layer-crosscheck.csv](layer-crosscheck.csv)。`on` 在 codegen 消费；dtm_to_dt 的 target 由校验保证等于 source 派生名，这两类不应误报“render 未使用”。dt/time 参数矛盾已修复。 |
| 4 Oracle | 前后分别按 accuracy→define 顺序执行；两份 CSV 前后完全相同，见下表及 summary.txt。 |
| 5 执行安全 | baseenv 父环境、显式 source、缺列不回退到 T/F、事务回滚、失败依赖阻断、partial 只跑选中变量、assign 自拷贝及 self-imputation 拒绝均通过既有回归；新增 dt 误删旗标回归。可信 data.frame 的隔离不代表任意恶意 R 对象的沙箱。 |
| 6 导出垃圾输入 | 43 个导出逐项登记；有数据参数的入口测试 NULL/list/空 df/错列名，见 [export-inputs.csv](export-inputs.csv)。无参函数不伪造数据参数，阻塞 MCP 单独测试。ACCEPTED 表示函数正常返回，validate_ir 返回问题向量、is_valid_ir 返回 FALSE、run_validation 返回 FAIL 等不应当作错误接受；构造器允许建立待验证 IR。 |
| 7 跨平台卫生 | R/tests 共 41 文件可按 UTF-8 解码，记录 CRLF/LF；[encoding.json](encoding.json)。Unicode artifact 往返测试通过；源码树中 load_evals 找到 24 案例；MCP 源码/安装两模式测试初始化、5 工具发现及恶意 IR 拒绝。本轮只实跑 Windows，不宣称 Linux CI 已运行。 |
| 8 错误分支 | [error-branches.json](error-branches.json) 列出 154 处静态错误/校验分支；[ERROR-PATHS.md](ERROR-PATHS.md) 将新增至少 10 条错误路径映射到测试。静态清单不冒充覆盖率工具报告。 |
| 9 文档 | 43 个导出均有 Rd；Rd 参数和实际签名无缺失/多余；roxygen 参数逐个核对一致。证据 [docs.csv](docs.csv)、[roxygen-params.csv](roxygen-params.csv)。旧叙述漂移列 MINOR，不修改。 |
| 10 性能 | 500 行 spec 的 rules classify + render，2.88→3.01 秒，达标；未包含网络 LLM 延迟。 |

## 5. Oracle 前后对比

| 指标 | 修改前 | 修改后 |
|---|---:|---:|
| accuracy：TRT01P vs pharmaverseadam | 100% | 100% |
| accuracy：TRT01P vs pilot1 | 100% | 100% |
| accuracy：TRTSDTM 原始全行 value_match | 83.0% | 83.0% |
| accuracy：TRTSDTM 缺失一致率 | 100% | 100% |
| TRTSDTM 非缺失值口径（前轮已核实） | 254/254，100% | 原始结果未变；对应集成测试通过 |
| define 真实矩阵可比项 | 16 | 16 |
| define 达到 100% 的项 | 14/16 | 14/16 |
| pilot1 rules 分类 | 17/49 | 17/49 |
| pilot1 needs_human | 32/49 | 32/49 |

全部原指标逐项不降，包括表中未单列的 TRT01A、TRTEDTM、BMIBL 等；不是只比较总体满分数量。证据：[accuracy-before.csv](accuracy-before.csv)、[accuracy-after.csv](accuracy-after.csv)、[define-before.csv](define-before.csv)、[define-after.csv](define-after.csv)。不把双方缺失的 TRTSDTM 样本按另一口径计入 100%，也不把 AGE 原生列比较成功误报为 AGE 派生成功。

## 6. Improvement loop 与剩余事项

修改前后均运行 demo_real.R 和 demo_llm_exec.R。所有 ERROR/FAIL/MANUAL/REVIEW 及 gate 拒绝行已编号归档：[probe-findings.csv](probe-findings.csv)（含 summary 行，不等同于 87 个独立缺陷）。AGE 缺 BRTHDT/TRTSDT、RACEN 缺 mc、AGEGR1 需确定切点以及旧 BMI 筛选口径问题均如实保留。

历史 LLM artifact 仍因多个变量竞争生成 EXSTDTM/EXSTDTF/EXSTTMF 被 read_artifact 拒绝。该脚本退出 1，是预期的旧坏产物拦截，不能称作 LLM 执行通过。后续需生成互不冲突的临时输出并重新评估；本轮未绕过 gate，也未宣称真实 define 的 LLM 已标定。

MINOR 清单（按纪律记录、不修）：

1. DESIGN 中“15 层”与实际 14 层不同；README 的 impute 示例仍展示旧 admiral 参数名。建议后续用注册表/黄金样例自动生成展示代码。
2. 继承旧项：run_validation 的 quiet 默认值叙述、flag_rate 的“not all-set”说明、impute_dtc 的 fn 函数族描述及 mock spec 来源叙述仍有打磨空间。
3. source 模式资源回退要求工作目录位于包树内；从 job 父目录单独 source 后直接 load_evals(NULL) 不自动向子目录查找，错误会提示进入包树或安装。MCP 启动脚本会进入包根，已验证通过。
4. log_run 的 event 类型、若干空集合返回策略及 JSON-RPC 版本/id 严格度可进一步统一；现有正常调用和本轮垃圾输入未出现未捕获进程崩溃。
5. stdin/部分辅助日志读写仍依赖运行时编码设置；本轮 Windows UTF-8 环境和 Unicode 往返已验证，其他 locale/OS 尚未实跑。
6. CI workflows 未实跑；保留现有 7 条测试警告和 1 条跳过。

后续建议：先为剩余 32 条真实 define 描述建立人工确认的语义标签，再用 schema-only 上下文标定 LLM；evals 应比较完整派生参数而非仅层链。底层 categorize 已存在，AGEGR1 的真实切点自动提取与确认仍未完成，不将人工决策擅自转换为规则。

最终确认：check-delivery 独立 R 脚本退出码为 0，计数为 0/0/0；交付 R/man/tests/tools 共 87 个文件与接受检查的源码逐字节一致，见 source-manifest.json。MCP 两模式已使用该最终检查安装目录再次验证通过。
