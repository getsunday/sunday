# Schema-first helpers for Sunday plugin settings tabs.
#
# Plugins contribute JSON settings schemas. Sunday validates those schemas,
# renders forms from them, and coerces untrusted HTTP form input into
# canonical typed JSON before persisting it.

import std/[json, strutils, tables, sets]
import pkg/valido/[str, email, uuid, port, json]

const pluginSettingsFieldTypes* = [
  "string", "text", "integer", "float", "boolean",
  "email", "uuid", "port", "json", "password"
]

const pluginSettingsReservedFields* = [
  "section", "csrf", "settings_action"
]

type
  PluginSettingsError* = object
    field*: string
    message*: string

  PluginSettingsOutcome* = object
    valid*: bool
    value*: JsonNode
    form*: JsonNode
    errors*: seq[PluginSettingsError]

  PluginSettingsMigration* = object
    value*: JsonNode
    changed*: bool
    warnings*: seq[string]

proc settingsCsrfId*(section: string): string =
  ## Returns the canonical CSRF identifier for a settings tab.
  "/dashboard/settings?tab=" & section

proc isSupportedFieldType*(fieldType: string): bool =
  fieldType in pluginSettingsFieldTypes

proc storageClassForNimType*(nimtype: string): string =
  case nimtype.toLowerAscii
  of "boolean", "bool": "boolean"
  of "serial", "serial2", "serial18", "int", "int2", "int4",
     "int8", "integer": "integer"
  of "float", "float4", "float8", "double", "numeric": "float"
  of "char", "varchar", "text", "string": "text"
  of "json", "jsonb": "json"
  else: ""

proc fieldTypeCompatible*(nimtype, fieldType: string): bool =
  case storageClassForNimType(nimtype)
  of "boolean": fieldType == "boolean"
  of "integer": fieldType in ["integer", "port"]
  of "float": fieldType == "float"
  of "text":
    fieldType in ["string", "text", "email", "uuid", "port",
                  "json", "password"]
  of "json": fieldType == "json"
  else: false

proc inferFieldType*(nimtype: string): string =
  ## Infers a runtime field type for legacy schemas that predate
  ## explicit `field_type` metadata.
  case storageClassForNimType(nimtype)
  of "boolean": "boolean"
  of "integer": "integer"
  of "float": "float"
  of "text": "string"
  of "json": "json"
  else: ""

proc effectiveFieldType*(fieldDef: JsonNode): string =
  if fieldDef.kind == JObject and fieldDef.hasKey("field_type") and
      fieldDef["field_type"].kind == JString:
    let explicit = fieldDef["field_type"].getStr
    if isSupportedFieldType(explicit):
      return explicit
  if fieldDef.kind == JObject and fieldDef.hasKey("nimtype") and
      fieldDef["nimtype"].kind == JString:
    return inferFieldType(fieldDef["nimtype"].getStr)
  ""

proc fieldRequired*(fieldDef: JsonNode): bool =
  fieldDef.kind == JObject and fieldDef.hasKey("required") and
    fieldDef["required"].kind == JBool and fieldDef["required"].getBool

proc fieldConstraints*(fieldDef: JsonNode): JsonNode =
  if fieldDef.kind == JObject and fieldDef.hasKey("constraints") and
      fieldDef["constraints"].kind == JObject:
    fieldDef["constraints"]
  else:
    newJObject()

proc constraintNumber*(constraints: JsonNode, key: string,
    value: var float): bool =
  if constraints.hasKey(key):
    case constraints[key].kind
    of JInt:
      value = float(constraints[key].getInt)
      return true
    of JFloat:
      value = constraints[key].getFloat
      return true
    else: return false
  false

proc defaultMatchesFieldType*(fieldType: string, default: JsonNode): bool =
  case fieldType
  of "integer": result = default.kind == JInt
  of "float": result = default.kind in {JInt, JFloat}
  of "boolean": result = default.kind == JBool
  of "json":
    if default.kind == JString:
      try:
        discard parseJson(default.getStr)
        result = true
      except JsonParsingError, ValueError:
        result = false
    else:
      result = true
  else: result = default.kind == JString

proc emptyFieldValue*(fieldType: string): JsonNode =
  case fieldType
  of "integer", "port": result = %0
  of "float": result = %0.0
  of "boolean": result = %false
  of "json": result = newJObject()
  else: result = %""

proc isSettingsInteger*(raw: string): bool =
  ## Integer syntax check built on Valido's digit validation.
  ## Unlike `isInt`, this also accepts an explicit leading sign.
  var digits = raw.strip
  if digits.len == 0: return false
  if digits[0] == '+' or digits[0] == '-':
    if digits.len == 1: return false
    digits = digits[1..^1]
  isInt(digits)

proc parseSettingsInteger*(raw: string, value: var int): bool =
  var digits = raw.strip
  var sign = 1
  if digits.len > 0 and (digits[0] == '+' or digits[0] == '-'):
    if digits[0] == '-': sign = -1
    digits = digits[1..^1]
  if not isSettingsInteger(raw): return false
  try:
    value = sign * parseInt(digits)
    result = true
  except ValueError:
    result = false

proc checkNumericConstraints*(value: float, constraints: JsonNode,
    label: string): string =
  var bound: float
  if constraintNumber(constraints, "min", bound) and value < bound:
    return label & " must be at least " & $constraints["min"]
  if constraintNumber(constraints, "max", bound) and value > bound:
    return label & " must be at most " & $constraints["max"]
  ""

proc checkLengthConstraints*(value: string, constraints: JsonNode,
    label: string): string =
  if constraints.hasKey("minlength") and
      constraints["minlength"].kind == JInt and
      value.len < constraints["minlength"].getInt:
    return label & " must contain at least " &
      $constraints["minlength"].getInt & " characters"
  if constraints.hasKey("maxlength") and
      constraints["maxlength"].kind == JInt and
      value.len > constraints["maxlength"].getInt:
    return label & " must contain at most " &
      $constraints["maxlength"].getInt & " characters"
  ""

proc collectLayoutFieldNodes*(nodes: JsonNode): seq[JsonNode] =
  if nodes.kind != JArray: return @[]
  for node in nodes:
    if node.kind != JObject: continue
    if node.hasKey("type") and node["type"].kind == JString and
        node["type"].getStr == "field":
      result.add(node)
    if node.hasKey("children"):
      for child in collectLayoutFieldNodes(node["children"]):
        result.add(child)

proc findFieldLabel*(nodes: JsonNode, fieldName: string): string =
  for node in collectLayoutFieldNodes(nodes):
    var name = ""
    if node.hasKey("name") and node["name"].kind == JString:
      name = node["name"].getStr
    elif node.hasKey("model") and node["model"].kind == JString:
      name = node["model"].getStr
    if name == fieldName:
      if node.hasKey("label") and node["label"].kind == JString and
          node["label"].getStr.len > 0:
        return node["label"].getStr
      return fieldName
  fieldName

proc canonicalPluginFields*(tab: JsonNode): OrderedTable[string, JsonNode] =
  ## Merges storage metadata with layout metadata into one canonical map.
  result = initOrderedTable[string, JsonNode]()
  if tab.kind != JObject: return
  if tab.hasKey("fields") and tab["fields"].kind == JObject:
    for name, fieldDef in tab["fields"].pairs:
      if fieldDef.kind == JObject:
        var merged = copy(fieldDef)
        merged["name"] = %name
        result[name] = merged
  if tab.hasKey("layout"):
    for node in collectLayoutFieldNodes(tab["layout"]):
      var name = ""
      if node.hasKey("name") and node["name"].kind == JString:
        name = node["name"].getStr
      elif node.hasKey("model") and node["model"].kind == JString:
        name = node["model"].getStr
      if name.len == 0: continue
      if not result.hasKey(name):
        result[name] = %*{"name": name}
      for key in ["field_type", "label", "description", "required",
                  "default", "constraints", "nimtype"]:
        if node.hasKey(key):
          result[name][key] = copy(node[key])

proc fieldLabel*(tab: JsonNode, fieldName: string,
    fieldDef: JsonNode): string =
  if tab.hasKey("layout"):
    let layoutLabel = findFieldLabel(tab["layout"], fieldName)
    if layoutLabel.len > 0: return layoutLabel
  if fieldDef.kind == JObject and fieldDef.hasKey("label") and
      fieldDef["label"].kind == JString and fieldDef["label"].getStr.len > 0:
    return fieldDef["label"].getStr
  fieldName

proc validateFieldMetadata*(fieldName, fieldType, nimtype: string,
    fieldDef: JsonNode): seq[string] =
  if fieldType.len == 0:
    return @["field \"" & fieldName & "\" does not declare a usable field type"]
  if not isSupportedFieldType(fieldType):
    return @["field \"" & fieldName & "\" has invalid field type \"" & fieldType & "\""]
  if nimtype.len > 0 and not fieldTypeCompatible(nimtype, fieldType):
    return @["field \"" & fieldName & "\" with field type \"" & fieldType &
      "\" cannot be stored in model type \"" & nimtype & "\""]
  if fieldDef.hasKey("required") and fieldDef["required"].kind != JBool:
    return @["field \"" & fieldName & "\" requires `required true` or `required false`"]
  if fieldDef.hasKey("default") and
      not defaultMatchesFieldType(fieldType, fieldDef["default"]):
    return @["field \"" & fieldName & "\" has a default that does not match field type \"" &
      fieldType & "\""]
  let constraints = fieldConstraints(fieldDef)
  if constraints.hasKey("min") and constraints["min"].kind notin {JInt, JFloat}:
    return @["field \"" & fieldName & "\" requires `min` to be a number"]
  if constraints.hasKey("max") and constraints["max"].kind notin {JInt, JFloat}:
    return @["field \"" & fieldName & "\" requires `max` to be a number"]
  if constraints.hasKey("minlength") and
      (constraints["minlength"].kind != JInt or constraints["minlength"].getInt < 0):
    return @["field \"" & fieldName & "\" requires `minlength` to be zero or greater"]
  if constraints.hasKey("maxlength") and
      (constraints["maxlength"].kind != JInt or constraints["maxlength"].getInt < 0):
    return @["field \"" & fieldName & "\" requires `maxlength` to be zero or greater"]
  var minimum, maximum: float
  if constraintNumber(constraints, "min", minimum) and
      constraintNumber(constraints, "max", maximum) and minimum > maximum:
    return @["field \"" & fieldName & "\" has a minimum greater than its maximum"]
  if constraints.hasKey("minlength") and constraints.hasKey("maxlength") and
      constraints["minlength"].getInt > constraints["maxlength"].getInt:
    return @["field \"" & fieldName & "\" has a minimum length greater than its maximum length"]
  @[]

proc validateLayoutNode*(node: JsonNode, declared: HashSet[string],
    tabId: string, seen: var HashSet[string],
    messages: var seq[string]) =
  if node.kind != JObject: return
  if node.hasKey("type") and node["type"].kind == JString:
    case node["type"].getStr
    of "field":
      var name = ""
      if node.hasKey("name") and node["name"].kind == JString:
        name = node["name"].getStr
      elif node.hasKey("model") and node["model"].kind == JString:
        name = node["model"].getStr
      if name.len == 0:
        messages.add("tab \"" & tabId & "\" contains a layout field without a name")
      elif name notin declared:
        messages.add("tab \"" & tabId & "\" references undeclared field \"" & name & "\"")
      elif name in seen:
        messages.add("tab \"" & tabId & "\" references field \"" & name & "\" more than once")
      else:
        seen.incl(name)
    of "submit", "button":
      let actionId =
        if node.hasKey("id") and node["id"].kind == JString: node["id"].getStr
        else: ""
      if actionId.len == 0:
        messages.add("tab \"" & tabId & "\" contains an action without an identifier")
      elif actionId != "restoreDefaults":
        messages.add("tab \"" & tabId & "\" uses unsupported action \"" & actionId & "\"")
    of "columns":
      if not node.hasKey("size") or node["size"].kind != JInt or
          node["size"].getInt <= 0:
        messages.add("tab \"" & tabId & "\" contains columns without a positive size")
    else: discard
  if node.hasKey("children") and node["children"].kind == JArray:
    for child in node["children"]:
      validateLayoutNode(child, declared, tabId, seen, messages)

proc validateLayoutNodes*(nodes: JsonNode, declared: HashSet[string],
    tabId: string): seq[string] =
  if nodes.kind != JArray:
    return @["tab \"" & tabId & "\" requires a layout array"]
  var seen = initHashSet[string]()
  for node in nodes:
    validateLayoutNode(node, declared, tabId, seen, result)
  result

proc validatePluginSettingsSchema*(settings: JsonNode): seq[string] =
  ## Validates a plugin settings payload before installation or activation.
  if settings.kind != JObject:
    return @["plugin settings schema must be a JSON object"]
  if settings.hasKey("settings_schema_version"):
    if settings["settings_schema_version"].kind != JInt or
        settings["settings_schema_version"].getInt != 1:
      return @["unsupported plugin settings schema version"]
  if not settings.hasKey("tabs") or settings["tabs"].kind != JArray or
      settings["tabs"].len == 0:
    return @["plugin settings schema must contain at least one tab"]
  for tab in settings["tabs"]:
    if tab.kind != JObject:
      result.add("every plugin settings tab must be a JSON object")
      continue
    let tabId =
      if tab.hasKey("id") and tab["id"].kind == JString: tab["id"].getStr
      else: ""
    if tabId.len == 0:
      result.add("a plugin settings tab is missing its identifier")
      continue
    if not tab.hasKey("label") or tab["label"].kind != JString or
        tab["label"].getStr.len == 0:
      result.add("tab \"" & tabId & "\" is missing its label")
    if not tab.hasKey("model") or tab["model"].kind != JString or
        tab["model"].getStr.len == 0:
      result.add("tab \"" & tabId & "\" is missing its model")
    if not tab.hasKey("fields") or tab["fields"].kind != JObject or
        tab["fields"].len == 0:
      result.add("tab \"" & tabId & "\" must declare at least one field")
      continue
    var declared = initHashSet[string]()
    for name, fieldDef in tab["fields"].pairs:
      declared.incl(name)
      if fieldDef.kind != JObject:
        result.add("tab \"" & tabId & "\" field \"" & name & "\" must be a JSON object")
        continue
      let nimtype =
        if fieldDef.hasKey("nimtype") and fieldDef["nimtype"].kind == JString:
          fieldDef["nimtype"].getStr
        else: ""
      for message in validateFieldMetadata(name, effectiveFieldType(fieldDef),
          nimtype, fieldDef):
        result.add("tab \"" & tabId & "\": " & message)
    if not tab.hasKey("layout"):
      result.add("tab \"" & tabId & "\" is missing its layout")
      continue
    let canonical = canonicalPluginFields(tab)
    for node in collectLayoutFieldNodes(tab["layout"]):
      var name = ""
      if node.hasKey("name") and node["name"].kind == JString:
        name = node["name"].getStr
      elif node.hasKey("model") and node["model"].kind == JString:
        name = node["model"].getStr
      if name.len > 0 and canonical.hasKey(name):
        let layoutType =
          if node.hasKey("field_type") and node["field_type"].kind == JString:
            node["field_type"].getStr
          else: ""
        let canonicalType = effectiveFieldType(canonical[name])
        if layoutType.len > 0 and canonicalType.len > 0 and
            layoutType != canonicalType:
          result.add("tab \"" & tabId & "\" field \"" & name &
            "\" has conflicting field types")
    for message in validateLayoutNodes(tab["layout"], declared, tabId):
      result.add(message)
  result

proc parseSubmittedField*(fieldType, raw: string, required: bool,
    constraints: JsonNode, label: string,
    value: var JsonNode): string =
  ## Validates one submitted string and converts it to canonical JSON.
  ## Returns an empty string on success or a human-readable error.
  case fieldType
  of "boolean":
    let normalized = raw.strip.toLowerAscii
    case normalized
    of "true", "1", "on", "yes":
      value = %true
      result = ""
    of "false", "0", "off", "no":
      value = %false
      result = ""
    of "":
      if required: result = label & " is required"
      else:
        value = %false
        result = ""
    else: result = label & " must be a boolean value"
  of "integer", "port":
    let normalized = raw.strip
    if normalized.len == 0:
      return (if required: label & " is required" else: "")
    var number: int
    if fieldType == "port":
      if not isPort(normalized):
        return label & " must be a valid port between 0 and 65535"
      try:
        number = parseInt(normalized)
      except ValueError:
        return label & " must be a valid port between 0 and 65535"
    else:
      if not parseSettingsInteger(normalized, number):
        return label & " must be a valid integer"
    value = %number
    result = checkNumericConstraints(float(number), constraints, label)
  of "float":
    let normalized = raw.strip
    if normalized.len == 0:
      return (if required: label & " is required" else: "")
    if not isFloat(normalized):
      return label & " must be a valid number"
    try:
      let number = parseFloat(normalized)
      value = %number
      result = checkNumericConstraints(number, constraints, label)
    except ValueError:
      result = label & " must be a valid number"
  of "email":
    let normalized = raw.strip
    if normalized.len == 0:
      return (if required: label & " is required" else: "")
    if not isEmail(normalized):
      return label & " must be a valid email address"
    value = %normalized
    result = checkLengthConstraints(normalized, constraints, label)
  of "uuid":
    let normalized = raw.strip
    if normalized.len == 0:
      return (if required: label & " is required" else: "")
    if not isUUID(normalized):
      return label & " must be a valid UUID"
    value = %normalized
    result = checkLengthConstraints(normalized, constraints, label)
  of "json":
    let normalized = raw.strip
    if normalized.len == 0:
      return (if required: label & " is required" else: "")
    if not isJSON(normalized):
      return label & " must contain valid JSON"
    try:
      value = parseJson(normalized)
      result = ""
    except JsonParsingError, ValueError:
      result = label & " must contain valid JSON"
  of "password":
    if raw.len == 0:
      return (if required: label & " is required" else: "")
    value = %raw
    result = checkLengthConstraints(raw, constraints, label)
  else:
    let normalized = raw.strip
    if required and not isNotEmpty(normalized):
      return label & " is required"
    value = %normalized
    result = checkLengthConstraints(normalized, constraints, label)

proc coercePluginSettings*(tab: JsonNode,
    submitted: openArray[(string, string)],
    existing: JsonNode = newJObject()): PluginSettingsOutcome =
  ## Converts untrusted form input into canonical typed settings JSON.
  result = PluginSettingsOutcome(valid: true, value: newJObject(),
    form: newJObject(), errors: @[])
  let fields = canonicalPluginFields(tab)
  if fields.len == 0:
    result.valid = false
    result.errors.add(PluginSettingsError(field: "",
      message: "Plugin settings schema is unavailable"))
    return
  var raw = initTable[string, string]()
  var seen = initHashSet[string]()
  for pair in submitted:
    if pair[0] in seen:
      result.valid = false
      result.errors.add(PluginSettingsError(field: pair[0],
        message: "Duplicate submitted value"))
      continue
    seen.incl(pair[0])
    if pair[0] notin pluginSettingsReservedFields:
      raw[pair[0]] = pair[1]
  for name in raw.keys:
    if not fields.hasKey(name):
      result.valid = false
      result.errors.add(PluginSettingsError(field: name,
        message: "Unknown setting"))
  for name, fieldDef in fields.pairs:
    let fieldType = effectiveFieldType(fieldDef)
    let label = fieldLabel(tab, name, fieldDef)
    let required = fieldRequired(fieldDef)
    let constraints = fieldConstraints(fieldDef)
    if raw.hasKey(name):
      result.form[name] = %raw[name]
      if fieldType == "password" and raw[name].len == 0 and not required:
        if existing.kind == JObject and existing.hasKey(name):
          result.value[name] = copy(existing[name])
        elif fieldDef.hasKey("default"):
          result.value[name] = copy(fieldDef["default"])
        else:
          result.value[name] = emptyFieldValue(fieldType)
        continue
      if raw[name].strip.len == 0 and fieldType notin ["string", "text", "password"]:
        if required:
          result.valid = false
          result.errors.add(PluginSettingsError(field: name,
            message: label & " is required"))
        elif existing.kind == JObject and existing.hasKey(name):
          result.value[name] = copy(existing[name])
        elif fieldDef.hasKey("default"):
          result.value[name] = copy(fieldDef["default"])
        else:
          result.value[name] = emptyFieldValue(fieldType)
        continue
      var parsed: JsonNode
      let message = parseSubmittedField(fieldType, raw[name], required,
        constraints, label, parsed)
      if message.len > 0:
        result.valid = false
        result.errors.add(PluginSettingsError(field: name, message: message))
      elif not parsed.isNil:
        result.value[name] = parsed
      elif fieldDef.hasKey("default"):
        result.value[name] = copy(fieldDef["default"])
      else:
        result.value[name] = emptyFieldValue(fieldType)
    else:
      if fieldType == "boolean":
        result.value[name] = %false
        result.form[name] = %false
      elif required:
        result.valid = false
        result.errors.add(PluginSettingsError(field: name,
          message: label & " is required"))
        if fieldDef.hasKey("default"):
          result.form[name] = copy(fieldDef["default"])
        else:
          result.form[name] = emptyFieldValue(fieldType)
      elif existing.kind == JObject and existing.hasKey(name):
        result.value[name] = copy(existing[name])
        result.form[name] = copy(existing[name])
      elif fieldDef.hasKey("default"):
        result.value[name] = copy(fieldDef["default"])
        result.form[name] = copy(fieldDef["default"])
      else:
        result.value[name] = emptyFieldValue(fieldType)
        result.form[name] = emptyFieldValue(fieldType)

proc restorePluginSettings*(tab: JsonNode): JsonNode =
  ## Returns canonical schema-declared defaults for every known field.
  result = newJObject()
  for name, fieldDef in canonicalPluginFields(tab).pairs:
    if fieldDef.hasKey("default"):
      result[name] = copy(fieldDef["default"])
    else:
      result[name] = emptyFieldValue(effectiveFieldType(fieldDef))

proc normalizeStoredValue*(fieldType: string, stored, default: JsonNode,
    label: string): tuple[ok: bool, value: JsonNode, warning: string] =
  ## An empty stored string is treated as missing and backfilled with the
  ## default, except for free-text fields where emptiness is a real value.
  if stored.kind == JString and stored.getStr.strip.len == 0 and
      fieldType notin ["string", "text", "password"]:
    return (true, copy(default), "")
  case fieldType
  of "boolean":
    case stored.kind
    of JBool: (true, copy(stored), "")
    of JString:
      case stored.getStr.strip.toLowerAscii
      of "true", "1", "on", "yes": (true, %true, "")
      of "false", "0", "off", "no": (true, %false, "")
      else: (false, copy(stored), label & " has an invalid stored boolean value")
    of JInt:
      if stored.getInt == 1: (true, %true, "")
      elif stored.getInt == 0: (true, %false, "")
      else: (false, copy(stored), label & " has an invalid stored boolean value")
    else: (false, copy(stored), label & " has an invalid stored boolean value")
  of "integer", "port":
    case stored.kind
    of JInt: (true, copy(stored), "")
    of JFloat:
      let asInt = int(stored.getFloat)
      if float(asInt) == stored.getFloat:
        (true, %asInt, "")
      else: (false, copy(stored), label & " has an invalid stored integer value")
    of JString:
      var number: int
      if fieldType == "port":
        if isPort(stored.getStr.strip):
          try:
            (true, %parseInt(stored.getStr.strip), "")
          except ValueError:
            (false, copy(stored), label & " has an invalid stored port")
        else: (false, copy(stored), label & " has an invalid stored port")
      elif parseSettingsInteger(stored.getStr, number):
        (true, %number, "")
      else: (false, copy(stored), label & " has an invalid stored integer value")
    else: (false, copy(stored), label & " has an invalid stored integer value")
  of "float":
    case stored.kind
    of JFloat: (true, copy(stored), "")
    of JInt: (true, %(float(stored.getInt)), "")
    of JString:
      if isFloat(stored.getStr.strip):
        try: (true, %parseFloat(stored.getStr.strip), "")
        except ValueError:
          (false, copy(stored), label & " has an invalid stored number")
      else: (false, copy(stored), label & " has an invalid stored number")
    else: (false, copy(stored), label & " has an invalid stored number")
  of "json":
    if stored.kind == JString and isJSON(stored.getStr):
      try: (true, parseJson(stored.getStr), "")
      except JsonParsingError, ValueError:
        (false, copy(stored), label & " has invalid stored JSON")
    elif stored.kind == JString:
      (false, copy(stored), label & " has invalid stored JSON")
    else: (true, copy(stored), "")
  of "password":
    if stored.kind == JString: (true, copy(stored), "")
    else: (false, copy(stored), label & " has an invalid stored value")
  else:
    if stored.kind == JString:
      let normalized = stored.getStr.strip
      var valid =
        case fieldType
        of "email": isEmail(normalized)
        of "uuid": isUUID(normalized)
        else: true
      if valid: (true, %normalized, "")
      else: (false, copy(stored), label & " has an invalid stored value")
    else: (false, copy(stored), label & " has an invalid stored value")

proc normalizeStoredPluginSettings*(tab: JsonNode,
    stored: JsonNode): PluginSettingsMigration =
  ## Migrates legacy stringified settings to canonical typed JSON.
  ## Invalid values are preserved and reported instead of discarded.
  result = PluginSettingsMigration(value: newJObject(), changed: false,
    warnings: @[])
  if stored.kind == JObject:
    for name, current in stored.pairs:
      result.value[name] = copy(current)
  for name, fieldDef in canonicalPluginFields(tab).pairs:
    let fieldType = effectiveFieldType(fieldDef)
    let label = fieldLabel(tab, name, fieldDef)
    let default =
      if fieldDef.hasKey("default"): fieldDef["default"]
      else: emptyFieldValue(fieldType)
    if not result.value.hasKey(name):
      result.value[name] = copy(default)
      result.changed = true
      result.warnings.add(label & " was backfilled with its default value")
    else:
      let normalized = normalizeStoredValue(fieldType, result.value[name],
        default, label)
      if normalized.ok:
        if normalized.value != result.value[name]:
          result.value[name] = normalized.value
          result.changed = true
      else:
        result.warnings.add(normalized.warning)

proc normalizeRenderField*(node, fields: JsonNode) =
  if node.kind != JObject: return
  if node.hasKey("type") and node["type"].kind == JString and
      node["type"].getStr == "field":
    var name = ""
    if node.hasKey("name") and node["name"].kind == JString:
      name = node["name"].getStr
    elif node.hasKey("model") and node["model"].kind == JString:
      name = node["model"].getStr
      node["name"] = %name
    if name.len > 0:
      var nimtype = ""
      if fields.kind == JObject and fields.hasKey(name) and
          fields[name].kind == JObject and
          fields[name].hasKey("nimtype") and
          fields[name]["nimtype"].kind == JString:
        nimtype = fields[name]["nimtype"].getStr
      elif node.hasKey("nimtype") and node["nimtype"].kind == JString:
        nimtype = node["nimtype"].getStr
      if (not node.hasKey("field_type") or
          node["field_type"].kind != JString or
          node["field_type"].getStr.len == 0) and nimtype.len > 0:
        let inferred = inferFieldType(nimtype)
        node["field_type"] =
          if inferred.len > 0: %inferred
          else: %"string"
  if node.hasKey("children") and node["children"].kind == JArray:
    for child in node["children"]:
      normalizeRenderField(child, fields)

proc normalizePluginTabForRender*(tab: JsonNode): JsonNode =
  ## Returns a render-safe copy with canonical field names and types.
  if tab.kind != JObject: return newJObject()
  result = parseJson($tab)
  if not result.hasKey("fields") or result["fields"].kind != JObject:
    result["fields"] = newJObject()
  if not result.hasKey("layout") or result["layout"].kind != JArray:
    result["layout"] = newJArray()
  for node in result["layout"]:
    normalizeRenderField(node, result["fields"])

proc mergeFormValues*(stored, form: JsonNode): JsonNode =
  ## Merges submitted form values over stored settings for redisplay.
  if stored.kind == JObject:
    result = parseJson($stored)
  else:
    result = newJObject()
  if form.kind == JObject:
    for name, value in form.pairs:
      result[name] = copy(value)

proc normalizePluginTabsForInstall*(settings: JsonNode): JsonNode =
  ## Returns a copy of a settings payload with render-safe canonical tabs.
  if settings.kind != JObject: return newJObject()
  result = parseJson($settings)
  if result.hasKey("tabs") and result["tabs"].kind == JArray:
    var tabsArr = newJArray()
    for tabNode in result["tabs"]:
      tabsArr.add(normalizePluginTabForRender(tabNode))
    result["tabs"] = tabsArr
