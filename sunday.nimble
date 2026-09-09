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
requires "supranim >= 0.1.9[powpow]"
requires "supranim_session >= 0.1.2"
requires "tim >= 0.2.7"
requires "bag >= 0.1.0"
requires "openparser >= 0.1.2"
requires "ozark >= 0.1.6"
requires "iconim >= 0.1.0"
requires "twofa >= 0.1.0"
requires "tiptap >= 0.1.0"
requires "multipart >= 0.1.2"
requires "marvdown >= 0.1.2"
requires "oris >= 0.1.0"
requires "pluginkit >= 0.1.1"

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