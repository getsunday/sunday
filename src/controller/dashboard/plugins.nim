# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[os, strutils, times, tables]
import pkg/[bag, pluginkit, tim]
import pkg/ozark/driver/psql

import pkg/ozark/runtimequery
import pkg/supranim/[controller, application]
import pkg/supranim/support/[slug, nanoid]

import ../ctrlutils
import ../../service/provider/[db, session, tim, pluggable, logger]

ctrl getDashboardPlugins:
  ## GET handler for rendering the plugins overview screen in the dashboard
  withSession do:
    withDBPool do:
      let currentTab: Option[string] = req.getTabName()
      let tabs = %*[
        {
          "name": "all",
          "label": "All"
        },
        {
          "name": "installed",
          "label": "Installed"
        },
        {
          "name": "uninstalled",
          "label": "Uninstalled"
        },
        {
          "name": "trash",
          "label": "Trash"
        }
      ]
      let notifications = userSession.getNotifications("/dashboard/plugins?tab=" & currentTab.get("all"))
      case currentTab.get("all")
      of "installed", "uninstalled", "trash":
        render("dashboard.plugins.list", layout="dashboard", local = &*{
          "page_title": "Plugins",
          "page_slug": "plugins",
          "tabs": tabs,
          "currentTab": currentTab.get(),
          "plugins": [],
          "notifications": notifications,
          "permission_icons": {
            "filesystem": $icon("device-floppy"),
            "database": $icon("database"),
            "template": $icon("template"),
            "event": $icon("calendar-event"),
            "middleware": $icon("keyframe-align-center"),
            "settings": $icon("settings"),
          }
        })
      else:
        if currentTab.isSome and currentTab.get() != "all":
          render("errors.4xx") # todo make a custom 4xx error page for invalid tabs
        else:
          var availablePlugins: seq[JsonNode]
          for plugin in pluginManager().manager.plugins():
            let exists = Models.table(Plugins)
                              .select(["id", "status"])
                              .where("id", plugin.getId())
                              .get()
            let pluginStatus =
              # todo get the int status instead of string
              if exists.isEmpty:
                # get the status of the plugin from the plugin manager
                # which can be "loaded" or "invalid" depending on whether
                # the plugin was successfully loaded at startup or not.
                $(plugin.getStatus())
              else:
                "pluginStatusInstalled"
            availablePlugins.add(%*{
              "id": plugin.getId(),
              "status": pluginStatus,
              "name": plugin.getName(),
              "author": plugin.getAuthor(),
              "version": plugin.getVersion(),
              "description": plugin.getDescription(),
              "license": plugin.getLicense(),
              "url": plugin.getUrl(),
            })

          let flashNotifications = userSession.getNotifications("/dashboard/plugins")
          render("dashboard.plugins.list", layout="dashboard", local = &*{
            "page_title": "Plugins",
            "page_slug": "plugins",
            "tabs": tabs,
            "plugins": availablePlugins,
            "notifications": flashNotifications,
            "permission_icons": {
              "filesystem": $icon("device-floppy"),
              "database": $icon("database"),
              "template": $icon("template"),
              "event": $icon("calendar-event"),
              "middleware": $icon("keyframe-align-center"),
              "settings": $icon("settings"),
            }
          })

ctrl postDashboardPluginsManageCsrf:
  ## POST handler for fetching a new CSRF token for plugin management actions
  withSession do:
    let id = req.params["nanoid"]
    if pluginManager().manager.hasPlugin(id):
      let token = userSession.genCSRF("/plugins/" & id & "/manage")
      json(%*{"token": token})
  json(%*{"error": "Plugin not found"}, code = HttpCode(404))

ctrl postDashboardPluginsManage:
  ## POST handler for managing a plugin (installing or uninstalling)
  withSession do:
    withDBPool do:
      if req.getFieldsTable.isNone():
        userSession.notify("Invalid request", some("/dashboard/plugins"))
        go getDashboardPlugins

      # the plugin_id field is required to identify which plugin to manage
      let data = req.getFieldsTable.get()
      if not data.hasKey("plugin_id"): 
        userSession.notify("Plugin ID is required", some("/dashboard/plugins"))
        go getDashboardPlugins
      let id = data["plugin_id"]
      let sundayPlugins = pluginManager()
      let anyPlugins = Models.table(Plugins)
                             .select(["id"]).where("id", id).get()
      if sundayPlugins.manager.hasPlugin(id):
        if anyPlugins.isEmpty:
          let plugin = sundayPlugins.manager.getPlugin(id)
          if sundayPlugins.onInstall.hasKey(id):
            # if the plugin has an `onInstall` schema collected
            # during the loading process, we can execute the
            # provided schema to create any necessary tables
            let schema = sundayPlugins.onInstall[id]
            for name, tableSchema in schema.schemas:
              # let xid = nanoid.generate(defaultAlphabet[2..^1], size = 10)
              # let tableName = "plugin_" & name & "_" & xid
              # sundayPlugins.onUninstallAliases[tableName] = id
              dbcon.exec(createTable(name, tableSchema))
          # the Pluggable Service provider defines a custom
          # callback `onPluginInstall` which can be used to
          # execute any additional logic during plugin installation
          pluggable.onInstallCallback(plugin)
          # flash a success notification and redirect back to
          # the plugins overview screen
          userSession.notify("Plugin installed successfully", some("/dashboard/plugins"))
          logger("PluginManager installed plugin: " & plugin.getId())
          go getDashboardPlugins
        else:
          # uninstalling a plugin involves removing the plugin's record
          # when is explicitly requested by the user from the dashboard.
          Models.table(Plugins)
                .removeRow()
                .where("id", id).exec()
          # flash a success notification and redirect
          # back to the plugins overview screen
          userSession.notify("Plugin uninstalled successfully", some("/dashboard/plugins"))
          logger("PluginManager uninstalled plugin: " & id)
          go getDashboardPlugins
      # flash an error notification if the plugin is not found in the plugin manager
      userSession.notify("Plugin not found", some("/dashboard/plugins"))
      go getDashboardPlugins