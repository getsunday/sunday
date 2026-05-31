# Sunday - A simple publishing platform written in Nim
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/sunday

import std/[os, strutils]

import pkg/[bag, openparser/json]
import pkg/ozark/driver/psql

import pkg/supranim/[core/paths, controller]
import ../../service/provider/[db, session, tim]

ctrl getDashboardMedia:
  ## Renders the media library dashboard screen.
  withDBPool do:
    let mediaItems = Models.table(MediaLibrary)
                           .selectAll() #  .orderDescBy(["uploaded_at"])
                           .getAll()
    render("dashboard.media.list", layout="dashboard", local = &*{
      "mediaItems": mediaItems,
    })

ctrl getDashboardMediaUpload:
  ## Renders the media upload form.
  render("dashboard.media.upload", layout="dashboard", local = &*{})

ctrl postDashboardMediaUpload:
  ## Handles media file uploads.
  json({"message": "Media upload is not implemented yet."})

ctrl getDashboardMediaId:
  ## Renders the media item details screen.
  let mediaId = req.params["id"]
  withDBPool do:
    let mediaItem = Models.table(MediaLibrary)
                          .selectAll()
                          .where("id", mediaId)
                          .get()
    if likely(not mediaItem.isEmpty):
      render("dashboard.media.detail", layout="dashboard", local = &*{
        "mediaItem": mediaItem,
      })
    render("errors.4xx")

ctrl deleteDashboardMediaId:
  ## Handles media file deletion.
  json({"message": "Media deletion is not implemented yet."})