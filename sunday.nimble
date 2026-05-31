# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "Sunday publishing platform built with Supranim"
license       = "AGPL-3.0"
srcDir        = "src"
bin           = @["sunday"]
binDir        = "build"


# Dependencies

requires "nim >= 2.0.0"
requires "supranim#head"
requires "supranim_session"
requires "tim >= 0.2.2"
requires "limiter#head"
requires "bag"
requires "openparser"
requires "zippy"
requires "ozark#head"
requires "iconim#head"
requires "twofa"
requires "tiptap"
requires "multipart"
requires "marvdown"
requires "e2ee"
requires "supra"
requires "oris#head"
# requires "pluginkit#head"

task prod, "Generate a production build":
  exec "nimble build -d:release"

import std/[os, strutils]
task services, "Build all services":
  # Discover and build all service providers
  for src in walkDir("./src/service"):
    let file = splitFile(src.path)
    if file.ext == ".nim":
      exec "nimble c --opt:speed -d:useMalloc --path: --mm:arc --out:./bin/" & bin[0] & "_" & file.name & " " & src.path

task service, "Build a Supranim Service":
  # Build a specific service by name
  let params = commandLineParams()
  exec "nimble c --opt:speed -d:useMalloc --path: --mm:arc --out:./bin/" & bin[0] & "_" & params[^1] & " ./src/service/" & params[^1] & ".nim"