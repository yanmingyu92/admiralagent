# Run the admiralagent MCP stdio server

Blocking newline-delimited JSON-RPC 2.0 loop over stdin/stdout (MCP
stdio transport, protocol version 2024-11-05). One request per line in,
zero or one response line out, flushed immediately. EOF on stdin ends
the loop cleanly. Refuses to run in interactive sessions so an
accidental call cannot hang the console. Meant to be launched via
\`Rscript tools/mcp_server.R\`.

## Usage

``` r
mcp_serve()
```

## Value

Invisible \`NULL\` when stdin reaches EOF.
