# Tool specifications for the admiralagent MCP server

Defines the five deterministic tools exposed over MCP stdio:
\`aa_classify\`, \`aa_validate_ir\`, \`aa_render_program\`,
\`aa_dependency_report\`, and \`aa_evals\`. Every tool is pure
base-package logic (no network, no LLM): spec rows in, layer IR /
admiral code / validation problems out.

## Usage

``` r
mcp_tool_specs()
```

## Value

A named list of tool definitions, each with \`name\`, \`description\`,
and \`inputSchema\` (a JSON-Schema-style list).
