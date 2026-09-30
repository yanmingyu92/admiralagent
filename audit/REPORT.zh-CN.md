# admiralagent 安全与质量审计报告

审计日期：2026-09-17。环境：Windows 11、R 4.6.0。工作目录不是 Git 仓库，因此下列为 commit 式修复说明，没有伪造提交或 commit hash。实际改动已落盘。

最终验收：**R CMD check 0 errors / 0 warnings / 0 notes**；全量 testthat **163 个用例、1989 条通过断言、0 failures、0 errors**。证据：[最终包检查](check-release.log)、[检查结果对象](check-release-result.rds)、[最终全量测试](tests-final.log)、[指标汇总](metrics.log)。

## 1. 分级发现与已实施修复

| 编号 / 级别 | 证据与影响 | commit 式修复说明 |
|---|---|---|
| B01 BLOCKER | 原 filter/formula 直接插入代码；旧校验剥除符号后比较单词，不能证明表达式安全。`system('rm -rf')`、`AGE;1`、赋值、索引、命名空间等进入同一攻击面。 | `fix(security): enforce lexical and AST expression allowlists before rendering`：新增 `R/safety.R:54`，parse 只用于构造语法树，不 eval；所有公开 render/execute 路径先 gate。17 类攻击 payload 分别覆盖 formula/filter。 |
| B02 BLOCKER | 原 `q_chr()` 直接拼双引号；target/from/on/dataset 等未经标识符检查；spec_origin/rationale 中换行可结束注释。 | `fix(codegen): quote literals and constrain identifiers and comment lines`：`R/layers.R:3` 使用 JSON 字符串编码；`R/safety.R` 检查标识符；`R/codegen.R` 对每个说明续行继续添加注释。常量原样往返，注入内容不会变成代码。 |
| B03 BLOCKER | `validate_ir()` 对多值 dataset、原子 step、嵌套 NULL、错误 args、非标量枚举可触发 length/$/条件错误。重复 Inf breaks 也可能产生 NA 条件。 | `fix(ir): validate structure and argument types before semantic checks`：`R/ir.R:93` 先执行 `validate_ir_shape()`；类型来自层 args 注册表；拒绝未知 args、错误长度、NA、超长字符串；明确检查 breaks 顺序。320 个随机畸形 JSON 往返样本全部返回可读问题。 |
| B04 BLOCKER | `execute_ir()` 原 parent=globalenv()；缺失列可能意外读取全局同名对象，且执行前没有完整 IR gate。sources 可覆盖 target/helper。 | `fix(execute): isolate evaluation and reject source shadowing`：`R/execute.R:62` 使用 baseenv() 父环境、显式 sources、唯一名称、data.frame 类型检查及 helper 保留名；全局 AGE 不再被读取。 |
| B05 BLOCKER | 原 DESCRIPTION 首字节 EF BB BF；R 把字段读成带 BOM 的 Package，roxygen 无法识别包，构建被阻断。 | `fix(package): remove DESCRIPTION UTF-8 BOM`：保留字段内容，移除 BOM。最终原生 build/check 全部通过。 |
| M01 MAJOR | impute_dtc 由前缀生成 DT/DTM，原 gate 不核对 target；dtm_to_dt 实际忽略任意 target；RFENDT 原被当作 datetime，声称执行成功但没有对应输出。 | `fix(dates): validate generated target names and select DT versus DTM correctly`：目标后缀与 output_class 对齐；dtm_to_dt target 必须为 source DTM→DT；target==dtc 直接拒绝。分类器保留 DTC predecessor copy，按 DT/DTM 选择输出。RFENDT 新增 oracle 100% 匹配。 |
| M02 MAJOR | 幂等守卫在整条变量链开始前删除所有输出；compute_var 等覆盖式表达式可能丢失自身输入。 | `fix(execute): guard each step immediately and preserve mutate inputs`：每步执行前清理；assign、compute_var、date_shift、categorize 保留输入列。现有 assign 自复制、重跑、外国数据集 imputation 回归保持通过，新增 X+1 保留输入测试。 |
| M03 MAJOR | prompt 禁止 ADSL 上直接生成 BDS 参数记录，原 validate_ir 却允许；裸 WEIGHT 也能通过 compute_param 的 token 检查。 | `fix(semantics): align BDS and parameter-reference rules with prompt`：禁止 compute_param/summary_record 直接用于 ADSL；公式符号仅限参数列表中的 AVAL.<PARAMCD>。更新原有错误“good”测试为真正 BDS 数据集 ADVS。 |
| M04 MAJOR | 导出函数垃圾输入触发原子向量 `$`、subscript out of bounds、隐晦连接错误；空 spec 补标量列导致崩溃。 | `fix(api): validate input shape and return actionable diagnostics`：spec、context、路径、artifact、dependency、validation、evals、compat 增加入口检查；空 spec 按 0 行补列。43 个导出入口有逐项探针记录。 |
| M05 MAJOR | 字符串生成/解析/文件写入未固定 UTF-8；MCP 仅用 R/ 目录存在判断源码模式，安装目录也可能满足。 | `fix(portability): preserve UTF-8 and distinguish source from installed MCP`：执行 parse 显式 UTF-8，artifact 使用 UTF-8 写入；MCP source 显式编码并检测 R/mcp.R 实文件。源码与最终安装包均通过 initialize、tools/list、恶意 IR 拒绝探针。 |
| M06 MAJOR | 通用 on 参数在 render/prompt 使用，却不在各层 args 文档；旧 compute_var 使用禁括号启发式，无法允许安全的分组运算；单变量产物缺免责声明。 | `fix(registry): document on and align arithmetic grammar and generated headers`：注册表统一附加 on；允许算术分组括号、拒绝函数调用；step/variable 输出附 DISCLAIMER，保留 CHECK。 |

本批次遵循 improvement loop：基线与探针 → 发现编号 → 语义/结构 gate、`build_system_prompt()`、对抗与回归测试同步修改 → 每批修改后执行全量测试。中间失败没有隐瞒，保留在 `tests-fix*.log`。最终一轮日志 `tests-final.log` 全绿。对 test-ordering 的原 foreign-only IR，新增拒绝断言并改用合法的数据集生产者继续测试排序，没有撤掉排序覆盖。

## 2. 注入面规则

校验分为结构、词法、语法树和层语义四部分。验证器解析后检查节点，不执行任何 IR 表达式。

- 变量名：`^[A-Z][A-Z0-9_]*$`，最长 128 字节，排除 R 的保留常量；表达式中的参数记录引用允许 `AVAL.<PARAMCD>`。
- 数据集对象名：`^[A-Za-z][A-Za-z0-9_]*$`，保留现有 ex/vs/dm 等小写输入习惯；禁止点号、反引号、索引、赋值片段。
- filter/restrict_filter：允许大写变量、有限数值、单/双引号字符串、圆括号、`< <= > >= == != & && | || !`，以及 `+ - * / ^`。
- formula：只允许大写变量/AVAL 参数引用、有限数值、`+ - * / ^` 和分组括号；不允许字符串或逻辑/比较运算。算术运算符是现有 BMI/CHG/PCHG 功能所需。
- 一律拒绝函数调用、`::`、`$`、`[`、`{}`、分号、多表达式、注释、反引号、管道、`%in%`、`<-`、`<<-`、`=` 赋值和伪装的 Unicode 语法字符。
- 字符串参数最长 16384 字节，语法树遍历深度最多 64；字符串常量中的中文、引号、反斜线、换行可以合法保留。
- `validate_ir()` 拒绝失败输入，render/execute 不绕过 gate；不靠捕获 eval 错误来阻止注入。`read_artifact()` 也在返回前校验。

攻击测试使用无破坏性断言，未执行 `rm`、`system` 或其他恶意命令。执行隔离针对 IR 和全局变量泄漏；运行使用的是调用者显式提供的数据对象。

## 3. Oracle 回归前后

按要求依次运行两份 demo；代码最终状态再次重跑。原始 CSV 和完整日志均保存在本目录。

| 指标 | 修复前 | 修复后 | 结论 |
|---|---:|---:|---|
| accuracy demo TRT01P | 100.0% | 100.0% | 不退化 |
| accuracy demo TRTSDTM 原始全行 value_match | 83.0% | 83.0% | 不退化；原指标将双方 NA 计为不匹配 |
| TRTSDTM 非缺失可比值 | 100%（由原始矩阵推得） | 100%（独立复算 254/254） | 达到非缺失值 100% |
| TRTSDTM 缺失状态一致率 | 100% | 100% | 52 条双方均缺失 |
| TRTSDTM 将双方缺失视为相等 | 100%（由原始矩阵推得） | 100%（306/306） | 没有更改 demo 原始指标口径 |
| define 真实矩阵 | 13/15 项达到 100% | 14/16 项达到 100% | 新增 RFENDT 100%；原可比项不下降 |
| accuracy demo TRTEDTM | 39.5% | 39.5% | 原有规则/生产口径差异保留 |
| BMIBL pilot1（原 demo 的修订规则） | 85.8% | 85.8% | 不退化 |

证据：`accuracy-before.csv` / `accuracy-after.csv`、`define-before.csv` / `define-after.csv`、`metrics.R` / `metrics.log`。用户预期的“TRTSDTM 100%”必须注明缺失值口径；不能把 demo 实测的 83.0% 直接报告成 100%。

AGENTS.md 的 `demo_real.R` 与 `demo_llm_exec.R` 探针也执行了。所有 ERROR/FAIL/MANUAL/REVIEW 行逐行编号保存在 `probe-findings.csv`（含前后矩阵重复观察，不能当作独立漏洞数）。其中 AGE 缺 BRTHDT/TRTSDT、RACEN 缺 mc、分类断点需要人工、BMI 缺 BASELINE HEIGHT 等是现有输入或规则限制；没有编造研究规则来抹除这些状态。DTHFL 在 pilot1 上仍为 1.2%，需要核对源数据与提交版死亡标志/缺失约定；该直接复制规则及前后值均未退化。

## 4. 测试与性能

| 项目 | 修复前 | 修复后 |
|---|---:|---:|
| testthat 测试用例 | 153 | 163 |
| 通过断言 | 849 | 1989（+1140） |
| failures / errors | 0 / 0 | 0 / 0 |
| testthat 警告 | 7 | 7 |
| 跳过 | 1 | 1 |

7 条警告：3 条依赖包由 R 4.6.1 构建的版本提示，4 条既有 BASELINE HEIGHT 数据条件提示。跳过项为“metacore 不存在”分支，因为本机已安装 metacore。它们与最终 R CMD check 的 0/0/0 属于不同统计口径。

新增 10 个测试块包含 320 次随机 JSON 畸形测试及超过 10 类原未覆盖错误路径；详见 `ERROR-PATHS.md`。随机种子 20260917，允许重复抽样；不宣称覆盖所有可能 IR，也不将此清单冒充全包分支覆盖率。

500 行 spec（500 个独立、合法、直接复制变量）完整 classify + render：最终实测 **2.50 秒**，小于 5 秒。见 `probe.R` 和 `performance.txt`；不是 500 个复杂 BDS 链的性能承诺。

## 5. 单一事实源、文档与跨平台结果

实际注册层为 **14 个**，不是 15 个：assign、merge_var、lookup_join、impute_dtc、dtm_to_dt、duration、date_shift、compute_param、summary_record、extreme_flag、codelist_var、obs_number、categorize、compute_var。已覆盖全部实际存在层，未人为新增一层凑数。

`layers.csv` 逐层记录 args/fn，以及文档卡是否原样出现在 system prompt（全部 TRUE）。通过静态阅读 render、既有 golden 测试、日期/BDS/枚举/类型新 gate 和执行测试核对实现。通用 on 已进入每层文档。`docs.csv` 对 43 个导出函数逐个比较实际 formals 与 man 参数：缺失文档、缺参、多参均为零；`roxygen-params.csv` 列出 roxygen 参数，最终 R CMD check 文档/namespace 检查全过。

UTF-8：DESCRIPTION 无 BOM；代码生成常量、执行解析和产物写入均有中文往返测试。CRLF/LF 扫描见 `encoding.json`；源码检查通过，不为排版原因批量改换行。`system.file()` 的安装查找及源码目录向上回退保留，相关测试通过。MCP 由 `mcp-probe.py` 在源码模式和最终检查安装包模式独立启动，各验证 3 个请求、5 个工具、恶意 IR 拒绝；结果见 `mcp-source.jsonl`、`mcp-installed.jsonl`。

`variables=` 语义：仅运行选中的变量，未知名称报错；空选择返回固定结构的 0 行 status。调用者重跑时通过 sources 提供上次结果和所需源数据。守卫保证相同源输入的重复执行；`X = X + 1` 若把前次输出再次作为输入，仍按表达式继续增加，不能把任意递推表达式解释成数学幂等。

## 6. MINOR 清单（记录、不修）

1. `run_validation()` 的 roxygen quiet 默认文字为 TRUE，实际默认 FALSE；参数签名一致，但描述默认值漂移。
2. `flag_rate` 说明提及不能 all-set，实现主要检查 never-set；建议另行明确验证需求。
3. mock ADSL 中 TRTSDTM/TRTEDTM 的 derivation 已写 DM RFSTDTC/RFENDTC，但 source_dataset/source_variable 元数据仍偏向 ex/EXSTDTC；建议统一示例元数据。
4. impute_dtc 的 fn 字段为 derive_vars_dtm，output_class=dt 实际走 derive_vars_dt；args/render 已验证对齐，建议后续把 fn 明确描述为函数族。
5. error-on-empty 与空结果接受策略在部分查询/构造函数不完全统一：构造器允许先建立对象再交 validate_ir；log_run 接受结构化事件值；这些行为未造成隐晦崩溃，建议后续统一 API 风格。
6. 本机原环境 LC_ALL/LC_CTYPE/LANG=C.UTF-8 在 Windows R 上产生启动警告；本次检查进程使用 Windows 有效 UTF-8 locale。Pandoc 已安装但不在 PATH，本次仅为进程补全 PATH/RSTUDIO_PANDOC，未修改用户全局设置。
7. 既有 testthat 的 7 warnings / 1 skip 保留；建议后续在依赖矩阵中专门测试“未安装 metacore”的分支。

## 7. 复现

在 job 目录运行：

```r
testthat::test_dir('admiralagent/tests/testthat', reporter='summary', stop_on_failure=TRUE)
rcmdcheck::rcmdcheck('admiralagent', args=c('--no-manual'), error_on='error')
```

Rscript 位于 `C:/Users/JaimeYan/AppData/Local/Programs/R/R-4.6.0/bin/Rscript.exe`；Pandoc 位于 `C:/Users/JaimeYan/AppData/Local/Pandoc`。最终检查使用 Windows 有效 UTF-8 locale 与该 Pandoc 路径，没有关闭 vignettes、跳过测试或降低 check 要求。`audit/` 仅包含报告与运行证据，已加入 .Rbuildignore；新测试位于正常 tests/testthat 内并进入包检查。