# MCP server setup — admiralagent

`admiralagent` ships a stdio MCP server (protocol `2024-11-05`, newline-delimited
JSON-RPC 2.0) exposing the package's deterministic tools: spec classification,
IR validation, admiral code rendering, dependency reporting, and the rules
evals. No network, no LLM, no API keys — everything runs locally through
base R + jsonlite + digest.

## Run it

```sh
Rscript <path-to-admiralagent>/tools/mcp_server.R
```

The entry script works both from the package source tree (it sources `R/*.R`
relative to itself) and from an installed package (`library(admiralagent)`).
It reads one JSON-RPC request per line from stdin and writes one response
line per request to stdout; EOF ends the process.

Quick smoke test:

```sh
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
  Rscript tools/mcp_server.R
```

## Register with Claude Code

Add to `.mcp.json` (project) or `~/.claude.json` (user config):

```json
{
  "mcpServers": {
    "admiralagent": {
      "command": "Rscript",
      "args": ["C:/Users/you/path/to/admiralagent/tools/mcp_server.R"]
    }
  }
}
```

Generic MCP clients: use `command = Rscript`, `args = [<absolute path to
tools/mcp_server.R>]`, transport `stdio`. On Windows, quote the path and
prefer forward slashes.

## Tools

| Tool | Input | Output |
|---|---|---|
| `aa_classify` | `{dataset, spec_rows[]}` (row fields: `dataset?`, `variable`, `label`, `type`, `origin`, `derivation`, `source_dataset?`, `source_variable?`) | `{ir: [...], problems: string[]}` — rules-backend classification + `validate_ir()` gate |
| `aa_validate_ir` | `{ir: [...]}` (variable IR: `dataset`, `variable`, `steps[{layer, args, on?}]`, `confidence`, `needs_human`, `rationale`, `spec_origin`) | `{valid: bool, problems: string[]}` — same parse/normalize path as LLM output (step-level `on` is absorbed into `args`) |
| `aa_render_program` | `{ir: [...], backend_label?}` | `{code: string, hash: string(8), warnings: string[]}` — deterministic admiral program with `# CHECK:` comments and DISCLAIMER header |
| `aa_dependency_report` | `{ir: [...], known_columns?: string[]}` | rows `[{variable, input, dataset, issue}]` — inputs no spec/step/known column provides |
| `aa_evals` | `{}` | `{cases: n, rules_accuracy: number, failures: array}` — bundled spec-to-IR corpus vs the rules backend |

## Example calls

Handshake, then list tools:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
```

Classify one spec row:

```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"aa_classify","arguments":{
  "dataset":"ADSL",
  "spec_rows":[{"variable":"TRTSDTM","label":"Date of First Study Treatment","type":"datetime",
    "origin":"Derived","derivation":"Date of first study treatment, imputed from DM RFSTDTC",
    "source_dataset":"dm","source_variable":"RFSTDTC"}]
}}}
```

Validate an IR (JSON array shaped like the `aa_classify` output), render it to
admiral code, and check dependencies:

```json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"aa_render_program","arguments":{
  "ir":[{"dataset":"ADSL","variable":"TRTSDTM","steps":[{"layer":"impute_dtc","args":{
    "target":"TRTSDTM","dtc":"RFSTDTC","output_class":"dtm","highest_imputation":"M","date_imputation":"first"}}],
    "confidence":0.9,"needs_human":false,"rationale":"impute DM RFSTDTC","spec_origin":"..."}]
}}}
```

Run the evals:

```json
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"aa_evals","arguments":{}}}
```

## Protocol notes

- Responses are single-line JSON on stdout, flushed immediately; stderr is
  ignored by clients and used by R for warnings.
- Tool failures inside a tool (e.g. IR fails to render) come back as a normal
  tool result with `isError: true`; unknown tools/methods/malformed lines are
  JSON-RPC errors (`-32602` / `-32601` / `-32700` / `-32600`).
- The server never receives patient data: tools operate on schema-level spec
  text and layer IR only.
