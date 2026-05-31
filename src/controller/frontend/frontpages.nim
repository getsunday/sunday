# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import pkg/supranim/[core/paths, controller]

ctrl getFeedXML:
  ## Renders the RSS feed XML
  json("todo")

ctrl getSitemapXML:
  ## Renders the sitemap XML
  json("todo")

ctrl getSlug:
  ## Renders a post or page based on the slug
  json("todo")

ctrl getCategorySlug:
  ## Renders a list of posts in a category based on the slug
  json("todo")

ctrl getTagSlug:
  ## Renders a list of posts with a tag based on the slug
  json("todo")