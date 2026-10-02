#' Parse an ODM define.xml directly into a spec data frame
#'
#' @description Parses an ODM/define v2.0 define.xml with [xml2::read_xml()]
#'   without metacore: walks every `ItemGroupDef` (dataset) and its ordered
#'   `ItemRef` list, joins each `ItemDef` (variable name, label, type, length,
#'   origin, codelist reference) and resolves `MethodOID` links to `MethodDef`
#'   elements carrying the real derivation text. This is the primary engine
#'   behind [read_define()]; unlike the metacore fallback it preserves
#'   per-variable derivation text for define versions metacore does not map
#'   (e.g. the CDISC pilot submission defines, where every ItemRef carries a
#'   MethodOID).
#'
#'   Namespace handling is pragmatic: all lookups match by `local-name()` so
#'   the ODM default namespace and the `def:` prefix version do not matter.
#' @title Parse define.xml
#' @param path Path to a define.xml file.
#' @return A spec data frame compatible with [read_spec_df()] with columns
#'   `dataset`, `variable`, `label`, `type`, `length`, `origin`, `derivation`,
#'   `order` plus `codelist_oid` (the CodeList OID per variable, `NA` when the
#'   variable has no CodeListRef). The data frame carries a `dataset_labels`
#'   attribute: a named character vector of dataset labels from the
#'   ItemGroupDef descriptions.
#' @keywords internal
#' @examples
#' \dontrun{
#' spec <- parse_define("define.xml")
#' nrow(spec[spec$dataset == "ADSL" & !is.na(spec$derivation), ])
#' }
parse_define <- function(path) {
  assert_path(path)
  if (!requireNamespace("xml2", quietly = TRUE)) {
    stop("parse_define() needs package 'xml2'.", call. = FALSE)
  }
  if (!file.exists(path)) {
    stop("define file not found: ", path, call. = FALSE)
  }
  doc <- tryCatch(
    xml2::read_xml(path),
    error = function(e) {
      stop(
        "cannot parse define file as XML: ", conditionMessage(e), call. = FALSE
      )
    }
  )

  child1 <- function(node, name) {
    xml2::xml_find_first(node, sprintf("./*[local-name()='%s']", name))
  }
  kids <- function(node, name) {
    xml2::xml_find_all(node, sprintf("./*[local-name()='%s']", name))
  }
  text_or_na <- function(el) {
    if (inherits(el, "xml_missing")) return(NA_character_)
    txt <- trimws(xml2::xml_text(el))
    if (!nzchar(txt)) NA_character_ else txt
  }

  method_defs <- xml2::xml_find_all(doc, "//*[local-name()='MethodDef']")
  method_text <- if (length(method_defs) > 0) {
    txt <- trimws(xml2::xml_text(method_defs))
    setNames(ifelse(nzchar(txt), txt, NA_character_), xml2::xml_attr(method_defs, "OID"))
  } else {
    character(0)
  }

  item_defs <- xml2::xml_find_all(doc, "//*[local-name()='ItemDef']")
  if (length(item_defs) == 0) {
    stop("no ItemDef elements found; not an ODM define.xml? ", path, call. = FALSE)
  }
  item_oid <- xml2::xml_attr(item_defs, "OID")
  item_info <- lapply(item_defs, function(it) {
    origin <- child1(it, "Origin")
    cl_ref <- child1(it, "CodeListRef")
    list(
      name = xml2::xml_attr(it, "Name"),
      datatype = xml2::xml_attr(it, "DataType"),
      length = suppressWarnings(as.integer(xml2::xml_attr(it, "Length"))),
      label = text_or_na(child1(child1(it, "Description"), "TranslatedText")),
      origin = if (inherits(origin, "xml_missing")) NA_character_ else xml2::xml_attr(origin, "Type"),
      codelist_oid = if (inherits(cl_ref, "xml_missing")) NA_character_ else xml2::xml_attr(cl_ref, "CodeListOID")
    )
  })
  names(item_info) <- item_oid

  group_defs <- xml2::xml_find_all(doc, "//*[local-name()='ItemGroupDef']")
  if (length(group_defs) == 0) {
    stop("no ItemGroupDef elements found; not an ODM define.xml? ", path, call. = FALSE)
  }

  rows <- list()
  dataset_labels <- character(0)
  for (gd in group_defs) {
    ds_name <- xml2::xml_attr(gd, "Name")
    if (is.na(ds_name) || !nzchar(ds_name)) next
    ds_label <- text_or_na(child1(child1(gd, "Description"), "TranslatedText"))
    dataset_labels[[ds_name]] <- if (is.na(ds_label)) ds_name else ds_label

    refs <- kids(gd, "ItemRef")
    if (length(refs) == 0) next
    ref_oid <- xml2::xml_attr(refs, "ItemOID")
    ref_order <- suppressWarnings(as.integer(xml2::xml_attr(refs, "OrderNumber")))
    ref_method <- xml2::xml_attr(refs, "MethodOID")
    ord <- order(ref_order, na.last = TRUE, method = "radix")

    for (j in ord) {
      info <- item_info[[ref_oid[[j]]]]
      if (is.null(info)) next
      rows[[length(rows) + 1]] <- data.frame(
        dataset = ds_name,
        variable = info$name,
        label = info$label,
        type = map_define_type(info$datatype),
        length = info$length,
        origin = info$origin,
        derivation = if (is.na(ref_method[[j]])) {
          NA_character_
        } else {
          hit <- method_text[ref_method[[j]]]
          if (is.na(hit)) NA_character_ else unname(hit)
        },
        codelist_oid = info$codelist_oid,
        order = if (is.na(ref_order[[j]])) NA_integer_ else ref_order[[j]],
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0) {
    stop("define.xml contained no variable rows: ", path, call. = FALSE)
  }
  out <- do.call(rbind, rows)
  out <- out[!is.na(out$variable) & nzchar(out$variable), , drop = FALSE]
  out <- read_spec_df(out)
  out <- out[, c("dataset", "variable", "label", "type", "length",
                 "origin", "derivation", "order", "codelist_oid")]
  attr(out, "dataset_labels") <- dataset_labels
  out
}

map_define_type <- function(datatype) {
  dt <- tolower(ifelse(is.na(datatype), "text", datatype))
  ifelse(
    dt %in% c("date", "datetime", "partialdate", "partialdatetime",
              "incompletedatetime", "durationdatetime", "incompletedate"),
    "datetime",
    dt
  )
}
