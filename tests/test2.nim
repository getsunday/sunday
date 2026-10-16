# Debug: dump generated Tim source for a media-like page.
import std/[json, tables, strutils]
import unittest

import service/plugin_pages

let pageNode = %*{
  "id": "media",
  "label": "Media Library",
  "path": "/dashboard/media",
  "layout": "dashboard",
  "data": {
    "model": "MediaLibrary",
    "columns": ["id", "filename", "filepath", "uploaded_at"],
    "order": "uploaded_at desc",
    "limit": 48,
    "as": "mediaItems"
  },
  "body": [
    {"type": "heading", "level": 2, "text": "Media Library"},
    {"type": "row", "children": [
      {"type": "col", "size": 12, "children": [
        {"type": "tabs", "children": [
          {"type": "link", "label": "All", "href": {"dashboard": "media"}},
          {"type": "link", "label": "Images",
           "href": {"dashboard": "media?tab=images"}, "icon": "photo-circle"}
        ]}
      ]}
    ]},
    {"type": "grid", "in": "mediaItems", "item": "mediaItem", "cols": 6,
     "children": [
      {"type": "card", "children": [
        {"type": "image",
         "src": {"bind": "mediaItem.filepath"},
         "alt": {"bind": "mediaItem.filename"}},
        {"type": "text", "bind": "mediaItem.filename", "muted": true}
      ]}
    ]},
    {"type": "empty", "key": "mediaItems", "children": [
      {"type": "text", "text": "No media items yet."}
    ]}
  ]
}

test "page schema converts to tim source":
  let src = pageToTiml(pageNode, "mediaItems")
  check "h2: \"Media Library\"" in src
  check "ul.nav.nav-underline" in src
  check "href=dashboard(\"media\")" in src
  check "for $mediaItem in $this[\"mediaItems\"]:" in src
  check "img.card-img-top src=$mediaItem[\"filepath\"]" in src
  check "if len($this[\"mediaItems\"]) == 0:" in src

test "invalid page schemas are rejected":
  var noBody = parseJson($pageNode)
  noBody.delete("body")
  check validatePluginPagesSchema(%*{"pages": [noBody]},
    {"media_library": {"id": "serial"}.toTable}.toTable).len > 0
  check validatePluginPagesSchema(%*{"pages": []},
    initTable[string, Table[string, string]]()).len > 0
