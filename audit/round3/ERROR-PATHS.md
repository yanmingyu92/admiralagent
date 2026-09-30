# 本轮新增错误路径清单

静态分支总清单：error-branches.json。以下路径在 before-src/tests 中缺少对应专项回归，本轮由 tests/testthat/test-audit-round3.R 覆盖。不是分支覆盖率百分比。

| 错误/边界路径 | 专项回归 |
|---|---|
| dt 模式清理错误的 TMF 列 | date-only reruns preserve unrelated time flags |
| dt 模式提供 time_imputation | date-only imputation cannot silently ignore a time rule |
| finalize NULL/NA/多值/矩阵 | program finalize requires a scalar logical |
| backend_label 空/NA/非字符串 | program backend label rejects nonstrings and missing values |
| run_validation quiet 非标量 | validation quiet reports the offending public argument |
| execute_ir quiet 矩阵 | execution quiet rejects matrix flags |
| installed 错类型/空/多版本/非法版本 | compatibility installed has a bounded version contract |
| order_variables known_columns 错类型 | ordering rejects malformed known_columns |
| dependency report known_columns 错类型 | dependency reporting rejects malformed known_columns |
| needs_human 矩阵 | IR scalar and vector fields reject matrices |
| assign.from 字符矩阵 | IR scalar and vector fields reject matrices |
| categorize.right 逻辑矩阵 | IR scalar and vector fields reject matrices |
| spec 重复列名 | spec ingestion rejects duplicate names and nonscalar cells |
| spec 列含嵌套 list 或 matrix | spec ingestion rejects duplicate names and nonscalar cells |

另外新增 240 个固定种子 JSON mutation 样本；保留全部旧错误路径、注入、执行隔离和 Oracle 测试。没有更改已有测试预期。