# 我让 LLM 一行 R 代码都不许写，然后把真实药审数据丢了进去

> 本文所有数字来自一条命令可复现的流水线（`Rscript demo/automation/run_all.R`），
> 跑在公开的 CDISC pilot 5 真实递交数据上；证据链是仓库里的
> `demo/automation/REPORT.md` 和 `demo/automation/out/` 下的机器可读文件。

## 一、为什么"AI 帮你写代码"在药审场景是死路

临床编程是强监管行业。市面上有一类 demo：LLM"刷刷刷"写完整套分析代码，观众鼓掌。
在 GxP 语境下这条路走不通——因为 LLM 写的每一行代码都得有人逐行 review，而它真正的
失败模式不是"跑不通"，而是**"跑得通，但悄悄地错"**。一个静默出错的分析结果，比没有
结果危险得多。

admiralagent（MIT 开源）换了一个赌注：**LLM 一行 R 代码都不许写。**

## 二、架构主张：LLM 只做翻译，编译器才写代码

整个系统里 LLM 只干一件事——把 spec 里每个变量的自由文本推导规则，翻译成一个叫
Layer IR 的 JSON 对象。IR 的词汇表是封闭的：`assign`、`merge_var`、`impute_dtc`、
`categorize`、`compute_param`……一共就这几种推导层，多一个都没有。

IR 之后的每一步都是确定性的：编译器把 IR 渲染成 {admiral} 代码（带 `# CHECK:` 校验
注释）；`validate_ir()` 这道 schema+语义门 fail-closed——任何超出词汇表的东西直接拒收，
不猜、不自动修复。最终被校验、被批准、被哈希归档的是那份小小的 JSON，不是散文，
也不是代码。

## 三、实验设计：真实递交数据，一条命令

直接把流水线对准 **CDISC pilot 5 真实递交**：P21 风格的 ADaM define 工作簿
（`adam-pilot-5.xlsx`）、原始 SDTM `.xpt` 作为执行输入、递交版的
`adsl.xpt`/`adae.xpt`/`adlbc.xpt` 作为 accuracy oracle。showcase 从最初只做 ADSL，
现在扩到了同一次递交的**三个数据集**：ADSL（49 个 spec 变量）、ADAE（55）、ADLBC（46）。

每个 spec 用两个后端各翻一遍：零依赖的 **rules 后端**（关键词基线，成本为零）和
**DeepSeek**（`deepseek-chat`，走 {ellmer}）。ADSL 另取 12 个变量做了 3 采样多数票。

## 四、真实数字（先念边界，再念数字）

先说两条跟每个数字绑定的边界：产出数据集**不做人口子集**（产出的 ADSL 有 306 行，
oracle 是 254 例随机化人群；产出的 ADLBC 59580 行 vs oracle 37132 行），agreement 只在
join 上的记录里算；这是和单个 oracle 的自评对比，**不等于双程编程**。

| 数据集 | 后端 | spec 变量 | 弃权(needs_human) | 执行 | oracle 可比 | 完全一致 | 均值 |
|---|---|---|---|---|---|---|---|
| ADSL | rules | 49 | 32 | 16 | 15 | **15 (100%)** | 100.0% |
| ADSL | DeepSeek | 49 | 27 | 20 | 19 | **16** | 90.9% |
| ADAE | rules | 55 | 16 | 27 | 20 | **20 (100%)** | 100.0% |
| ADAE | DeepSeek | 55 | 8 | 32 | 27 | **25** | 96.3% |
| ADLBC | rules | 46 | 14 | 15 | 14 | **12** | 85.8% |
| ADLBC | DeepSeek | 46 | 13 | 22 | 21 | **19** | 90.5% |

几个要点：

- rules 基线在 ADSL 上弃权近三分之二，但只要它敢做的，三个数据集上**全对**
  （ADLBC 的 85.8% 是被一个 spec 文本缺陷拖下来的，见第六节）。
- DeepSeek 在三个数据集上都比基线多做（ADAE 只弃权 8/55）。
- 双后端层链一致率 ADSL 82% / ADAE 58% / ADLBC 57%——这是"两个译者读同一份文本"的
  一致性度量，**明确不是正确性声明**；3 采样共识在 ADSL 12 变量子集上 12/12 全票。
- LLM 边际成本：**每个数据集 50–84 秒、0.008–0.011 美元**，三个加起来不到 3 美分
  （约两毛人民币）；rules 基线 0.1 秒、零成本。

但头条数字仍然是弃权那一列，不是准确率那一列。

## 五、边界即卖点：27 次弃权，次次有理由

DeepSeek 在 ADSL 上拒答了 49 个变量里的 27 个。翻开弃权清单，它不是随机的——那是
被大声说出来的词汇表边界，而且在另外两个数据集上以不同的口音重复：

- **词汇表里没有条件层**。所以所有 `Y if <条件>` 旗标集体弃权：ADSL 的 SAFFL、ITTFL、
  DISCONFL、COMP8/16/24 访视窗口旗标、EOSSTT；ADAE 的 TRTEMFL 和条件 study day
  （ASTDY/AENDY）；ADLBC 的 ANRIND/BNRIND（if/else 正常值范围判定）。模型编不出
  `ifelse`，因为 `ifelse` 不在词汇表里。
- **引用外部材料的弃权**：SAP 章节（SITEGR1）、spec 没给的 codelist（TRT01PN、
  DCSREAS、ADLBC 的 PARAMN）。
- **缺词汇就如实说缺**：ADLBC 的 PARAM 需要字符串拼接（"LBTEST (LBSTRESU)"），
  词汇表没有函数调用，弃权；ALBTRVAL 要 `max()`，同样弃权。
- **跨数据集存在性检查**（EFFFL、VISNUMEN）和**多分支临床逻辑**（CUMDOSE 按组别
  分段的剂量规则）弃权。

一个会对这些变量硬编答案的系统，严格地比一个会弃权的系统更差。在审计叙事里，
"机器说了 27 次'我不知道'，每次都带理由"，是一条你能站得住的特性。

## 六、错误分类学：连"错"都错得很有意思

- **HEIGHTBL/WEIGHTBL：原始一致率 19.7%/8.7%——但按 oracle 自己的存储精度算是
  98.8%/94.5%**（finding F-05）。数值溯源到的正是 spec 点名的 VS 记录；oracle 悄悄
  做了 1 位小数舍入，这个约定 spec 文本从没提过。推导是对的，沉默的是元数据。
- **AGEGR1N：在尝试推导它的那轮运行里，全部 11 例分歧都是恰好 80 岁的受试者**
  （F-04）。spec 原文同时写着"65–80"和">80"，自相矛盾；模型选了一种读法，递交选了
  另一种。人类程序员在这里也只能发 query。当前缓存的这轮运行里，模型对这个变量改为
  弃权——运行间方差如实记录在 limitation 8。
- **ADLBC 的 BASE/CHG 只有 0.4% 一致，而这是 spec 文本的字面缺陷**（F-09）：工作簿里
  BASE 的推导文本字面上就是 `LB.LBSTNRHI`（该记录自己的正常值上限），不是基线值。
  流水线照 spec 字面执行、照实报告分歧——人类程序员看到这句话也得发 query。
- **诚实的依赖级联**：ADAE 剩下的执行错误，大多是要 merge 的 ADSL 列恰好是 ADSL 后端
  自己弃权的那些——跨数据集推导的完整性以上游为上限。

这就是为什么流水线要和 oracle 比、而不是自称正确：自动化 showcase 的诚实产出是一份
**失败分类学**，不是一场庆功宴。

## 七、showcase 会审计自己：探针→发现→修复→回归

从 ADSL 扩到三个数据集之后，最意外的收获是流水线开始抓自己的 bug。findings 登记册
（`out/findings.json`，F-01 到 F-10）记录的不是一次性 demo，而是一个真实运转的改进
回路。已解决的四个值得展开：

**F-01：fail-closed 防线前移了。** LLM 给 ADSL 的 TRTSDT 生成的 IR 先把 `SVSTDTC`
merge 成新列 `TRTSDT`，下一步又要从 `SVSTDTC` 做插补——merge 之后这个名字已经不存在了。
旧语义门放行，执行时才炸。fail-closed 执行层接住了它（事务回滚、下游变量拒绝使用
陈旧输入），但正确的拦截点是门里。现在 `validate_ir()` 跨步骤追踪 merge 改名，**同类
IR 在门内就被拒收，错误信息里直接报出新列名**，并配了回归测试。这是整个包的缩影：
一道原本在执行层的防线，前移到语义门，离错误发生的地方更近了一步。

**F-06：一个缺失的 context 字段悄悄拖垮了整个数据集。** 分类 context 从没告诉模型它在
翻译哪个数据集，而系统提示里唯一的例子写着 `"dataset":"ADSL"`。推导文本写
"ADSL.TRT01A" 的 ADAE 变量，模型乖乖照抄 ADSL，对齐检查整批拒收，14 个变量退回弃权。
一行修复（把 spec 的 dataset 列放进每个变量的 payload）：ADAE 弃权 21→8、失败批次
4→0（ADLBC：46→25、16→0），全量测试 4815 条通过。

**F-10：修好 F-06，暴露了下一层。** dataset 字段修好后，模型把"跨数据集取值一律
merge"的 rules 执行得太字面：把 AE merge 进 ADAE——而 ADAE 的基座就是 AE——by-key 重复，
25 个 fail-closed 的 duplicate_records 错误。修复落在 prompt 层（词汇表没动）：新增
一条硬规则——同域基座列**必须**用 `assign` 直拷，把数据集 merge 进它自己的子数据集是
禁止的。重跑实测：**ADAE 执行变量数 7→32、duplicate_records 25→0、oracle 27 可比
25 全对、均值 96.3%**；ADLBC 弃权 25→13、执行 4→22。

**F-02：codelist 从纸面变成可执行。** 模型为 RACEN/TRT01PN/TRT01AN 选了
`codelist_var` 层，但 showcase 从没构建过 metacore 对象，执行即报错。现在流水线把递交
工作簿的 `Codelists` 表转成每个数据集一个可执行 metacore（`out/mc_<ds>.rds`），直接
探针验证手工 IR 在 254 例 join 上 100% 吻合 oracle。诚实脚注：当前缓存的 LLM 运行对
这几个变量仍是弃权（运行间方差，limitation 8）——修复由探针验证，随时等任何一个选中
该层的 IR。

探针→登记 finding→修复→回归测试→重测——这个序列本身就是重点。本文的数字全是
**回路跑完之后**的数字，而这个回路是产品的一部分。

## 八、我们不声称什么

REPORT 的 limitations 是逐字保留、不可谈判的，压缩版：不做人口子集，agreement 只在
join 记录上算；词汇表缺口是硬边界，加投票者修不了；rules 后端是关键词基线不是理解；
evals 语料是自评分（期望值由 rules 生成）的回归语料不是 oracle；IR 一致性 ≠ 双程编程
（所有投票者读同一份 spec）；oracle 分歧可能是 spec 歧义不是包错误；生成的程序是
UNGATED DRAFT，没有任何人工批准门覆盖，只是演示产物；单模型、三个数据集、有随机性
（ADSL 两轮全量运行弃权数 24→22，层链一致率 78%→71%——这正是共识投票模式存在的理由）；
ValueLevel 元数据（全是 ADADAS）不在范围内。

## 九、为什么偏要约束 LLM？

因为约束让其他一切变便宜。封闭词汇表意味着 LLM 的输出可 schema 校验、可哈希、可
diff、可签署；意味着"模型的答案"是 review 者真能读完的一小份 JSON，而不是 200 行必须
逐行审计的 R；意味着失败模式从**悄悄错**变成**大声弃权**——这是监管编程唯一负担得起
的失败模式。

LLM 是译者，不是作者。代码由编译器写，放不放行由门决定。spec 有歧义的时候，系统会
说出来——在三个真实递交数据集上，带着回执，还带着一份证明"门越量越锋利"的 findings
登记册。

---

- 仓库（MIT）：`pak::pak("yanmingyu92/admiralagent")`，GitHub 搜 admiralagent
- 完整证据链：`demo/automation/REPORT.md` + `demo/automation/out/`（一条命令复现）
- 叙事版 showcase：包站点 articles/cdisc-pilot-showcase
