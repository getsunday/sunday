# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import pkg/bag
import pkg/ozark/driver/psql
import pkg/supranim/[controller, application]

import ../ctrlutils
import ../../service/provider/[db, session, tim, logger]

ctrl getDashboardThemes:
  ## Handles GET requests to the `/dashboard/themes`
  withSession do:
    let catalog = refreshFrontendThemes()
    let currentTab: Option[string] = req.getTabName()
    let tabs = %*[
      {"name": "all", "label": "All"},
      {"name": "active", "label": "Active"},
      {"name": "inactive", "label": "Inactive"}
    ]
    let notifications = userSession.getNotifications("/dashboard/themes")
    let tab = currentTab.get("all")
    if tab notin ["all", "active", "inactive"]:
      render("errors.4xx", layout="dashboard")
    var visible = newJArray()
    var invalidThemes = 0
    for theme in catalog:
      if not theme["valid"].getBool():
        inc invalidThemes
      let active = theme["active"].getBool()
      if tab == "all" or (tab == "active") == active:
        visible.add(theme)
    render("dashboard.themes.list", layout="dashboard", local = &*{
      "page_title": "Themes",
      "page_slug": "themes",
      "tabs": tabs,
      "currentTab": tab,
      "themes": visible,
      "hasInvalidThemes": invalidThemes > 0,
      "notifications": notifications,
      "csrfToken": userSession.genCSRF("/dashboard/themes/manage")
    })

ctrl postDashboardThemesManage:
  ## Handles POST requests to `/dashboard/themes/manage`
  withSession do:
    withBag req.getFields:
      theme_id -> callback do(input: string) -> bool:
        result = input.len > 0 and input.len <= 100
      action -> callback do(input: string) -> bool:
        result = input == "activate" or input == "deactivate"
      csrf -> callback do(input: string) -> bool:
        result = userSession.validateCSRF("/dashboard/themes/manage", input)
    do:
      if inputBag.isInvalid:
        userSession.notify("Invalid theme request", some("/dashboard/themes"))
        go getDashboardThemes

    let fields = req.getFieldsTable.get()
    let name = fields.getOrDefault("theme_id", "")
    let action = fields.getOrDefault("action", "")
    
    try:
      if action == "activate":
        if activateFrontendTheme(name):
          userSession.notify("Theme activated successfully", some("/dashboard/themes"))
        else:
          userSession.notify("Theme is unavailable and cannot be activated", some("/dashboard/themes"))
      else:
        if deactivateFrontendTheme(name):
          userSession.notify("Theme deactivated successfully", some("/dashboard/themes"))
        else:
          userSession.notify("Theme was not found", some("/dashboard/themes"))
    except CatchableError as e:
      logger("Theme management failed for " & name & ": " & e.msg, ERROR)
      userSession.notify("Theme management failed", some("/dashboard/themes"))
    go getDashboardThemes
