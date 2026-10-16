# Tests for schema-first plugin settings (validation, coercion, migration).
import std/json
import unittest

import service/plugin_settings

let mediaTab = %*{
  "id": "media",
  "label": "Media Library",
  "model": "MediaLibrarySettings",
  "fields": {
    "jpg_quality": {"nimtype": "Int4"},
    "auto_optimize": {"nimtype": "Boolean"},
    "max_file_size": {"nimtype": "Int4"}
  },
  "layout": [
    {"type": "field", "name": "jpg_quality", "field_type": "integer",
     "label": "JPEG Quality", "required": true, "default": 85,
     "constraints": {"min": 1, "max": 100}},
    {"type": "field", "name": "auto_optimize", "field_type": "boolean",
     "label": "Auto-optimize", "required": true, "default": true},
    {"type": "field", "name": "max_file_size", "field_type": "integer",
     "label": "Max File Size (MB)", "required": true, "default": 32,
     "constraints": {"min": 1, "max": 1024}},
    {"type": "actions", "children": [
      {"type": "submit", "id": "restoreDefaults", "label": "Restore Defaults"}
    ]}
  ]
}

let mediaSettings = %*{"tabs": [mediaTab]}

test "valid settings schema passes validation":
  check validatePluginSettingsSchema(mediaSettings).len == 0

test "schema without tabs is rejected":
  check validatePluginSettingsSchema(%*{"tabs": []}).len > 0

test "layout reference to undeclared field is rejected":
  var broken = parseJson($mediaSettings)
  broken["tabs"][0]["layout"].add(%*{
    "type": "field", "name": "nope", "field_type": "string", "label": "Nope"})
  check validatePluginSettingsSchema(broken).len > 0

test "unsupported action is rejected":
  var broken = parseJson($mediaSettings)
  broken["tabs"][0]["layout"][3]["children"].add(%*{
    "type": "submit", "id": "launch", "label": "Launch"})
  check validatePluginSettingsSchema(broken).len > 0

test "valid submission coerces to canonical typed JSON":
  let outcome = coercePluginSettings(mediaTab, @[
    ("section", "media"), ("csrf", "token"),
    ("settings_action", "save"),
    ("jpg_quality", "90"), ("auto_optimize", "on"),
    ("max_file_size", "64")])
  check outcome.valid
  check outcome.value["jpg_quality"].getInt == 90
  check outcome.value["auto_optimize"].getBool == true
  check outcome.value["max_file_size"].getInt == 64

test "out-of-range value is rejected":
  let outcome = coercePluginSettings(mediaTab, @[
    ("jpg_quality", "200"), ("auto_optimize", "on"),
    ("max_file_size", "64")])
  check not outcome.valid
  check outcome.errors.len == 1
  check outcome.errors[0].field == "jpg_quality"

test "non-numeric value is rejected":
  let outcome = coercePluginSettings(mediaTab, @[
    ("jpg_quality", "lots"), ("auto_optimize", "on"),
    ("max_file_size", "64")])
  check not outcome.valid

test "unknown submitted field is rejected":
  let outcome = coercePluginSettings(mediaTab, @[
    ("jpg_quality", "90"), ("auto_optimize", "on"),
    ("max_file_size", "64"), ("admin", "true")])
  check not outcome.valid

test "duplicate submitted field is rejected":
  let outcome = coercePluginSettings(mediaTab, @[
    ("jpg_quality", "90"), ("jpg_quality", "91"),
    ("auto_optimize", "on"), ("max_file_size", "64")])
  check not outcome.valid

test "unchecked checkbox coerces to false":
  let outcome = coercePluginSettings(mediaTab, @[
    ("jpg_quality", "90"), ("max_file_size", "64")])
  check outcome.valid
  check outcome.value["auto_optimize"].getBool == false

test "missing required field is rejected":
  let outcome = coercePluginSettings(mediaTab, @[
    ("auto_optimize", "on"), ("max_file_size", "64")])
  check not outcome.valid

test "restore returns schema-declared defaults":
  let defaults = restorePluginSettings(mediaTab)
  check defaults["jpg_quality"].getInt == 85
  check defaults["auto_optimize"].getBool == true
  check defaults["max_file_size"].getInt == 32

test "migration normalizes legacy stringified values":
  let migration = normalizeStoredPluginSettings(mediaTab, %*{
    "jpg_quality": "85", "auto_optimize": "on"})
  check migration.changed
  check migration.value["jpg_quality"].getInt == 85
  check migration.value["auto_optimize"].getBool == true
  check migration.value["max_file_size"].getInt == 32

test "migration preserves invalid values instead of discarding them":
  let migration = normalizeStoredPluginSettings(mediaTab, %*{
    "jpg_quality": "lots", "auto_optimize": true, "max_file_size": 32})
  check migration.value["jpg_quality"].getStr == "lots"
  check migration.warnings.len > 0
