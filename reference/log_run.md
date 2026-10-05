# Log a run

Appends one JSON line (schema, sequence number, timestamp, package
version, event, details, previous digest, digest mode, digest) to a
hash-chained JSONL audit log. Each record seals the digest of the record
before it, so editing, deleting or reordering any line is detectable
with \[verify_log()\]. When a key is configured
(\`admiralagent.log_key\` option or \`ADMIRALAGENT_LOG_KEY\`) the digest
is an HMAC and the record records that mode, so a keyed log can never be
silently continued unkeyed.

## Usage

``` r
log_run(event, details = list(), file = aa_log_file())
```

## Arguments

- event:

  Event name (e.g. \`"write_program"\`, \`"execute_variable"\`).

- details:

  List of event-specific details. Never put patient data here.

- file:

  Log file path; defaults to the active audit log (see
  \`admiralagent.log_file\`).

## Value

Invisibly \`TRUE\`.

## Details

Append an entry to the audit log
