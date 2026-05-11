# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import pkg/supranim/model

newModel Plugins:
  id {.pk.}: Varchar(40)
  status: Int4 = 0 # 0 = not installed, 1 = installed, 2 = error
  filepath: Text
  database_schema {.nullable.}: JSON
  settings_schema {.nullable.}: JSON
  installed_at {.notnull.}: TimestampTz