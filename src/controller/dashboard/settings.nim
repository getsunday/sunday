# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[os, envvars, osproc, strutils, times]
import pkg/bag
import pkg/ozark/driver/psql

import pkg/supranim/[controller, application]
import pkg/supranim/core/[paths, utils, fileserver]

import ../../service/provider/[db, session, tim]

let timezones = [
  "GMT-1", "GMT-10", "GMT-11", "GMT-12", "GMT-13", "GMT-14", "GMT-2", "GMT-3", "GMT-4", "GMT-5", "GMT-6", "GMT-7", "GMT-8", "GMT-9",
  "GMT", "GMT+1", "GMT+10", "GMT+11", "GMT+12", "GMT+2", "GMT+3", "GMT+4", "GMT+5", "GMT+6", "GMT+7", "GMT+8", "GMT+9",
  "Greenwich", "Universal", "UCT", "Zulu", "GMT0", "UTC"
]

ctrl getDashboardSettings:
  ## Renders the users settings dashboard screen.
  withDBPool do:
    let tabs = %*[
      {
        "name": "general",
        "label": "General"
      },
      {
        "name": "users",
        "label": "Users"
      },
      {
        "name": "plugins",
        "label": "Plugins"
      },
      {
        "name": "smtp",
        "label": "SMTP"
      },
      {
        "name": "system",
        "label": "System"
      }
    ]
    if req.getQuery != nil:
      if req.getQuery.hasKey("tab") and req.getQuery["tab"] != "general":
        if req.getQuery["tab"] == "system":
          render("dashboard.settings.system", layout="dashboard", local = &*{
            "tabs": tabs
          })
        elif req.getQuery["tab"] == "users":
          render("dashboard.settings.users", layout="dashboard", local = &*{
            "tabs": tabs
          })
        elif req.getQuery["tab"] == "plugins":
          render("dashboard.settings.plugins", layout="dashboard", local = &*{
            "tabs": tabs
          })
        elif req.getQuery["tab"] == "smtp":
          render("dashboard.settings.smtp", layout="dashboard", local = &*{
            "tabs": tabs
          })
        else:
          render("errors.4xx", layout="dashboard")

    # the `general` settings tab is the default view
    # for the settings dashboard and includes general application settings
    let settings = Models.table(Settings).selectAll()
                         .where("tab", "general")
                         .getAll()
    if likely(settings.isEmpty == false):
      let data = settings.first()
      render("dashboard.settings.general",
          layout="dashboard", local = &*{
            "tabs": tabs,
            "settings": {
              "tab": data.getTab(),
              "description": data.getDescription(),
              "data": fromJson(data.getData()),
              "timezones": timezones
            }
          })
    else:
      render("errors.5xx")

ctrl postDashboardSettingsFreeMemory:
  ## POST handler for triggering the release of unused memory back to the OS
  ## This can help reduce the memory footprint of the application, especially after
  ## performing memory-intensive operations. It uses the `releaseUnusedMemory` proc
  ## defined in `core/utils.nim`, which is a cross-platform shim for `malloc_trim` on Linux and `malloc_zone_pressure_relief` on macOS.
  if releaseUnusedMemory():
    json(%*{"msg": "Unused memory released back to the OS successfully."})
  else:
    json(%*{"msg": "Failed to release unused memory. This may not be supported on the current platform."})

ctrl getDashboardSettingsStats:
  ## GET handler for rendering the system stats screen in the dashboard settings

  # Get CPU cores
  let cpuCores = countProcessors()

  # Get total RAM (macOS: use sysctl)
  let ramOutput = execProcess("sysctl -n hw.memsize")
  let totalRamBytes = parseInt(ramOutput.strip())

  # Get current process memory usage (resident set size)
  let pid = getCurrentProcessId()
  let output = execProcess("ps -p " & $pid & " -o %cpu,rss,comm")
  let lines = output.splitLines()
  var cpuUsage = 0.0
  var memoryUsageBytes = 0
  if lines.len > 1:
    let cols = lines[1].strip().splitWhitespace()
    if cols.len >= 2:
      cpuUsage = parseFloat(cols[0])
      memoryUsageBytes = parseInt(cols[1]) * 1024 # rss is in KB

  json(%*{
    "total_cores": cpuCores,
    "total_ram_bytes": totalRamBytes, # in bytes
    "cpu_usage_percent": cpuUsage, # as a percentage
    "memory_usage_bytes": memoryUsageBytes # in bytes
  })

ctrl postDashboardSettingsBackup:
  ## Endpoint to download a zipped SQL backup of the entire database.
  let
    timeNow = getTime()
    dateStr = timeNow.format("dd-MM-yyyy-HHmmss").replace("-", "_")
    backupName = "sunday_backup_" & dateStr
    tempSql = getTempDir() / backupName & ".sql" 
    tempZip = getTempDir() / backupName & ".zip"

  # Adjust these as needed for your environment
  # Dump the database to a temp SQL file
  let dumpCmd = "pg_dump -U " & getEnv("database.user") & " " & getEnv("database.name") & " > " & tempSql
  let dumpResult = execShellCmd(dumpCmd)
  if dumpResult != 0:
    json(%*{"msg": "Failed to create database backup."})

  # Zip the SQL file
  let zipCmd = "zip -j " & tempZip & " " & tempSql
  let zipResult = execShellCmd(zipCmd)
  if zipResult != 0:
    json(%*{"msg": "Failed to create backup zip file."})
  
  req.sendDownloadable(tempZip, res.headers)

ctrl postDashboardSettingsUpdate:
  ## POST handler for 

ctrl getDashboardSettingsUsers:
  ## Renders the users settings dashboard screen.
  render("dashboard.settings.users",
        layout="dashboard", local = &*{})

type
  SchemaFieldType* = enum
    sfString, sfInt, sfBool, sfSelect

  SchemaField* = object
    field_name*: string
      ## The name of the field, which is used as the key in the
      ## settings data and for labeling in the UI.
    field_type*: SchemaFieldType
      ## The type of the field, which can be a string, integer,
      ## boolean, or select (dropdown) option.
    field_info*: Option[string] = none(string)
      ## Optional additional information about the field, such
      ## as a description or help text to display in the UI.
    required*: bool
      ## Represents a single field in a settings schema,
      ## including its name, type, and whether it is required.
  
  RuntimeSchemaTable* = OrderedTable[string, SchemaField]
    ## A runtime representation of a settings schema, which is an ordered
    ## table mapping field names to their corresponding schema field definitions.

  SettingsUsersSchema* = object
    allowNewUserRegistration*: bool
      ## Whether to allow new users to register for an account on the platform.
    enableConfirmationEmail*: bool
      ## Whether to send a confirmation email to users when they register for an account.
    minPasswordLength*: uint = 16'u
      ## Minimum number of characters required for user passwords.
    passwordExpirationDays*: uint = 0'u
      ## Number of days after which a user's password expires and they are required to set a new one.
    passwordCommonDictionaryPath*: Option[string] = none(string)
      ## An optional path to a file containing common passwords to check
      ## against during registration and password changes.

# var usersSettingsSchema: RuntimeSchemaTable = {
#   "allowNewUserRegistration": {
#     field_name: "allowNewUserRegistration",
#     field_type: sfBool,
#     field_info: some("Whether to allow new users to register for an account on the platform."),
#     required: true
#   },
#   "enableConfirmationEmail": {
#     field_name: "enableConfirmationEmail",
#     field_type: sfBool,
#     field_info: some("Whether to send a confirmation email to users when they register for an account."),
#     required: true
#   },
#   "minPasswordLength": {
#     field_name: "minPasswordLength",
#     field_type: sfInt,
#     field_info: some("Minimum number of characters required for user passwords."),
#     required: true
#   },
#   "passwordExpirationDays": {
#     field_name: "passwordExpirationDays",
#     field_type: sfInt,
#     field_info: some("Number of days after which a user's password expires and they are required to set a new one."),
#     required: true
#   },
#   "passwordCommonDictionaryPath": {
#     field_name: "passwordCommonDictionaryPath",
#     field_type: sfString,
#     field_info: some("An optional path to a file containing common passwords to check against during registration and password changes."),
#     required: false
#   }
# }

ctrl postDashboardSettingsUsers:
  ## POST handler for updating user settings.
  json(%*{"msg": "User settings updated successfully."})