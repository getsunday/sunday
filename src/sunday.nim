# Sunday - A simple publishing platform powered by Supranim
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday


#
# This is the main file for the Supranim application.
#
# It initializes the application, loads configurations,
# and sets up the necessary services and middlewares.
#
import std/os

import pkg/supranim
import pkg/supranim/core/paths

#
# Init core modules using `init` macro
#
App.init()

#
# Define CLI commands for the application
#

proc startCommand(v: Values) =
  ## Kapsis `init` command handler
  initStartCommand(v, createDirs = false)

proc updateCommand(v: Values) =
  ## Kapsis `update` command handler
  displayInfo("Checking for updates...")

App.cli do:
  start path(project):
    ## Start a Sunday app from specified directroy
  
  update:
    ## Check for updates to Sunday platform


#
# Initialize available Service Providers.
#
# Configuration files are defined as YAML in the
# `config/` directory.
#
App.services do:
  # Initialize Storage Service
  storage.init(App)

  # Initialize Logger Service
  logger.init()

  # Initialize the global event emitter service
  events.init()

  # Initialize Ozark Database Engine
  db.init()
  
  # Init Oris Internationalization Service
  locales.init()

  # Initialize Tim Templating Engine before the Plugin Manager:
  # declarative plugin pages are compiled into the backend
  # Tim instance while plugins load.
  tim.init(
    App,
    App.config("tim.source").getStr,
    App.config("tim.output").getStr,
    supranim.basePath,
    global = %*{
      "isDev": (when defined release: false else: true),
      "browserSync": {
        "appPort": App.config("server.port").getInt,
      },
      "homepage_cover": "/assets/photo-1579169703977-e4575236583c.jpeg",
      "login_cover": ""
    }
  )

  # Initialize Sunday's Plugin Manager
  pluggable.init(App)

  when defined release: # init static assets
    assets.embedAssets("assets")
    assets.embedDirectory("storage/icons", "icons")

macro loadLanguages =
  # Macro for loading all language files from the i18n directory at compile time
  result = newStmtList()
  for localModule in walkDirRec(basePath / "service" / "i18n"):
    if localModule.endsWith(".nim"):
      let f = localModule.splitFile
      if f.name[0] notin ['!', '_']:
        add result, nnkImportStmt.newTree(newLit(localModule))

loadLanguages()

when defined release:
  # Preload embedded assets into memory for faster access in production
  assets.preloadBundle("assets")
  assets.preloadBundle("icons")

  App.withAssetsHandler:
    proc (req: var Request, res: var Response, hasFoundResource: var bool) =
      when defined release:
        # Serve static assets from the embedded StaticBundle
        req.sendEmbeddedAsset(req.path, res.getHeaders(), hasFoundResource)
      if not hasFoundResource and req.path.startsWith("/assets/"):
        # Serve project assets, then fall back to the active theme
        # and the default theme without copying theme files.
        req.sendAssets(req.path, res.getHeaders(), hasFoundResource)
        if not hasFoundResource:
          let themeAsset = resolvePublicAsset(req.path)
          if themeAsset.len > 0:
            req.sendAssetFile(themeAsset, res.getHeaders())
            hasFoundResource = true

#
# Starts the application. This will start the HTTP
# server and listen for incoming requests.
#
# The application will be available at the specified port.
#
App.run()