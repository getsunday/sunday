# Declarative plugin pages for Sunday.
#
# Plugins describe dashboard pages with the SundayKit `registerPages` DSL.
# The compiled JSON schema is embedded in the plugin binary. Sunday validates
# the schema, converts it to Tim Engine source, compiles it into its own
# backend Tim instance and serves the page through a host-owned route.
# Plugins never ship `.timl` files for pages.

import std/[json, strutils, tables]
import pkg/ozark/driver/psql
import pkg/ozark/model
import pkg/openparser/sql

const pluginPagesSchemaVersion* = 1

type
  PluginPageData* = object
    table*: string
    columns*: seq[string]
    columnTypes*: Table[string, string]
    orderColumn*: string
    orderDir*: string
    limit*: int
    dataKey*: string

  PluginPage* = object
    pluginId*: string
    pluginName*: string
    id*: string
    label*: string
    path*: string
    layout*: string
    viewKey*: string
    data*: PluginPageData
    body*: JsonNode

proc isSafeIdent*(value: string): bool =
  if value.len == 0: return false
  if value[0] notin Letters + {'_'}: return false
  for c in value:
    if c notin Letters + Digits + {'_'}: return false
  result = true

proc isSafePagePath*(value: string): bool =
  if not value.startsWith("/dashboard/"): return false
  if value.len <= "/dashboard/".len: return false
  if "{" in value or "}" in value or "?" in value or "#" in value: return false
  for c in value:
    if c notin Letters + Digits + {'_', '-', '/', '.'}: return false
  result = true

proc optStr*(node: JsonNode, key: string): string =
  ## Safely reads an optional string member.
  if node.kind == JObject and node.hasKey(key) and
      node[key].kind == JString:
    node[key].getStr
  else:
    ""

proc runtimeTables*(schemas: RuntimeSchemas): Table[string, Table[string, string]] =
  ## Flattens runtime model schemas to table -> column -> storage type name.
  for tableName, cols in schemas.schemas.pairs:
    var columns = initTable[string, string]()
    for colName, colDef in cols.pairs:
      var typeName = ""
      if colDef.sons.len >= 2:
        let typeNode = colDef.sons[1]
        case typeNode.kind
        of nkIdent: typeName = typeNode.strVal.toLowerAscii
        of nkCall:
          if typeNode.sons.len > 0 and typeNode.sons[0].kind == nkIdent:
            typeName = typeNode.sons[0].strVal.toLowerAscii
        else: discard
      columns[colName] = typeName
    result[tableName] = columns

proc validatePageNode*(node: JsonNode, dataKey: string,
    columns: seq[string], path: string): seq[string] =
  if node.kind != JObject or not node.hasKey("type") or
      node["type"].kind != JString:
    return @["page \"" & path & "\" contains an invalid node"]
  let nodeType = node["type"].getStr
  const known = ["heading", "text", "image", "icon", "badge", "link",
    "tabs", "row", "col", "card", "section", "divider", "alert",
    "grid", "for", "empty"]
  if nodeType notin known:
    return @["page \"" & path & "\" uses unknown element \"" & nodeType & "\""]
  template need(key: string) =
    if not node.hasKey(key):
      return @["page \"" & path & "\" element \"" & nodeType &
        "\" is missing \"" & key & "\""]
  case nodeType
  of "heading":
    need("level")
    need("text")
  of "text", "badge":
    if not node.hasKey("text") and not node.hasKey("bind"):
      return @["page \"" & path & "\" element \"" & nodeType &
        "\" needs text or a bind"]
  of "image":
    need("src")
  of "icon":
    need("name")
  of "link":
    need("label")
    need("href")
    if node["href"].kind != JObject or
        (not node["href"].hasKey("dashboard") and
         not node["href"].hasKey("literal")):
      return @["page \"" & path & "\" contains a link with an invalid href"]
  of "col":
    need("size")
  of "card", "tabs", "row", "section", "alert", "grid", "for", "empty":
    need("children")
  else: discard
  if nodeType in ["grid", "for"]:
    if not node.hasKey("in") or node["in"].getStr != dataKey:
      return @["page \"" & path & "\" loops over unknown data key"]
    if not node.hasKey("item") or not isSafeIdent(node["item"].getStr):
      return @["page \"" & path & "\" has an invalid loop item name"]
    if nodeType == "grid":
      if not node.hasKey("cols") or node["cols"].kind != JInt:
        return @["page \"" & path & "\" grid is missing its column count"]
  if nodeType == "empty":
    if not node.hasKey("key") or node["key"].getStr != dataKey:
      return @["page \"" & path & "\" has an invalid empty-state key"]
  for key in ["bind", "src", "alt"]:
    if node.hasKey(key) and node[key].kind == JObject and
        node[key].hasKey("bind"):
      let parts = node[key]["bind"].getStr.split('.')
      if parts.len != 2 or parts[1] notin columns:
        return @["page \"" & path & "\" binds unknown field \"" &
          node[key]["bind"].getStr & "\""]
  if node.hasKey("children"):
    if node["children"].kind != JArray:
      return @["page \"" & path & "\" element \"" & nodeType &
        "\" children must be an array"]
    for child in node["children"]:
      for message in validatePageNode(child, dataKey, columns, path):
        result.add(message)
  result

proc validatePageNodes*(nodes: JsonNode, dataKey: string,
    columns: seq[string], path: string): seq[string] =
  if nodes.kind != JArray:
    return @["page \"" & path & "\" body must be an array"]
  for node in nodes:
    for message in validatePageNode(node, dataKey, columns, path):
      result.add(message)
  result

proc resolvePageTable*(modelName: string,
    tables: Table[string, Table[string, string]]): string =
  ## Resolves a page model name to a runtime table name.
  if tables.hasKey(modelName):
    return modelName
  var snake = ""
  for c in modelName:
    if c.isUpperAscii and snake.len > 0: snake.add('_')
    snake.add(c.toLowerAscii)
  if tables.hasKey(snake):
    return snake
  ""

proc validatePluginPagesSchema*(pages: JsonNode,
    tables: Table[string, Table[string, string]]): seq[string] =
  ## Validates a plugin pages payload before compiling or serving it.
  if pages.kind != JObject:
    return @["plugin pages schema must be a JSON object"]
  if pages.hasKey("pages_schema_version"):
    if pages["pages_schema_version"].kind != JInt or
        pages["pages_schema_version"].getInt != pluginPagesSchemaVersion:
      return @["unsupported plugin pages schema version"]
  if not pages.hasKey("pages") or pages["pages"].kind != JArray or
      pages["pages"].len == 0:
    return @["plugin pages schema must contain at least one page"]
  var seenPaths: seq[string] = @[]
  for page in pages["pages"]:
    if page.kind != JObject:
      result.add("every plugin page must be a JSON object")
      continue
    let id = optStr(page, "id")
    if not isSafeIdent(id):
      result.add("a plugin page has an invalid identifier")
      continue
    let path = optStr(page, "path")
    if not isSafePagePath(path):
      result.add("page \"" & id & "\" has an invalid path")
      continue
    if path in seenPaths:
      result.add("duplicate page path \"" & path & "\"")
      continue
    seenPaths.add(path)
    if optStr(page, "label").len == 0:
      result.add("page \"" & id & "\" is missing its label")
    if not page.hasKey("layout") or page["layout"].getStr != "dashboard":
      result.add("page \"" & id & "\" must use the dashboard layout")
    if not page.hasKey("data") or page["data"].kind != JObject:
      result.add("page \"" & id & "\" is missing its data source")
      continue
    let data = page["data"]
    if optStr(data, "model").len == 0:
      result.add("page \"" & id & "\" data is missing its model")
      continue
    let table = resolvePageTable(data["model"].getStr, tables)
    if table.len == 0:
      result.add("page \"" & id & "\" uses unknown table for model \"" &
        data["model"].getStr & "\"")
      continue
    if not data.hasKey("columns") or data["columns"].kind != JArray or
        data["columns"].len == 0:
      result.add("page \"" & id & "\" data must declare columns")
      continue
    var cols: seq[string] = @[]
    for col in data["columns"]:
      if col.kind != JString or col.getStr notin tables[table]:
        result.add("page \"" & id & "\" uses unknown column \"" &
          (if col.kind == JString: col.getStr else: "?") & "\"")
      else:
        cols.add(col.getStr)
    if data.hasKey("order"):
      let parts = data["order"].getStr.splitWhitespace()
      if parts.len != 2 or parts[0] notin tables[table] or
          parts[1].toLowerAscii notin ["asc", "desc"]:
        result.add("page \"" & id & "\" has an invalid order expression")
    if data.hasKey("limit"):
      if data["limit"].kind != JInt or data["limit"].getInt < 1 or
          data["limit"].getInt > 500:
        result.add("page \"" & id & "\" has an invalid limit")
    if not data.hasKey("as") or not isSafeIdent(optStr(data, "as")):
      result.add("page \"" & id & "\" data is missing its key")
    if not page.hasKey("body") or page["body"].kind != JArray:
      result.add("page \"" & id & "\" is missing its body")
      continue
    for message in validatePageNodes(page["body"], optStr(data, "as"),
        cols, path):
      result.add(message)
  result

proc timlEsc*(value: string): string =
  ## Escapes a string for use as a Tim string literal.
  result = "\""
  for c in value:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    else: result.add(c)
  result.add("\"")

proc bindRef*(raw: string): string =
  ## Converts a `scope.field` bind reference to a Tim expression.
  let parts = raw.split('.')
  "$" & parts[0] & "[\"" & parts[1] & "\"]"

proc hrefExpr*(href: JsonNode): string =
  if href.kind == JObject and href.hasKey("dashboard"):
    "dashboard(" & timlEsc(href["dashboard"].getStr) & ")"
  elif href.kind == JObject and href.hasKey("literal"):
    timlEsc(href["literal"].getStr)
  else:
    timlEsc(optStr(href, "literal"))

proc pad2(indent: int): string =
  result = ""
  for _ in 0..<indent * 2:
    result.add(' ')

proc pageNodesToTiml*(nodes: JsonNode, dataKey: string,
    indent: int): string

proc pageNodeToTiml*(node: JsonNode, dataKey: string,
    indent: int): string =
  let pad = pad2(indent)
  let nodeType = node["type"].getStr
  case nodeType
  of "heading":
    result = pad & "h" & $node["level"].getInt & ": " &
      timlEsc(node["text"].getStr)
  of "text":
    let classes =
      if node.hasKey("muted") and node["muted"].getBool: ".text-muted"
      else: ""
    if node.hasKey("bind"):
      result = pad & "p" & classes & ": " & bindRef(node["bind"].getStr)
    else:
      result = pad & "p" & classes & ": " & timlEsc(optStr(node, "text"))
  of "image":
    var src, alt: string
    if node["src"].kind == JObject and node["src"].hasKey("bind"):
      src = bindRef(node["src"]["bind"].getStr)
    else:
      src = timlEsc(optStr(node["src"], "literal"))
    if node.hasKey("alt"):
      if node["alt"].kind == JObject and node["alt"].hasKey("bind"):
        alt = bindRef(node["alt"]["bind"].getStr)
      else:
        alt = timlEsc(node["alt"].getStr(""))
    else:
      alt = "\"\""
    result = pad & "img.card-img-top src=" & src & " alt=" & alt
  of "icon":
    result = pad & "icon(" & timlEsc(node["name"].getStr) & ")"
  of "badge":
    if node.hasKey("bind"):
      result = pad & "span.badge.bg-primary: " & bindRef(node["bind"].getStr)
    else:
      result = pad & "span.badge.bg-primary: " & timlEsc(optStr(node, "text"))
  of "link":
    var cls = "a"
    if optStr(node, "style").len > 0:
      cls &= "." & node["style"].getStr.replace(" ", ".")
    if node.hasKey("active") and node["active"].getBool:
      cls &= ".active"
    let href = "href=" & hrefExpr(node["href"])
    if node.hasKey("icon"):
      result = pad & cls & " " & href & ":\n"
      result &= pad2(indent + 1) & "icon(" & timlEsc(node["icon"].getStr) & ")\n"
      result &= pad2(indent + 1) & "span.ms-1: " & timlEsc(node["label"].getStr)
    else:
      result = pad & cls & " " & href & ": " & timlEsc(node["label"].getStr)
  of "tabs":
    result = pad & "ul.nav.nav-underline\n"
    for child in node["children"]:
      result &= pad2(indent + 1) & "li.nav-item\n"
      result &= pageNodeToTiml(child, dataKey, indent + 2) & "\n"
    result = result.strip(chars = {'\n'})
  of "row":
    result = pad & "div.row\n"
    result &= pageNodesToTiml(node["children"], dataKey, indent + 1)
  of "col":
    result = pad & "div.col-lg-" & $node["size"].getInt & "\n"
    result &= pageNodesToTiml(node["children"], dataKey, indent + 1)
  of "card":
    result = pad & "div.card.rounded-4.shadow-sm\n"
    var childIndent = indent + 1
    if node.hasKey("title"):
      result &= pad2(childIndent) & "div.card-header: " &
        timlEsc(node["title"].getStr) & "\n"
    result &= pad2(childIndent) & "div.card-body\n"
    result &= pageNodesToTiml(node["children"], dataKey, childIndent + 1)
  of "section":
    result = pad & "hr.my-4\n"
    result &= pad & "h5.h5.mb-0: " & timlEsc(node["title"].getStr) & "\n"
    result &= pageNodesToTiml(node["children"], dataKey, indent)
  of "divider":
    result = pad & "hr.my-4"
  of "alert":
    result = pad & "div.alert.alert-" & node["style"].getStr & ":\n"
    result &= pageNodesToTiml(node["children"], dataKey, indent + 1)
  of "grid":
    let width = 12 div max(node["cols"].getInt, 1)
    result = pad & "div.row.g-3\n"
    result &= pad2(indent + 1) & "for $" & node["item"].getStr &
      " in $this[" & timlEsc(node["in"].getStr) & "]:\n"
    result &= pad2(indent + 2) & "div.col-lg-" & $width & "\n"
    result &= pageNodesToTiml(node["children"], dataKey, indent + 3)
  of "for":
    result = pad & "for $" & node["item"].getStr &
      " in $this[" & timlEsc(node["in"].getStr) & "]:\n"
    result &= pageNodesToTiml(node["children"], dataKey, indent + 1)
  of "empty":
    result = pad & "if len($this[" & timlEsc(node["key"].getStr) & "]) == 0:\n"
    result &= pageNodesToTiml(node["children"], dataKey, indent + 1)
  else:
    result = pad & "div: \"\""

proc pageNodesToTiml*(nodes: JsonNode, dataKey: string,
    indent: int): string =
  if nodes.kind != JArray: return ""
  var lines: seq[string] = @[]
  for node in nodes:
    lines.add(pageNodeToTiml(node, dataKey, indent))
  result = lines.join("\n").strip(chars = {'\n'})

proc pageToTiml*(page: JsonNode, dataKey: string): string =
  ## Converts a page body schema to Tim Engine source.
  pageNodesToTiml(page["body"], dataKey, 0) & "\n"

proc castPageValue*(typeName, raw: string): JsonNode =
  ## Casts a database string value using the column storage type.
  case typeName
  of "int", "int2", "int4", "int8", "integer", "serial", "serial2", "serial18":
    try: %parseInt(raw)
    except ValueError: %raw
  of "float4", "float8", "double", "numeric":
    try: %parseFloat(raw)
    except ValueError: %raw
  of "boolean", "bool":
    %(raw.strip.toLowerAscii in ["t", "true", "1", "on", "yes"])
  else: %raw

proc loadPluginPageData*(page: PluginPage): JsonNode =
  ## Loads page rows from the plugin's own table using an allowlisted query.
  result = newJArray()
  var selectCols: seq[string] = @[]
  for col in page.data.columns:
    if page.data.columnTypes.hasKey(col):
      selectCols.add("\"" & col & "\"")
  if selectCols.len == 0: return
  var sql = "SELECT " & selectCols.join(", ") & " FROM \"" & page.data.table & "\""
  if page.data.orderColumn.len > 0 and
      page.data.columnTypes.hasKey(page.data.orderColumn):
    sql &= " ORDER BY \"" & page.data.orderColumn & "\" " & page.data.orderDir
  sql &= " LIMIT " & $max(page.data.limit, 1)
  withDBPool do:
    for row in dbcon.getAllRows(SqlQuery(sql)):
      var entry = newJObject()
      for i in 0..<min(row.len, page.data.columns.len):
        let col = page.data.columns[i]
        entry[col] = castPageValue(
          page.data.columnTypes.getOrDefault(col), row[i])
      result.add(entry)

proc parsePluginPage*(pluginId, pluginName: string, page: JsonNode,
    tableName: string,
    columnTypes: Table[string, string]): PluginPage =
  ## Builds a runtime page definition from a validated page schema.
  let data = page["data"]
  var orderColumn, orderDir = ""
  if data.hasKey("order"):
    let parts = data["order"].getStr.splitWhitespace()
    if parts.len == 2:
      orderColumn = parts[0]
      orderDir = parts[1].toUpperAscii
  var cols: seq[string] = @[]
  for col in data["columns"]:
    cols.add(col.getStr)
  result = PluginPage(
    pluginId: pluginId,
    pluginName: pluginName,
    id: page["id"].getStr,
    label: page["label"].getStr,
    path: page["path"].getStr,
    layout: page["layout"].getStr("dashboard"),
    data: PluginPageData(
      table: tableName,
      columns: cols,
      columnTypes: columnTypes,
      orderColumn: orderColumn,
      orderDir: orderDir,
      limit:
        if data.hasKey("limit"): max(data["limit"].getInt, 1)
        else: 100,
      dataKey: data["as"].getStr
    ),
    body: copy(page["body"])
  )
  result.viewKey = "plugin." & pluginName & "." & result.id
