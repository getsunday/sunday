# Sunday - A simple publishing platform written in Nim
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/sunday

import std/[os, json, strutils]

import pkg/bag
import pkg/ozark/driver/psql

import pkg/supranim/[core/paths, controller]
import ../../service/provider/[db, session, tim]

ctrl getDashboardUsers:
  ## Renders the users dashboard screen.
  withDBPool do:
    withSession do:
      let users = Models.table(Users).select(["name", "is_confirmed", "created_at"]).getAll()
      let flashNotifications = userSession.getNotifications("/dashboard/plugins").get(@[])
      render("dashboard.users.list", layout="dashboard", local = &*{
        "users": users,
        "notifications": flashNotifications,
      })

ctrl getDashboardUsersId:
  ## Renders the user edit screen for a specific user.
  let userId = req.params["id"]
  withDBPool do:
    let currentUser = Models.table(Users).selectAll().where("id", userId).getAll()
    render("dashboard.users.edit", layout="dashboard", local = &*{
      "user": currentUser.first()
    })

ctrl patchDashboardUsersId:
  ## Handles the form submission for updating a user's information.
  let userId = req.params["id"]
  let someData = req.getBodyData(JsonNode)
  if someData.isNone:
    json("No data provided")

ctrl deleteDashboardUsersId:
  ## Handles the form submission for deleting a user.
  let userId = req.params["id"]
  withDBPool do:
    Models.table(Users).removeRow().where("id", userId).exec()
    # if deleteResult.rowsAffected > 0:
    #   json("User deleted successfully")
    # else:
    #   json("User not found")

ctrl getDashboardUsersCreate:
  ## Renders the user creation screen in the dashboard.
  render("dashboard.users.create", layout="dashboard")

ctrl postDashboardUsersCreate:
  ## Handles the form submission for creating a new user.
  let someData = req.getBodyData(JsonNode)
  json("No data provided")

ctrl getDashboardUsersRoles:
  ## Renders the user roles management screen in the dashboard.
  render("dashboard.users.roles", layout="dashboard")