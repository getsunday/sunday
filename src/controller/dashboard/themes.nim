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

import ../../service/provider/[db, session, tim]

ctrl getDashboardThemes:
  ## Handles GET requests to the `/dashboard/themes`
  render("dashboard.themes.list", layout="dashboard", local = &*{
    "themes": [
      {
        "name": "Default Theme",
        "version": "1.0.0",
        "author": "OpenPeeps",
        "description": "The default theme for Sunday.",
        "active": true
      },
      {
        "name": "Dark Mode",
        "version": "1.2.3",
        "author": "Jane Doe",
        "description": "A sleek dark mode theme.",
        "active": false
      }
    ]
  })

ctrl postDashboardThemesManage:
  ## Handles POST requests to `/dashboard/themes/manage`
  json(%*{
    "success": true,
    "message": "Theme management endpoint is under construction."
  })

ctrl postDashboardThemesUpload:
  ## Handles POST requests to `/dashboard/themes/upload`
  json(%*{
    "success": true,
    "message": "Theme upload endpoint is under construction."
  })