# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday


import supranim/[middleware]
from std/strutils import startsWith

# newBaseMiddleware i18n:
#   # Routing can be internationalized by sub-path `/it/products`.
#   # You can redirect the user based on the locale inside
#   # a BaseMiddleware.
#   # echo req.getUriPath.startsWith("/ro/")
#   discard