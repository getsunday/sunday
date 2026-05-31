# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import pkg/bag
import pkg/ozark/driver/psql

import pkg/supranim/controller

import ../../service/provider/[db, tim]

ctrl getDashboard:
  ## Renders the posts overview dashboard screen.
  withDBPool do:
    # let countPosts = Models.table(Posts).select("id").getAll().len
    # let countComments = Models.table(Comments).select("id").getAll().len
    let countPosts = 42 # placeholder
    let countComments = 1337 # placeholder
    render("dashboard.overview", layout="dashboard", local = &*{
      "countPosts": countPosts,
      "countComments": countComments
    })
    