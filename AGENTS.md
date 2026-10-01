# AGENTS.md — admiralagent 开发约定

## 项目是什么

R 包：把 P21 风格 ADaM spec（自由文本派生描述）翻译为可执行 admiral
代码 + 验证注释。 LLM 只输出封闭词汇表内的 Layer
IR（JSON），代码由确定性模板生成。LLM 永远不直接写 R 代码。

## 硬性规则

1.  注册表是唯一事实源：变量派生层用 `R/layers.R` 的
    [`aa_layers()`](https://yanmingyu92.github.io/admiralagent/reference/aa_layers.md)；分析结果
    IR（`aa_analysis_ir`，DESIGN.md §10）用 `R/analysis_ir.R` 的
    `aa_operations()`。新增/修改层或操作 =
    改对应注册表（args/required/render/checks/rank），并同步测试。
2.  不引入 `ellmer`/`metacore`/`admiral` 为强依赖（放
    Suggests）。核心（IR 校验、codegen、artifacts）必须只靠 base +
    glue/jsonlite/digest 可测试。
3.  所有生成给用户的代码必须带 `# CHECK:` 验证注释与 DISCLAIMER 头。
4.  任何 LLM 输出必须经过
    [`validate_ir()`](https://yanmingyu92.github.io/admiralagent/reference/validate_ir.md)；校验失败不猜测、不修复，返回错误或置
    `needs_human`。
5.  不在 prompt、日志、sidecar
    中放入任何患者数据；[`build_context()`](https://yanmingyu92.github.io/admiralagent/reference/build_context.md)
    只输出 schema 级信息。
6.  产物文件名确定性：`<dataset>__<variable>__<hash8>.R`，同 IR
    覆盖写，不堆积副本。

## 代码风格

- tidyverse 风格；管道用 `|>`；对象名 snake_case。
- 导出函数必须 roxygen（@export @title @description @param @return）。
- 生成模板内注释是产品功能（CHECK 注释），不属于”多余注释”。

## 测试

    Rscript -e "testthat::test_dir('tests/testthat', reporter='summary')"

无需网络、无需 API key、无需 ellmer/metacore。改 layers.R
后必须全绿再提交。

## Improvement loop（强制惯例）

每个迭代周期执行：探针 → 发现 → 修复 → 回归。

1.  探针：`demo/demo_llm_exec.R`（真实数据执行 LLM 产物）+
    `demo/demo_real.R`
2.  每个 ERROR/FAIL/MANUAL 都登记为 finding，编号归档
3.  修复必须三层齐动：语义校验（validate_ir / dependency report）+
    prompt 规则（build_system_prompt）+ 回归测试
4.  历史经验（勿重蹈）：
    - LLM 会把 `on` 放在 step 层而不是 args 内 →
      `normalize_ir_records()`（R/safety.R） 已把 step 级 `on` 吸收进
      args，并在与 args\$on 冲突时报错
    - fromJSON simplifyVector=FALSE 把数组变 list → new_step 已归一化 +
      vector_args 类型校验
    - LLM 会用 assign 拉跨数据集值、把 compute_param 直接放 ADSL → BDS
      黑名单 + foreign-only 校验 + prompt 规则
    - admiral 大版本会重命名参数（1.5: new_vars_prefix、set_values_to
      内公式）→ 只改 layers.R 模板，IR 不动
    - 旧产物重读必须过 read_artifact 归一化，坏产物会被 gate
      拦截（预期行为）
    - LLM 会在 merge 改名后仍引用旧列名 →
      `renamed_column_problems()`（R/ir.R） 门内追踪
      merge_var/lookup_join 的 source→target
      改名，引用旧名报出新名（F-01）
    - 非 ADSL 数据集的 LLM 批次会照抄 prompt 示例的 “ADSL” →
      [`build_context()`](https://yanmingyu92.github.io/admiralagent/reference/build_context.md)
      每变量带 dataset 字段（F-06）；目标数据集基座域的列会被误用
      merge_var 自并 （occurrence 数据 by 键重复，duplicate_records
      关门）→ prompt 规则 5： 同域基座列必须 assign 直拷（F-10）

## 常用入口

- [`mock_spec_adsl()`](https://yanmingyu92.github.io/admiralagent/reference/mock_spec_adsl.md)
  示例 spec
- `classify_variables(spec, dataset, backend = "rules"|"llm")`
- `render_program(ir)` / `render_variable(ir)`
- `run_validation(data, ir)`、`write_artifact(ir, dir = "gen")`
