# Write program artifact

Renders the full program via \[render_program()\], writes it as
\`\<dataset\>\_\_program\_\_\<hash8\>.R\` with a JSON sidecar, and
appends a \`write_program\` entry to the run log.

## Usage

``` r
write_program_artifact(
  ir,
  dir = "gen",
  backend_label = "rules",
  model = NULL,
  gate = NULL,
  require_gate = NULL
)
```

## Arguments

- ir:

  Non-empty list of \`aa_variable_ir\` objects.

- dir:

  Output directory (created when missing).

- backend_label:

  Backend label recorded in header and sidecar.

- model:

  Model identifier recorded in the sidecar (LLM backend).

- gate:

  Optional approval gate from \`sign_gate()\`, recorded in the program
  header, the sidecar and the run log. A gate names a signer, a moment
  and a reason; it is not a claim that any derivation is correct.

- require_gate:

  Whether a covering approval gate is mandatory. \`NULL\` (default)
  reads \`getOption("admiralagent.require_gate", TRUE)\`: enforcement is
  ON out of the box, so an ungated write is refused and the refusal
  itself is logged.

  Writing ungated requires an explicit opt-out - \`require_gate =
  FALSE\` on the call, or the option switched off for the session - and
  is never silent: the rendered program carries an \`UNGATED DRAFT\`
  banner, the sidecar and the audit record carry \`release_grade =
  "ungated-draft"\` and \`gate_enforced = FALSE\`, and the first ungated
  write of a session prints a notice. An ungated artifact is never
  release-grade.

## Value

Invisibly, the character vector of files written.

## Details

Write the assembled program artifact
