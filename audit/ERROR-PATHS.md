# 新增错误路径与验证清单

测试文件：`tests/testthat/test-audit-security.R`。新增 10 个 test_that 块；以下分支通过循环覆盖，不以测试块数冒充分支覆盖率。

| 路径 | 校验与预期 |
|---|---|
| filter/formula 调用 system/get | validate_ir 拒绝，公开 render/execute gate 拦截 |
| 分号、多语句、花括号、管道 | 拒绝 |
| <- / <<- / = 赋值 | 拒绝；未执行外部命令 |
| 命名空间、索引、$、反引号、注释 | 拒绝 |
| Unicode 分隔符、未配对括号 | 拒绝 |
| target/from 标识符注入 | 拒绝 |
| literal 引号、反斜线、换行、中文 | 原样作为值往返，不成为代码 |
| spec_origin/rationale 换行 | 每行继续注释，无环境变量写入 |
| dataset/variable 非标量或非法名称 | 返回可读问题向量 |
| needs_human NA、confidence Inf | 返回可读问题向量 |
| NULL/原子 step、未知/多值 layer | 返回可读问题向量 |
| 原子 args、未知 arg、嵌套 NULL | 返回可读问题向量 |
| 空 steps 且 needs_human=false | 拒绝 |
| 17000 字节字符串、Unicode 标识符 | 拒绝 |
| args$on 代码片段 | 拒绝 |
| 错误 sources 类型或非 data.frame base | 明确数据类型错误 |
| sources 覆盖 exprs/params/target | 拒绝 |
| variables 不存在或空选择 | 不存在拒绝；空选择返回固定结构的 0 行 status |
| 隐式读取外部全局 AGE | 不可见；缺列报告 ERROR |
| dtm_to_dt 目标不一致 | 拒绝 |
| impute_dtc target==dtc | 执行前拒绝，不删除输入 |
| 重复 Inf breaks | 拒绝且不崩溃 |
| JSON 顶层 null/数字、原子 step/args | 解析失败返回 NULL，后续 gate 拒绝 |
| compute_param 直接用于 ADSL | 拒绝，提示使用 BDS source + merge_var |
| compute_param 裸参数名 WEIGHT | 拒绝，仅 AVAL.WEIGHT 合法 |
| 导出 API 错路径/数据框/列 | 明确指出 path、spec、data.frame 或所需列 |
| compute_var 自引用输入 | 守卫保留输入，X+1 可执行 |
| 安全算术分组括号 | 接受，仍拒绝函数调用 |

另外，以种子 20260917 对 320 个经 JSON 序列化/反序列化的随机畸形 IR 运行 validate_ir，逐个检查 character 结果、至少一条错误及非空错误文本。此清单是错误分支测试清单，不宣称全包 100% 分支覆盖。