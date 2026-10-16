# Host-side runtime for declarative plugin pages.
#
# This module links the Tim engine and the HTTP layer, so it is used by the
# application only. The schema format, validation and Tim source generation
# live in `plugin_pages`, which stays importable from unit tests.

import std/[json, strutils, tables, options, httpcore, os, times]
import pkg/tim
import pkg/vancode/interpreter/manager
import pkg/openparser/json
import pkg/ozark/driver/psql
import pkg/supranim/core/[request, response, router, application, autolink]

import ./plugin_pages
import ./provider/[tim, db, logger]
import ./middleware/auth

export plugin_pages

var hostedPluginPages = initTable[string, PluginPage]()
  ## Host-owned page routes by request path.

proc compilePluginPageView*(pluginName, pageId, source: string): string =
  ## Compiles page Tim source into the backend engine and returns the
  ## dotted view key used with `render`.
  let engine = getTimBackInst()
  let viewPath = ("plugin" / pluginName / pageId) & ".timl"
  let tpl = TimTemplate(id: viewPath, templateType: ttView,
    embeddedCode: some(source))
  if not precompileEmbeddedTemplate(engine, tpl, sharedManager()):
    raise newException(ValueError, "Could not compile plugin page: " & pageId)
  engine.views[engine.config.compilation.viewsPath / viewPath] = tpl
  "plugin." & pluginName & "." & pageId

proc registerPluginPage*(page: PluginPage) =
  ## Registers a compiled page for request handling.
  hostedPluginPages[page.path] = page

proc handlePluginPage*(req: var Request, res: var Response) {.nimcall, gcsafe.} =
  ## Serves host-owned plugin pages: loads declared data and renders the
  ## compiled view inside the dashboard layout.
  {.gcsafe.}:
    let path = req.getUriPath()
    if not hostedPluginPages.hasKey(path):
      req.send(Http404, "Page not found")
      return
    let page = hostedPluginPages[path]
    try:
      let rows = loadPluginPageData(page)
      var local = &*{
        "page_title": page.label,
        "page_slug": page.id,
        "notifications": []
      }
      local[page.data.dataKey] = rows
      let html = getTimBackInst().render(page.viewKey, page.layout, local)
      req.send(Http200, html)
    except TimEngineError as e:
      logger("Plugin pages: " & e.msg, ERROR)
      try:
        req.send(Http500, getTimBackInst().render("errors.5xx", "dashboard",
          %*{"page_title": "Error", "page_slug": "error", "notifications": []}))
      except CatchableError:
        req.send(Http500, "Internal server error")
    except CatchableError as e:
      logger("Plugin pages: " & e.msg, ERROR)
      req.send(Http500, "Internal server error")

proc registerPluginPageRoute*(page: PluginPage) =
  ## Registers the host-owned GET route behind the admin middleware.
  registerRoute(App.router, (page.path, page.path), HttpGet,
    handlePluginPage, middlewares = @[adminOnly])

proc removeHostedPluginPages*(pluginId: string): seq[PluginPage] =
  ## Drops a plugin's entries from the hosted page lookup table and
  ## returns the removed pages so their routes and compiled views can
  ## be unregistered by the caller.
  for path, page in hostedPluginPages.pairs:
    if page.pluginId == pluginId:
      result.add(page)
  for page in result:
    hostedPluginPages.del(page.path)

proc unregisterPluginPages*(pluginId: string) =
  ## Removes a plugin's host-owned page routes and compiled views.
  for page in removeHostedPluginPages(pluginId):
    unregisterRoute(App.router, (page.path, page.path), HttpGet)
    let engine = getTimBackInst()
    engine.views.del(engine.config.compilation.viewsPath /
      ("plugin" / page.pluginName / page.id) & ".timl")
    logger("PluginManager unregistered page: " & page.path)
