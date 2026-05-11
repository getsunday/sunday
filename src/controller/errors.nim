# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import supranim/[controller]
import ../service/provider/tim

ctrl get4xx:
  ## Renders a 4xx error page
  tim.render("errors.4xx")

ctrl get5xx:
  ## Renders a 5xx error page
  tim.render("errors.5xx")