# Read define.xml

Primary path: parses the define.xml directly with \[parse_define()\]
(requires the \`xml2\` package), which preserves the per-variable
derivation text from \`MethodDef\` elements - metadata that
\[metacore::define_to_metacore()\] drops for some define versions (e.g.
the CDISC pilot submission defines). Fallback path: when the direct
parser fails (missing \`xml2\`, malformed XML, non-ODM structure), the
file is re-parsed via metacore and flattened through \`spec_as_df()\`,
whose \`derivation\` column may then be empty. When both paths fail an
informative error is raised.

## Usage

``` r
read_define(path)
```

## Arguments

- path:

  Path to the define.xml file.

## Value

A spec data frame as produced by \[read_spec_df()\]; the primary path
additionally returns \`codelist_oid\` and \`order\` columns.

## Details

Read a define.xml metadata file

## Examples

``` r
# Write a minimal one-variable define.xml to a temp directory and read it:
define_txt <- paste(
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<ODM ODMVersion="1.3.2" xmlns="http://www.cdisc.org/ns/odm/v1.3">',
  '  <Study OID="STD1"><MetaDataVersion OID="MDV1">',
  '    <ItemGroupDef OID="IG.ADSL" Name="ADDSL" SASDatasetName="ADSL">',
  '      <Description><TranslatedText>Subject-Level</TranslatedText></Description>',
  '      <ItemRef ItemOID="IT.STUDYID" OrderNumber="1" MethodOID="MT.STUDYID"/>',
  '    </ItemGroupDef>',
  '    <ItemDef OID="IT.STUDYID" Name="STUDYID" DataType="text" Length="12">',
  '      <Description><TranslatedText>Study Identifier</TranslatedText></Description>',
  '    </ItemDef>',
  '    <MethodDef OID="MT.STUDYID" Name="STUDYID" Type="Computation">',
  '      <Description><TranslatedText>',
  '        Copied directly from DM.STUDYID',
  '      </TranslatedText></Description>',
  '    </MethodDef>',
  '  </MetaDataVersion></Study>',
  '</ODM>',
  sep = "\n"
)
f <- file.path(tempdir(), "define.xml")
writeLines(define_txt, f)
spec <- read_define(f)
spec[, c("dataset", "variable", "derivation")]
#>   dataset variable                      derivation
#> 1   ADDSL  STUDYID Copied directly from DM.STUDYID
```
