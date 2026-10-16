# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[macros, json, strutils, os,
        httpcore, times, options, uri,
        tables, locks, algorithm]

import pkg/supranim/controller
import pkg/supranim/support/slug
import pkg/supranim/core/[services, application, paths]
import pkg/vancode/interpreter/value

import pkg/[tim, iconim, marvdown]
import pkg/kapsis/interactive/prompts
import pkg/ozark/driver/psql
import pkg/openparser/yaml
import pkg/semver

import ./logger, ./locales, ./db

export HttpCode, render, `&*`
export times.now, times.format, iconim

initService Tim[Global]:
  # A singleton service that wraps the Tim Engine
  # and provides a simple interface to render HTML pages
  state do:
    const frontendFallbackTheme = "twentysix"

    type FrontendTheme = object
      name*, dirname*, root*, error*: string
      manifest*: ThemeManifest
      valid*: bool

    var timBackend*: TimEngine
    var timFrontend*: TimEngine
    var frontendEngines: Table[string, TimEngine]
    var frontendInstallPath, frontendThemesRoot, frontendCachePath: string
    var activeFrontendTheme: string
    var frontendLock: Lock

    Icon.init(
      source = storagePath / "icons",
      default = "outline",
      stripAttrs = %*["class"]
    )

    proc frontendThemeNameValid(name: string): bool =
      if name.len == 0 or name.len > 100:
        return false
      for c in name:
        if c notin Letters + Digits + {'.', '-', '_'}:
          return false
      true

    proc parseFrontendTheme(root, dirname: string): FrontendTheme =
      result = FrontendTheme(
        dirname: dirname,
        root: normalizedPath(root / dirname)
      )
      let yamlPath = result.root / "theme.yaml"
      let jsonPath = result.root / "theme.json"
      try:
        var manifest: ThemeManifest
        if fileExists(yamlPath):
          manifest = parseYaml(readFile(yamlPath), ThemeManifest)
        elif fileExists(jsonPath):
          manifest = fromJson(readFile(jsonPath), ThemeManifest)
        else:
          result.error = "Theme manifest not found"
          return
        result.manifest = manifest
        result.name = manifest.name.strip()
        if not frontendThemeNameValid(result.name):
          result.error = "Theme manifest name is missing or invalid"
        elif not dirExists(result.root / "layouts"):
          result.error = "Theme layouts directory is missing"
        elif not dirExists(result.root / "views"):
          result.error = "Theme views directory is missing"
        else:
          result.valid = true
      except CatchableError as e:
        result.valid = false
        result.error = "Theme manifest is invalid: " & e.msg

    proc discoverFrontendThemes*(): seq[FrontendTheme] =
      result = @[]
      if frontendThemesRoot.len == 0 or not dirExists(frontendThemesRoot):
        return
      for kind, path in walkDir(frontendThemesRoot):
        if kind notin {pcDir, pcLinkToDir}:
          continue
        let dirname = extractFilename(path)
        if dirname.len == 0 or dirname[0] == '.':
          continue
        result.add(parseFrontendTheme(frontendThemesRoot, dirname))
      var nameCounts = initTable[string, int]()
      for theme in result:
        if theme.name.len > 0:
          nameCounts.mgetOrPut(theme.name, 0) += 1
      for i in 0 ..< result.len:
        if result[i].name.len > 0 and nameCounts.getOrDefault(result[i].name) > 1:
          result[i].valid = false
          result[i].error = "Duplicate theme name: " & result[i].name
      result.sort(proc (a, b: FrontendTheme): int = cmp(a.name, b.name))

    proc findFrontendTheme(discovered: seq[FrontendTheme], name: string): FrontendTheme =
      for theme in discovered:
        if theme.name == name and theme.valid:
          return theme
      FrontendTheme(valid: false, error: "Theme not found: " & name)

    proc frontendDbBool(value: string): bool =
      value.strip().toLowerAscii() in ["t", "true", "1", "y", "yes"]

    proc syncFrontendThemes*(discovered: seq[FrontendTheme]) =
      if frontendThemesRoot.len == 0 or not dirExists(frontendThemesRoot):
        return
      withDBPool do:
        let rows = Models.table(Themes).selectAll().getAll()
        let hadRows = rows.len > 0
        let stamp = $(now())
        var seen = initTable[string, bool]()
        for theme in discovered:
          if not theme.valid:
            continue
          seen[theme.name] = true
          let existing = Models.table(Themes).selectAll().where("id", theme.name).getAll()
          if existing.isEmpty:
            Models.table(Themes).insert({
              "id": theme.name,
              "dirname": theme.dirname,
              "active": $(theme.name == frontendFallbackTheme and not hadRows),
              "created_at": stamp,
              "updated_at": stamp
            }).exec()
          elif existing.first().getDirname() != theme.dirname:
            Models.table(Themes).update({
              "dirname": theme.dirname,
              "updated_at": stamp
            }).where("id", theme.name).exec()
        for row in rows:
          if not seen.hasKey(row.getId()):
            Models.table(Themes).removeRow().where("id", row.getId()).exec()

    proc readStoredFrontendTheme*(discovered: seq[FrontendTheme]): string =
      withDBPool do:
        let activeRows = Models.table(Themes).selectAll().where("active", "true").getAll()
        if activeRows.isEmpty:
          return ""
        let stamp = $(now())
        var candidates: seq[string]
        for row in activeRows:
          let name = row.getId()
          if findFrontendTheme(discovered, name).valid:
            candidates.add(name)
          else:
            Models.table(Themes).update({
              "active": "false",
              "updated_at": stamp
            }).where("id", name).exec()
        if candidates.len == 0:
          return ""
        candidates.sort()
        if candidates.len > 1:
          logger("Service Tim: multiple active themes found, using " & candidates[0], ERROR)
        let storedRows = Models.table(Themes).select(["id"]).getAll()
        for storedRow in storedRows:
          let storedId = storedRow.getId()
          Models.table(Themes).update({
            "active": $(storedId == candidates[0]),
            "updated_at": stamp
          }).where("id", storedId).exec()
        return candidates[0]

    proc buildFrontendEngine*(name: string, discovered: seq[FrontendTheme]): TimEngine =
      let theme = findFrontendTheme(discovered, name)
      if not theme.valid:
        raise newException(ValueError, theme.error)
      var fallbackName = ""
      if name != frontendFallbackTheme:
        let fallback = findFrontendTheme(discovered, frontendFallbackTheme)
        if fallback.valid:
          fallbackName = fallback.name
      result = newTim(
        enableThemes = true,
        activeThemeName = name,
        fallbackThemeName = fallbackName,
        src = "themes",
        output = ".cached_themes",
        basePath = frontendInstallPath,
        globalData = newJObject()
      )
      result.precompile()
      if result.getView("index") == nil:
        raise newException(ValueError, "Theme does not provide an index view: " & name)
      if result.getLayout("base") == nil:
        raise newException(ValueError, "Theme does not provide a base layout: " & name)

    proc storeFrontendEngine(name: string, engine: TimEngine) =
      withLock frontendLock:
        frontendEngines[name] = engine
        timFrontend = engine
        activeFrontendTheme = name

    proc clearFrontendEngine(name: string) =
      withLock frontendLock:
        if activeFrontendTheme == name:
          timFrontend = nil
          activeFrontendTheme = ""

    proc ensureFrontendSelection*(discovered: seq[FrontendTheme], selected: string): bool =
      if selected.len == 0:
        clearFrontendEngine(activeFrontendTheme)
        return false
      if not findFrontendTheme(discovered, selected).valid:
        return false
      withLock frontendLock:
        if activeFrontendTheme == selected and timFrontend != nil and
            frontendEngines.hasKey(selected):
          return true
      try:
        let engine = buildFrontendEngine(selected, discovered)
        storeFrontendEngine(selected, engine)
        return true
      except CatchableError as e:
        logger("Service Tim: cannot initialize theme " & selected & ": " & e.msg, ERROR)
        return false

    proc activateFrontendTheme*(name: string): bool =
      let discovered = discoverFrontendThemes()
      syncFrontendThemes(discovered)
      if not findFrontendTheme(discovered, name).valid:
        return false
      withLock frontendLock:
        if activeFrontendTheme == name and timFrontend != nil and
            frontendEngines.hasKey(name):
          return true
      var engine: TimEngine
      var haveEngine = false
      withLock frontendLock:
        if frontendEngines.hasKey(name):
          engine = frontendEngines[name]
          haveEngine = true
      if not haveEngine:
        try:
          engine = buildFrontendEngine(name, discovered)
        except CatchableError as e:
          logger("Service Tim: cannot activate theme " & name & ": " & e.msg, ERROR)
          return false
        withLock frontendLock:
          if frontendEngines.hasKey(name):
            engine = frontendEngines[name]
          else:
            frontendEngines[name] = engine
      try:
        withDBPool do:
          let stamp = $(now())
          let storedRows = Models.table(Themes).select(["id"]).getAll()
          for storedRow in storedRows:
            let storedId = storedRow.getId()
            Models.table(Themes).update({
              "active": $(storedId == name),
              "updated_at": stamp
            }).where("id", storedId).exec()
      except CatchableError as e:
        logger("Service Tim: cannot persist active theme " & name & ": " & e.msg, ERROR)
        return false
      storeFrontendEngine(name, engine)
      true

    proc deactivateFrontendTheme*(name: string): bool =
      try:
        withDBPool do:
          let existing = Models.table(Themes).selectAll().where("id", name).getAll()
          if existing.isEmpty:
            return false
          Models.table(Themes).update({
            "active": "false",
            "updated_at": $(now())
          }).where("id", name).exec()
      except CatchableError as e:
        logger("Service Tim: cannot deactivate theme " & name & ": " & e.msg, ERROR)
        return false
      clearFrontendEngine(name)
      true

    proc tryFrontendEngine*(): TimEngine =
      withLock frontendLock:
        result = timFrontend

    proc currentFrontendThemeName*(): string =
      withLock frontendLock:
        result = activeFrontendTheme

    proc frontendThemeCatalog*(): JsonNode =
      let discovered = discoverFrontendThemes()
      syncFrontendThemes(discovered)
      let selected = readStoredFrontendTheme(discovered)
      discard ensureFrontendSelection(discovered, selected)
      result = newJArray()
      withDBPool do:
        let rows = Models.table(Themes).selectAll().getAll()
        var activeById = initTable[string, bool]()
        for row in rows:
          activeById[row.getId()] = frontendDbBool(row.getActive())
        for theme in discovered:
          let active = activeById.getOrDefault(theme.name, false) and theme.valid
          result.add(%*{
            "id": theme.name,
            "dirname": theme.dirname,
            "name": theme.manifest.name,
            "version": $theme.manifest.version,
            "author": theme.manifest.author,
            "description": theme.manifest.description,
            "license": theme.manifest.license,
            "url": theme.manifest.url,
            "active": active,
            "valid": theme.valid,
            "error": theme.error
          })

    proc refreshFrontendThemes*(): JsonNode =
      frontendThemeCatalog()

    proc readinessHtml*(): string =
      """<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sunday Publishing Platform</title>
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0c0c0c;color:#fff;font-family:Inter,system-ui,sans-serif;font-size:18px}
.card{max-width:520px;margin:24px;padding:48px 40px;text-align:center;background:rgba(33,33,33,.5);border-radius:28px}
a{color:#8ab4ff}
</style>
</head>
<body>
<div class="card">
<h1>Are you ready?</h1>
<p>Go to <a href="/dashboard">your dashboard</a> to select a theme and start building your website.</p>
</div>
</body>
</html>"""

    proc frontendErrorHtml*(): string =
      """<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sunday is unavailable</title>
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0c0c0c;color:#fff;font-family:Inter,system-ui,sans-serif;font-size:18px}
.card{max-width:520px;margin:24px;padding:40px;text-align:center;background:rgba(33,33,33,.5);border-radius:28px}
</style>
</head>
<body>
<div class="card">
<h1>Something went wrong</h1>
<p>The active theme could not render this page.</p>
</div>
</body>
</html>"""

    proc resolvePublicAsset*(requestPath: string): string =
      var relativePath = requestPath
      const prefix = "/assets/"
      if not relativePath.startsWith(prefix):
        return ""
      relativePath = normalizedPath(relativePath[prefix.len .. ^1])
      if relativePath.len == 0 or relativePath == "." or isAbsolute(relativePath):
        return ""
      for part in relativePath.split(DirSep):
        if part.len == 0 or part == "." or part == ".." or part[0] == '.':
          return ""
      var roots: seq[string]
      if frontendInstallPath.len > 0:
        let projectAssets = normalizedPath(frontendInstallPath / "storage" / "assets")
        if dirExists(projectAssets):
          roots.add(projectAssets)
      let engine = tryFrontendEngine()
      if engine != nil:
        if engine.activeTheme != nil:
          let activeAssets = normalizedPath(engine.activeTheme.path / "assets")
          if dirExists(activeAssets):
            roots.add(activeAssets)
        let fallback = engine.getFallbackTheme()
        if fallback != nil:
          let fallbackAssets = normalizedPath(fallback.path / "assets")
          if dirExists(fallbackAssets):
            roots.add(fallbackAssets)
      for root in roots:
        let base = normalizedPath(root)
        let full = normalizedPath(base / relativePath)
        if full != base and full.startsWith(base & DirSep) and fileExists(full):
          try:
            let canonical = expandFilename(full)
            let canonicalBase = expandFilename(base)
            if canonical == canonicalBase or canonical.startsWith(canonicalBase & DirSep):
              return canonical
          except OSError:
            continue
      return ""

    proc init*(app: Application, src, output, basePath: string; global = newJObject()) =
      ## Initializes Tim Engine instances for both backend and frontend rendering
      logger("Service Tim: Initializing Tim Engine (backend + frontend)")
      frontendInstallPath = app.paths().getInstallationPath
      frontendThemesRoot = frontendInstallPath / "themes"
      frontendCachePath = frontendInstallPath / ".cached_themes"
      discard existsOrCreateDir(frontendThemesRoot)
      discard existsOrCreateDir(frontendCachePath)
      initLock(frontendLock)
      frontendEngines = initTable[string, TimEngine]()
      timFrontend = nil
      activeFrontendTheme = ""

      block initFrontend:
        let discovered = discoverFrontendThemes()
        syncFrontendThemes(discovered)
        let selected = readStoredFrontendTheme(discovered)
        if selected.len > 0 and not ensureFrontendSelection(discovered, selected):
          withDBPool do:
            Models.table(Themes).update({
              "active": "false",
              "updated_at": $(now())
            }).where("id", selected).exec()
          clearFrontendEngine(selected)
          logger("Service Tim: active theme unavailable, showing readiness page", ERROR)

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

        timBackend.userScript.addProc("parseMarkdown", @[paramDef("md", ttyString)], ttyString,
          proc (args: StackView, argc: int): value.Value =
            return initValue(toHtml(args[0].stringVal[]))
          )

        timBackend.userScript.addProc("parseMarkdown", @[paramDef("md", ttyJson)], ttyString,
          proc (args: StackView, argc: int): value.Value =
            return initValue(toHtml(args[0].jsonVal.getStr()))
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

  api do:
    proc isSPARequest(req: var Request): bool =
      # A simple heuristic to determine if the request is an AJAX request
      # You can customize this based on your frontend framework's conventions
      req.getHeaders().isSome and req.getHeaders().get().hasKey("X-Requested-With")

    template renderFrontend*(view: string, layout: string = "base",
                             httpCode = Http200, local: JsonNode = nil): untyped =
      ## Renders a Tim template using the active frontend engine.
      ## When no theme is active, responds with a static readiness page.
      block:
        let frontendEngine = tryFrontendEngine()
        if frontendEngine == nil:
          respond(Http200, readinessHtml())
        else:
          try:
            respond(httpCode, frontendEngine.themeRender(view, layout, local))
          except TimEngineError as e:
            logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
            respond(Http500, frontendErrorHtml())
          except Exception as e:
            logger("Tim Engine: " & e.msg & "\n" & e.getStackTrace(), ERROR)
            respond(Http500, frontendErrorHtml())
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
