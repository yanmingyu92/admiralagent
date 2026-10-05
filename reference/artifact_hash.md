# Artifact hash

Hashes the canonical JSON of the IR (preserving variable and step
order); used in deterministic artifact file names so identical IRs
always overwrite the same files. The package version is deliberately NOT
part of the hash: it is recorded as provenance in sidecars/manifests
instead, so a version bump never silently moves artifact identities.

## Usage

``` r
artifact_hash(ir)
```

## Arguments

- ir:

  List of \`aa_variable_ir\` objects.

## Value

An 8-character hash string.

## Details

Deterministic hash of a variable IR
