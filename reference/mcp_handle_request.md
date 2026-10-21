# Handle one MCP / JSON-RPC 2.0 request

Dispatches a parsed JSON-RPC 2.0 request list against the admiralagent
MCP methods: \`initialize\`, \`notifications/initialized\`,
\`tools/list\`, and \`tools/call\`. Tool results are wrapped as MCP text
content ({content: \[{type: "text", text: \<json\>}\], isError: false});
tool execution errors come back with \`isError: true\`. Unknown methods
return a JSON-RPC error (-32601), structurally invalid requests -32600.
The function is pure: it never touches stdin/stdout, so the whole server
can be unit-tested in-process.

## Usage

``` r
mcp_handle_request(req)
```

## Arguments

- req:

  Parsed request: a JSON-RPC 2.0 object as an R list (typically
  \`jsonlite::fromJSON(line, simplifyVector = FALSE)\`).

## Value

A JSON-RPC response list, or \`NULL\` for notifications (no response may
be sent).

## Examples

``` r
resp <- mcp_handle_request(list(
  jsonrpc = "2.0", id = 1, method = "tools/list"
))
vapply(resp$result$tools, function(t) t$name, character(1))
#> [1] "aa_classify"          "aa_validate_ir"       "aa_render_program"   
#> [4] "aa_dependency_report" "aa_evals"            
```
