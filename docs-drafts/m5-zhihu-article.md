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
`categorize`、`compute_param`……一共十几种推导层，多一个都没有。

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
**DeepSeek**（`deepseek-chat`，走 {ellmer}）。每个数据集另取 12 个变量的确定性子集做
3 采样多数票（consensus）。

## 四、真实数字（先念边界，再念数字）

先说两条跟每个数字绑定的边界：产出数据集**不做人口子集**（产出的 ADSL 有 306 行，
oracle 是 254 例随机化人群；产出的 ADLBC 59580 行 vs oracle 37132 行），agreement 只在
join 上的记录里算；这是和单个 oracle 的自评对比，**不等于双程编程**。

| 数据集 | 后端 | spec 变量 | 弃权(needs_human) | 执行 | oracle 可比 | 完全一致 | 均值 |
|---|---|---|---|---|---|---|---|
| ADSL | rules | 49 | 32 | 16 | 15 | **15 (100%)** | 100.0% |
| ADSL | DeepSeek | 49 | 25 | 21 | 20 | **16** | 91.4% |
| ADAE | rules | 55 | 16 | 27 | 20 | **20 (100%)** | 100.0% |
| ADAE | DeepSeek | 55 | 6 | 33 | 27 | **25** | 96.3% |
| ADLBC | rules | 46 | 14 | 15 | 14 | **12** | 85.8% |
| ADLBC | DeepSeek | 46 | 15 | 19 | 19 | **19 (100%)** | 100.0% |

几个要点：

- rules 基线在 ADSL 上弃权近三分之二，但只要它敢做的，三个数据集上**全对**
  （ADLBC 的 85.8% 是被一个 spec 文本缺陷拖下来的，见第六节）。
- DeepSeek 在 ADSL/ADAE 上都比基线多做（ADAE 只弃权 6/55）。ADLBC 这一轮它的覆盖率
  反而**下降**（执行 22→19）但准确率升到 **19/19 全对**——这是运行间方差，不是回退
  （limitation 8）；其中之一是模型这轮拒绝照字面执行 spec 里写错的 BASE 推导（见 F-09）。
- 双后端层链一致率 ADSL 80% / ADAE 58% / ADLBC 52%——这是"两个译者读同一份文本"的
  一致性度量，**明确不是正确性声明**；3 采样共识在三个数据集的 12 变量子集上全部
  12/12 全票；consensus 后端对 oracle 的比较结果是 ADSL 15/15=100%、ADAE 26/26=100%、
  ADLBC 12/14=85.8%（consensus 的 oracle 比较覆盖全 spec、套用子集投票结果，分母与
  12 变量漏斗不同，by design）。
- LLM 边际成本：单个数据集全量 **91–126 秒、0.010–0.013 美元**；本文这轮实测把三个
  数据集的全量+共识全部重新跑了一遍，合计约 **0.053 美元**（不到四毛人民币）；rules
  基线约 0.1 秒、零成本。

但头条数字仍然是弃权那一列，不是准确率那一列。

## 五、边界即卖点：25 次弃权，次次有理由

DeepSeek 在 ADSL 上拒答了 49 个变量里的 25 个。翻开弃权清单，它不是随机的——那是
被大声说出来的词汇表边界，而且在另外两个数据集上以不同的口音重复：

- **记录存在性/访视窗口逻辑仍不可表达**：COMP8/16/24FL 访视窗口旗标、EFFFL（跨
  数据集存在性检查）、VISNUMEN。这些仍然是真正的词汇表空洞。
- **缺失值判断不可表达**：SAFFL（TRTSDT 非缺失则为 Y）弃权，因为过滤器子语言里
  没有 `is.na()`。
- **引用外部材料的弃权**：SAP 章节（SITEGR1）、spec 没给的 codelist（TRT01PN、
  DCSREAS、ADLBC 的 PARAMN）。
- **缺词汇就如实说缺**：ADLBC 的 PARAM 需要字符串拼接（"LBTEST (LBSTRESU)"），
  词汇表没有函数调用，弃权；ALBTRVAL 要 `max()`，同样弃权。
- **多分支临床逻辑**（CUMDOSE 按组别分段的剂量规则）弃权。

一个会对这些变量硬编答案的系统，严格地比一个会弃权的系统更差。在审计叙事里，
"机器说了 25 次'我不知道'，每次都带理由"，是一条你能站得住的特性。

## 六、我们加了条件层。9 个变量里落地了 1 个。

词汇表最近一次扩张是第 15 层 `assign_conditional`——一个带守卫的
`Y if <条件> else <N>` 赋值，正是上面弃权最多的家族。评估笔记当时预测它能"确定转化
9 个里的 4 个"（ITTFL 直接转；EOSSTT、DISCONFL、DSRAEFL 走共享的上游链）。然后我们
强制全量重测，把实测结果如实登记为 finding F-11：

- **ITTFL 转化成功、执行成功、oracle 100% 一致。** 层本身是好用的。
- **EOSSTT 转化了但执行时 fail-closed**：它的 IR 依赖 DCDECOD，而这轮运行里 LLM 恰好
  对 DCDECOD 弃权——链条断在一个随机上游，事务守卫按设计拦下（上一轮 DCDECOD 是推导
  出来且 100% 一致的）。
- **DISCONFL 和 DSRAEFL 根本没转化。** "确定 4/9" 的预测在运行间方差面前偏乐观，
  findings 登记册里就是这么写的。

2/9 转化、1/9 端到端落地。我们考虑过不把这段放在开头讲，最后决定它是全文最有用的一
段：新增一层改变的是"**可表达**什么"，不是"某一次随机运行**选择**什么"——这正是共识
投票模式和 findings 登记册存在的理由。（rules 后端有意不用新层：evals 语料把它的弃权
pin 住当契约。零成本基线保持不动，是回归套件的特性，不是疏忽。）

## 七、错误分类学：连"错"都错得很有意思

- **HEIGHTBL/WEIGHTBL：原始一致率 19.7%/8.7%——但按 oracle 自己的存储精度算是
  98.8%/94.5%**（finding F-05）。数值溯源到的正是 spec 点名的 VS 记录；oracle 悄悄
  做了 1 位小数舍入，这个约定 spec 文本从没提过。推导是对的，沉默的是元数据。
- **AGEGR1N：在尝试推导它的那轮运行里，全部 11 例分歧都是恰好 80 岁的受试者**
  （F-04）。spec 原文同时写着"65–80"和">80"，自相矛盾；模型选了一种读法，递交选了
  另一种。人类程序员在这里也只能发 query。当前缓存的这轮运行里，模型对这个变量改为
  弃权——运行间方差如实记录在 limitation 8。
- **ADLBC 的 BASE/CHG 是 spec 文本的缺陷**（F-09）：工作簿里 BASE 的推导文本字面上
  就是 `LB.LBSTNRHI`（该记录自己的正常值上限），不是基线值。rules 基线仍照字面执行，
  一致率 0.4%；LLM 这一轮对 BASE **弃权**，理由写的是"likely improper mapping"——
  这正是人类程序员看到这句话会发的 query。
- **诚实的依赖级联**：ADAE/ADLBC 剩下的执行错误，大多是要 merge 的 ADSL 列恰好是
  ADSL 后端自己弃权的那些（TRTSDT、TRT01AN、RACEN、SAFFL……）——跨数据集推导的
  完整性以上游为上限。

这就是为什么流水线要和 oracle 比、而不是自称正确：自动化 showcase 的诚实产出是一份
**失败分类学**，不是一场庆功宴。

## 八、showcase 会审计自己：探针→发现→修复→回归

从 ADSL 扩到三个数据集之后，最意外的收获是流水线开始抓自己的 bug。findings 登记册
（`out/findings.json`，F-01 到 F-11）记录的不是一次性 demo，而是一个真实运转的改进
回路。已解决的几个值得展开：

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
禁止的。重跑实测：**ADAE 执行变量数 7→32、duplicate_records 25→0**；当前这轮（
`assign_conditional` 已在词汇表里）执行 33/55，oracle 27 可比 25 全对、均值 96.3%。

**F-02：codelist 从纸面变成可执行。** 模型为 RACEN/TRT01PN/TRT01AN 选了
`codelist_var` 层，但 showcase 从没构建过 metacore 对象，执行即报错。现在流水线把递交
工作簿的 `Codelists` 表转成每个数据集一个可执行 metacore（`out/mc_<ds>.rds`），直接
探针验证手工 IR 在 254 例 join 上 100% 吻合 oracle。诚实脚注：当前缓存的 LLM 运行对
这几个变量仍是弃权（运行间方差，limitation 8）——修复由探针验证，随时等任何一个选中
该层的 IR。

探针→登记 finding→修复→回归测试→重测——这个序列本身就是重点。本文的数字全是
**回路跑完之后**的数字，而这个回路是产品的一部分。

## 九、我们不声称什么

REPORT 的 limitations 是逐字保留、不可谈判的，压缩版：不做人口子集，agreement 只在
join 记录上算；词汇表缺口是硬边界，加投票者修不了（`assign_conditional` 这层现在有了，
但存在性/窗口、缺失值判断、多分支逻辑仍是洞）；rules 后端是关键词基线不是理解；
evals 语料是自评分（期望值由 rules 生成）的回归语料不是 oracle；IR 一致性 ≠ 双程编程
（所有投票者读同一份 spec）；oracle 分歧可能是 spec 歧义不是包错误；生成的程序是
UNGATED DRAFT，没有任何人工批准门覆盖，只是演示产物；单模型、三个数据集、有随机性
（ADSL 全量运行的弃权数在各轮间移动 24→22→27→25，层链一致率 78%→71%→82%→80%——
这正是共识投票模式存在的理由）；ValueLevel 元数据（全是 ADADAS）不在范围内。

## 十、为什么偏要约束 LLM？

因为约束让其他一切变便宜。封闭词汇表意味着 LLM 的输出可 schema 校验、可哈希、可
diff、可签署；意味着"模型的答案"是 review 者真能读完的一小份 JSON，而不是 200 行必须
逐行审计的 R；意味着失败模式从**悄悄错**变成**大声弃权**——这是监管编程唯一负担得起
的失败模式。这个月我们扩了一次词汇表，一次只加一层，测完把"预测和实测的差距"（F-11）
和胜利如实并排写在一起。

LLM 是译者，不是作者。代码由编译器写，放不放行由门决定。spec 有歧义的时候，系统会
说出来——在三个真实递交数据集上，带着回执，还带着一份证明"门越量越锋利"的 findings
登记册。

---

- 仓库（MIT）：`pak::pak("yanmingyu92/admiralagent")`，GitHub 搜 admiralagent
- 完整证据链：`demo/automation/REPORT.md` + `demo/automation/out/`（一条命令复现）
- 叙事版 showcase：包站点 articles/cdisc-pilot-showcase
