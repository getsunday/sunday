import std/[tables, options]
import pkg/supranim/controller

proc getTabName*(req: var Request, default = "all"): Option[string] =
  ## Utility proc to get the current active `?tab=` query parameter from the
  ## request with an optional default value
  if req.getQuery() != nil:
    if req.getQuery().hasKey("tab") and req.getQuery()["tab"] != default:
      return some(req.getQuery()["tab"])
  none(string)