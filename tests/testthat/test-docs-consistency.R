# Documentation consistency gates (drift guards).
#
# The single-source-of-truth rule (AGENTS.md hard rule 1) only works if the
# documents that REFERENCE the truth are machine-checked against it. These
# tests pin the seams where docs have drifted before (A15; the removed
# `warnings` field lingering in demo/mcp_setup.md).
#
# Scope notes:
# - The layer vocabulary itself is already single-sourced: build_system_prompt()
#   injects layer_docs() at runtime, so no generated copies exist to test.
# - Root docs (AGENTS.md, README.md, demo/mcp_setup.md) are excluded from the
#   package build, so their checks run in dev-source mode and skip under an
#   installed test_check(); inst/skills/ ships with the package and is always
#   checked.

# Locate the source-tree root (dev mode) or NULL (installed test_check()).
docs_root <- function() {
  root <- file.path("..", "..")
  if (file.exists(file.path(root, "AGENTS.md"))) root else NULL
}

# Exported names, in both modes: namespace when installed, NAMESPACE file when
# running against a source tree.
exported_names <- function() {
  ns <- tryCatch(getNamespaceExports("admiralagent"), error = function(e) NULL)
  if (!is.null(ns)) return(ns)
  ns_file <- file.path("..", "..", "NAMESPACE")
  skip_if_not(file.exists(ns_file), "NAMESPACE not reachable")
  gsub("^export\\((.+)\\)$", "\\1", grep("^export\\(", readLines(ns_file), value = TRUE))
}

# Tokens of the form admiralagent::foo in a text.
doc_fn_tokens <- function(text) {
  m <- gregexpr("admiralagent::[A-Za-z][A-Za-z0-9_.]*", text)
  unique(sub("admiralagent::", "", regmatches(text, m)[[1]]))
}

test_that("every admiralagent::fn referenced in SKILL.md is exported", {
  path <- system.file("skills", "spec-to-adam", "SKILL.md", package = "admiralagent")
  if (!nzchar(path)) path <- file.path("..", "..", "inst", "skills", "spec-to-adam", "SKILL.md")
  skip_if_not(file.exists(path), "SKILL.md not reachable")
  refs <- doc_fn_tokens(paste(readLines(path, warn = FALSE), collapse = "\n"))
  expect_true(length(refs) > 0)
  bad <- setdiff(refs, exported_names())
  expect_equal(bad, character(0), info = paste("SKILL.md references non-exports:", bad))
})

test_that("every admiralagent::fn referenced in root docs is exported", {
  root <- docs_root()
  skip_if(is.null(root), "source tree not reachable (installed test_check)")
  for (doc in c("AGENTS.md", "README.md", file.path("demo", "mcp_setup.md"))) {
    path <- file.path(root, doc)
    skip_if_not(file.exists(path))
    refs <- doc_fn_tokens(paste(readLines(path, warn = FALSE), collapse = "\n"))
    bad <- setdiff(refs, exported_names())
    expect_equal(bad, character(0), info = paste(doc, "references non-exports:", bad))
  }
})

# First balanced {...} group in a string (the field list in a table cell).
first_brace_fields <- function(cell) {
  m <- regmatches(cell, regexpr("\\{[^{}]*\\}", cell))
  if (length(m) == 0 || !nzchar(m)) return(character(0))
  toks <- regmatches(m, gregexpr("[A-Za-z_][A-Za-z0-9_]*", m))[[1]]
  setdiff(toks, c("string", "strings", "bool", "boolean", "number", "array",
                  "object", "null", "n", "chars"))
}

# Table rows of demo/mcp_setup.md, keyed by tool name.
mcp_doc_rows <- function(path) {
  lines <- readLines(path, warn = FALSE)
  rows <- grep("^\\| `aa_", lines, value = TRUE)
  out <- list()
  for (r in rows) {
    cells <- strsplit(r, "\\|")[[1]]
    cells <- trimws(cells[nzchar(trimws(cells))])
    name <- gsub("`", "", cells[1])
    out[[name]] <- list(input = cells[2], output = cells[3])
  }
  out
}

# Documented OUTPUT fields per tool, pinned to the current contracts. When a
# tool's output changes, update this map deliberately in the same commit.
MCP_DOC_OUTPUT_FIELDS <- list(
  aa_classify = c("ir", "problems"),
  aa_validate_ir = c("valid", "problems"),
  aa_render_program = c("code", "hash"),
  aa_dependency_report = c("variable", "input", "dataset", "issue"),
  aa_evals = c("cases", "rules_accuracy", "failures")
)

test_that("mcp_setup.md tool table matches mcp_tool_specs()", {
  root <- docs_root()
  skip_if(is.null(root), "source tree not reachable (installed test_check)")
  path <- file.path(root, "demo", "mcp_setup.md")
  skip_if_not(file.exists(path))
  rows <- mcp_doc_rows(path)
  specs <- mcp_tool_specs()

  # Tool names: exact match, no extras either way.
  expect_setequal(names(rows), names(specs))

  for (tool in names(specs)) {
    schema_fields <- names(specs[[tool]]$inputSchema$properties)
    doc_input <- first_brace_fields(rows[[tool]]$input)
    # Documented input fields must exist in the schema ...
    expect_true(all(doc_input %in% schema_fields),
                info = paste(tool, "documents unknown input fields:",
                             setdiff(doc_input, schema_fields)))
    # ... and every schema field must be mentioned in the doc row.
    expect_true(all(schema_fields %in% c(doc_input, unlist(strsplit(rows[[tool]]$input, "[^A-Za-z0-9_]+")))),
                info = paste(tool, "schema fields missing from docs:",
                             setdiff(schema_fields, doc_input)))
    # Output fields match the pinned contract (catches removed-field drift
    # like the `warnings` incident).
    expect_setequal(first_brace_fields(rows[[tool]]$output),
                    MCP_DOC_OUTPUT_FIELDS[[tool]])
  }
})

test_that("SKILL.md frontmatter keeps name and description", {
  path <- system.file("skills", "spec-to-adam", "SKILL.md", package = "admiralagent")
  if (!nzchar(path)) path <- file.path("..", "..", "inst", "skills", "spec-to-adam", "SKILL.md")
  skip_if_not(file.exists(path), "SKILL.md not reachable")
  head_lines <- head(readLines(path, warn = FALSE), 5)
  expect_true(any(grepl("^name: spec-to-adam", head_lines)))
  expect_true(any(grepl("^description: ", head_lines)))
})
