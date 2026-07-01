# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[macros, json, strutils, os,
        httpcore, times, options, uri]

import pkg/supranim/controller
import pkg/supranim/support/slug
import pkg/supranim/core/[services, application, paths]
import pkg/vancode/interpreter/value

import pkg/[tim, iconim]
import pkg/kapsis/interactive/prompts

import ./logger, ./locales

export HttpCode, render, `&*`
export times.now, times.format, iconim

initService Tim[Global]:
  # A singleton service that wraps the Tim Engine
  # and provides a simple interface to render HTML pages
  backend do:
    var timBackend*: TimEngine
    var timFrontend*: TimEngine

    Icon.init(
      source = storagePath / "icons",
      default = "outline",
      stripAttrs = %*["class"]
    )

    proc init*(app: Application, src, output, basePath: string; global = newJObject()) =
      ## Initializes Tim Engine instances for both backend and frontend rendering
      logger("Service Tim: Initializing Tim Engine (backend + frontend)")
      # Ensure the themes directory exists at installation path
      let themesPath = "themes"
      let cachedThemesPath = ".cached_themes"
      block initFrontend:
        discard existsOrCreateDir(app.paths().getInstallationPath / themesPath)
        discard existsOrCreateDir(app.paths().getInstallationPath / cachedThemesPath)

        timFrontend = newTim(
          enableThemes = true,
          activeThemeName = "twentysix",
          src = themesPath,
          output = cachedThemesPath,
          basePath = app.paths().getInstallationPath,
          globalData = newJObject()
        )

        timFrontend.precompile()

      block initBackend:
        # Initialize the backend Tim Engine instance
        timBackend = newTim(
          src = src,
          output = output,
          basePath = basePath,
          globalData = global
        )

        # initialize global data for plugins
        timBackend.globalData["plugins"] = newJArray()

        # predefine foreign functions
        timBackend.userScript.addProc("slugify", @[paramDef("s", ttyString)], ttyString,
          proc (args: StackView, argc: int): value.Value =
            ## Convert a string to a URL-friendly slug
            return initValue(slugify(args[0].stringVal[]))
          )

        timBackend.userScript.addProc("dashboard", @[paramDef("x", ttyString)], ttyString,
          proc (args: StackView, argc: int): value.Value =
            # prefix a link with `/dashboard/`
            return initValue("/dashboard/" & args[0].stringVal[])
          )

        timBackend.userScript.addProc("icon", @[paramDef("name", ttyString)], ttyString,
          proc (args: StackView, argc: int): value.Value =
            # Return an HTML string for an icon
            return initValue($icon(args[0].stringVal[]).size(18))
          )

        timBackend.userScript.addProc("getCurrentTab", @[paramDef("path", ttyJson)], ttyString,
          proc (args: StackView, argc: int): value.Value =
            # A simple helper to determine the current active tab
            # based on the given request path.
            for q in decodeQuery(parseUri(args[0].jsonVal.getStr()).query):
              if q[0] == "tab":
                return initValue(q[1])
            return initValue("")
          )

        timBackend.userScript.addProc("i18n", @[paramDef("key", ttyString)], ttyString,
          proc (args: StackView, argc: int): value.Value =
            # A helper to translate a key using the I18n service
            return initValue(i18n().translate(args[0].stringVal[]))
          )

        tim.initCommonStorage do:
          {
            "path": req.getUrl(),
            "currentYear": now().format("yyyy"),
            "navigation": (
              # this looks bad but it's necessary for injecting
              # plugin-provided navigation links from the database into
              # the layout's navigation menu.
              #
              # we use database storage here because most plugin data is
              # stored in the database for allowing user customization and persistence
              var plugins = newJArray()
              withDBPool do:
                # let res = Models.table(Plugins).select(["id", "settings_schema"]).getAll()
                let res = Models.rawSQL("SELECT id, settings_schema FROM plugins ORDER BY (settings_schema->'navigation'->>'order')::int;").getWith(Plugins)
                if not res.isEmpty:
                  for plugin in res:
                    let settings = plugin.getSettingsSchema()
                    if settings.len > 0:
                      let schema = parseJson(settings)
                      if schema.hasKey("navigation") and schema["navigation"].hasKey("items"):
                        plugins.add(%*{
                          "id": plugin.getId(),
                          "items": schema["navigation"]["items"]
                        })
              plugins
            )
          }
        
        timBackend.precompile()

    proc getTimBackInst*: TimEngine =
      # Returns the singleton instance of the Tim Engine
      if timBackend == nil:
        raise newException(ValueError, "Tim Engine is not initialized for backend rendering")
      return timBackend

    proc getTimFrontInst*: TimEngine =
      # Returns the singleton instance of the frontend Tim Engine
      if timFrontend == nil:
        raise newException(ValueError, "Tim Engine is not initialized for frontend rendering")
      return timFrontend

  client do:
    proc isSPARequest(req: var Request): bool =
      # A simple heuristic to determine if the request is an AJAX request
      # You can customize this based on your frontend framework's conventions
      req.getHeaders().isSome and req.getHeaders().get().hasKey("X-Requested-With")

    template renderFrontend*(view: string, layout: string = "base",
                             httpCode = Http200, local: JsonNode = nil): untyped =
      ## Renders a Tim template using the frontend engine and sends it as an HTTP response.
      ## It must be used within a route handler (controller).
      try:
        let html = getTimFrontInst().themeRender(view, layout, local)
        respond(httpCode, html)
      except TimEngineError as e:
        logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
        let html = getTimFrontInst().themeRender("errors.5xx", layout, local)
        respond(Http500, html)
      except Exception as e:
        logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
        let html = getTimFrontInst().themeRender("errors.5xx", layout, local)
        respond(Http500, html)
      return # blocks further execution in the route handler after rendering the view

    template render*(view: string, layout: string = "base",
                      httpCode = Http200, local: JsonNode = nil): untyped =
      ## Renders a Tim template and sends it as an HTTP response.
      ## It must be used within a route handler (controller).
      try:
        respond(httpCode, getTimBackInst().render(view, layout, local))
      except TimEngineError as e:
        logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
        respond(Http500, getTimBackInst().render("errors.5xx", layout, local))
      except Exception as e:
        logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
        respond(Http500, getTimBackInst().render("errors.5xx", layout, local))
      return # blocks further execution in the route handler after rendering the view

    template renderView*(view: string, httpCode = Http200, local: JsonNode = nil): untyped =
      ## Renders a Tim view without a layout and sends it as an HTTP response.
      ## This can be used for rendering partials or standalone views.
      try:
        respond(httpCode, getTimBackInst().renderView(view, local))
      except TimEngineError as e:
        logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
        respond(Http500, getTimBackInst().renderView("errors.5xx", local))
      except Exception as e:
        logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
        respond(Http500, getTimBackInst().renderView("errors.5xx", local))
      return # blocks further execution in the route handler after rendering the view