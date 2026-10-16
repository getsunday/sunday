# Tests for route deregistration used by plugin uninstall.
import std/[httpcore, tables, options]
import unittest

import pkg/supranim/core/[router, request, response]
import pkg/supranim/core/autolink

proc dummyHandler(req: var Request, res: var Response) =
  discard

test "unregistering a static route removes it":
  var r = newHttpRouter()
  r.registerRoute(("/dash-test", "/dash-test"), HttpGet, dummyHandler)
  check r.httpGet.hasKey("/dash-test")
  r.unregisterRoute(("/dash-test", "/dash-test"), HttpGet)
  check not r.httpGet.hasKey("/dash-test")

test "unregistering uses the autolinked key for dynamic routes":
  var r = newHttpRouter()
  let autolinked = autolinkController("/media/{id:id}", HttpGet)
  let rp = if autolinked.params.isSome(): autolinked.params.get() else: @[]
  r.registerRoute((autolinked[1], autolinked[2]), HttpGet, dummyHandler,
    routeParams = rp)
  check r.httpGet.hasKey(autolinked[2])
  r.unregisterRoute((autolinked[1], autolinked[2]), HttpGet)
  check not r.httpGet.hasKey(autolinked[2])

test "unregistering only removes the given method":
  var r = newHttpRouter()
  r.registerRoute(("/dash-test", "/dash-test"), HttpGet, dummyHandler)
  r.registerRoute(("/dash-test", "/dash-test"), HttpDelete, dummyHandler)
  r.unregisterRoute(("/dash-test", "/dash-test"), HttpGet)
  check not r.httpGet.hasKey("/dash-test")
  check r.httpDelete.hasKey("/dash-test")

test "unregistering an unknown route is a no-op":
  var r = newHttpRouter()
  r.unregisterRoute(("/dash-missing", "/dash-missing"), HttpGet)
  check not r.httpGet.hasKey("/dash-missing")
