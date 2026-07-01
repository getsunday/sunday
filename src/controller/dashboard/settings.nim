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
    withSession do:
      if req.getQuery != nil:
        if req.getQuery.hasKey("tab") and req.getQuery["tab"] != "general":
          if req.getQuery["tab"] == "system":
            render("dashboard.settings.system", layout="dashboard", local = &*{
              "tabs": tabs,
              "page_title": "Settings",
              "page_slug": "settings",
              "notifications": userSession.getNotifications("/dashboard/settings"),
              "csrfToken": userSession.genCSRF("/dashboard/settings?tab=system")
            })
          elif req.getQuery["tab"] == "users":
            let usersSettings = Models.table(Settings).selectAll()
                                        .where("tab", "users")
                                        .getAll()
            if likely(usersSettings.isEmpty == false):
              let data = usersSettings.first()
              render("dashboard.settings.users", layout="dashboard", local = &*{
                "tabs": tabs,
                "page_title": "Settings",
                "page_slug": "settings",
                "notifications": userSession.getNotifications("/dashboard/settings?tab=users"),
                "csrfToken": userSession.genCSRF("/dashboard/settings?tab=users"),
                "settings": {
                  "tab": data.getTab(),
                  "description": data.getDescription(),
                  "data": fromJson(data.getData())
                }
              })
            else:
              render("errors.5xx")
          elif req.getQuery["tab"] == "plugins":
            let pluginsSettings = Models.table(Settings).selectAll()
                                          .where("tab", "plugins")
                                          .getAll()
            if likely(pluginsSettings.isEmpty == false):
              let data = pluginsSettings.first()
              render("dashboard.settings.plugins", layout="dashboard", local = &*{
                "tabs": tabs,
                "page_title": "Settings",
                "page_slug": "settings",
                "notifications": userSession.getNotifications("/dashboard/settings?tab=plugins"),
                "csrfToken": userSession.genCSRF("/dashboard/settings?tab=plugins"),
                "settings": {
                  "tab": data.getTab(),
                  "description": data.getDescription(),
                  "data": fromJson(data.getData())
                }
              })
            else:
              render("errors.5xx")
          elif req.getQuery["tab"] == "smtp":
            let smtpSettings = Models.table(Settings).selectAll()
                                       .where("tab", "smtp")
                                       .getAll()
            if likely(smtpSettings.isEmpty == false):
              let data = smtpSettings.first()
              render("dashboard.settings.smtp", layout="dashboard", local = &*{
                "tabs": tabs,
                "page_title": "Settings",
                "page_slug": "settings",
                "notifications": userSession.getNotifications("/dashboard/settings?tab=smtp"),
                "csrfToken": userSession.genCSRF("/dashboard/settings?tab=smtp"),
                "settings": {
                  "tab": data.getTab(),
                  "description": data.getDescription(),
                  "data": fromJson(data.getData())
                }
              })
            else:
              render("errors.5xx")
          else:
            render("errors.4xx", layout="dashboard")

      # the `general` settings tab is the default view
      # for the settings dashboard and includes general application settings
      let settings = Models.table(Settings).selectAll()
                          .where("tab", "general")
                          .getAll()
      if likely(settings.isEmpty == false):
        let data = settings.first()
        render("dashboard.settings.general", layout="dashboard", local = &*{
          "page_title": "Settings",
          "page_slug": "settings",
          "csrfToken": userSession.genCSRF("/dashboard/settings"),
          "notifications": userSession.getNotifications("/dashboard/settings?tab=general"),
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

ctrl postDashboardSettings:
  ## POST handler for updating settings pages.
  withSession do:
    withBag req.getFields:
      section -> callback do(input: string) -> bool:
        result = input in ["general", "users", "smtp", "plugins"]
      csrf -> callback do(input: string) -> bool:
        result = userSession.validateCSRF("/dashboard/settings", input)

    let fieldsTable = req.getFieldsTable()
    if fieldsTable.isNone:
      userSession.notify("Invalid form data", some("/dashboard/settings"))
      go getDashboardSettings

    let fields = fieldsTable.get()
    let section = fields.getOrDefault("section", "")

    withDBPool do:
      case section
      of "general":
        updateSettings("general", "General application settings", %*{
          "site_name": fields.getOrDefault("site_name", ""),
          "site_description": fields.getOrDefault("site_description", ""),
          "site_keywords": fields.getOrDefault("site_keywords", ""),
          "site_visibility": fields.hasKey("site_visibility"),
          "default_language": fields.getOrDefault("default_language", "en"),
          "timezone": fields.getOrDefault("timezone", "UTC"),
          "maintenance_mode": fields.hasKey("maintenance_mode")
        })
      of "users":
        let minPassLen = try: parseInt(fields.getOrDefault("minimum_password_len", "8")) except: 8
        let passExpDays = try: parseInt(fields.getOrDefault("password_expiration_days", "0")) except: 0
        let lockoutThreshold = try: parseInt(fields.getOrDefault("account_lockout_threshold", "5")) except: 5
        updateSettings("users", "User management settings", %*{
          "user_allow_registration": fields.hasKey("allow_user_registration"),
          "user_require_email_confirmation": fields.hasKey("enable_confirmation_email"),
          "user_password_min_length": minPassLen,
          "user_password_expiration_days": passExpDays,
          "user_two_factor_auth": fields.hasKey("enable_twofa"),
          "user_two_factor_auth_methods": fields.getOrDefault("twofa_delivery_method", "authenticator"),
          "user_enable_account_lockout": fields.hasKey("enable_account_lockout"),
          "user_account_lockout_threshold": lockoutThreshold,
          "user_allow_self_deactivation": fields.hasKey("allow_account_deactivation"),
          "user_allow_self_deletion": fields.hasKey("allow_account_deletion")
        })
      of "smtp":
        let smtpPort = try: parseInt(fields.getOrDefault("smtp_port", "587")) except: 587
        updateSettings("smtp", "SMTP configuration settings", %*{
          "smtp_host": fields.getOrDefault("smtp_host", "localhost"),
          "smtp_port": smtpPort,
          "smtp_username": fields.getOrDefault("smtp_username", ""),
          "smtp_password": fields.getOrDefault("smtp_password", ""),
          "smtp_secure": fields.hasKey("smtp_secure"),
          "smtp_from_email": fields.getOrDefault("smtp_from_email", "")
        })
      of "plugins":
        updateSettings("plugins", "Plugin management settings", %*{
          "plugin_update_checks": fields.hasKey("plugin_update_checks"),
          "maintenance_mode": fields.hasKey("maintenance_mode")
        })
      else:
        userSession.notify("Invalid settings section", some("/dashboard/settings?tab=" & section))
        go getDashboardSettings, [("tab", section)]

    userSession.notify("Settings updated successfully.", some("/dashboard/settings?tab=" & section))
    go getDashboardSettings, [("tab", section)]

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