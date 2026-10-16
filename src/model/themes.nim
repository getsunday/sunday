# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import pkg/supranim/model

newModel Themes:
  id {.pk.}: Varchar(100)
  dirname {.notnull.}: Varchar(255)
  active {.notnull.}: Boolean = false
  created_at {.notnull.}: TimestampTz
  updated_at {.notnull.}: TimestampTz
