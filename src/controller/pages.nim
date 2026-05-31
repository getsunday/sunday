# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[os, json]

import pkg/bag
import pkg/ozark/driver/psql

import pkg/supranim/[core/paths, controller]
import ../service/provider/[db, session, tim]

ctrl getHomepage:
  ## renders the home page
  renderFrontend("index")
