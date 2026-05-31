# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[strutils, tables, json, macros, os]
import pkg/ozark/driver/psql
import pkg/kapsis/interactive/prompts

import pkg/supranim/core/services
import pkg/supranim/core/[paths, config]
import pkg/supranim/support/auth

import ./events, ./logger

initService DB[Global]:
  backend do:
    macro loadModels =
      # auto discover /database/models/*.nim
      # nim files prefixed with `!` will be ignored
      result = newStmtList()
      for fModel in walkDirRec(modelPath):
        let f = fModel.splitFile
        if f.ext == ".nim" and f.name.startsWith("!") == false:
          add result, nnkImportStmt.newTree(newLit(fModel))
          add result, nnkExportStmt.newTree(ident(f.name))
    loadModels() # autoload available models

  client do:

    proc putSettings*(tab, description: string, data: JsonNode) =
      ## Utility proc to insert or update settings in the database. Settings
      ## are organized by "tab" for easy retrieval and management
      withDBPool do:
        let res = Models.table(Settings).select(["tab"]).where("tab", tab).getAll()
        if res.isEmpty:
          Models.table(Settings).insert({
            "tab": tab,
            "description": description,
            "data": toJson(data)
          }).exec()

    proc updateSettings*(tab, description: string, data: JsonNode) =
      ## Utility proc to update existing settings in the database
      withDBPool do:
        Models.table(Settings).update({
          "description": description,
          "data": toJson(data)
        }).where("tab", tab).exec()

    proc init*() =
      ## Initializes the database with Sunday's required tables and default settings
      loadEnv()
      initOzarkDatabase(
        address = getEnv("database.address"),
        name = getEnv("database.name"),
        user = getEnv("database.user"),
        password = getEnv("database.password")
      )

      initOzarkPool(10)
      logger("Service Database: Initialize DB service and connection pool")

      # create tables if they don't exist
      try:
        withDBPool do:
          # create database tables if not exists
          Models.table(Settings).prepareTable().exec()
          Models.table(Plugins).prepareTable().exec()

          # user related tables
          Models.table(Users).prepareTable().exec()
          Models.table(UserSessions).prepareTable().exec()
          Models.table(UserAccountConfirmations).prepareTable().exec()
          Models.table(UserAccountEmailConfirmations).prepareTable().exec()
          Models.table(UserAccountPasswordResets).prepareTable().exec()

          # user roles and permissions
          Models.table(UserRoles).prepareTable().exec()
          Models.table(Permissions).prepareTable().exec()
          Models.table(RoleHasPermissions).prepareTable().exec()
          Models.table(UserHasPermissions).prepareTable().exec()
          Models.table(UserHasRoles).prepareTable().exec()

          when not defined release:
            # when running in development mode, checks if there are any
            # users in the database. if not (first time setup), it creates
            # a default demo user.
            let userRes = Models.table(Users).select(["id"]).getAll()
            if userRes.isEmpty:
              event().emit("account.register",
                some(@["test@example.com", "strong password here"]))

          # first time setup, we need to insert default settings into the database
          # these settings can be later updated from the dashboard interface.
          putSettings("general", "General application settings", %*{
            "site_name": "Awesome Sunday Blog",
            "site_description": "Just another blog powered by Sunday",
            "site_keywords": "blog, sunday, cms, nim, supranim",
            "site_visibility": true
          })

          putSettings("users", "User management settings", %*{
            "user_allow_registration": true,
            "user_require_email_confirmation": true,
            "user_password_min_length": 8,
            "user_password_expiration_days": 0, # 0 means passwords never expire
            "user_password_common_dictionary": "",
            "user_two_factor_auth": false,
            "user_two_factor_auth_methods": "authenticator", # any of: "email", "sms", "authenticator"
            "user_enable_account_lockout": false,
            "user_account_lockout_threshold": 5, # number of failed login attempts before lockout
            "user_allow_self_deactivation": false,
            "user_allow_self_deletion": false
          })

          putSettings("stmp", "SMTP configuration settings", %*{
            "smtp_host": "localhost",
            "smtp_port": 587,
            "smtp_username": "",
            "smtp_password": "",
            "smtp_secure": false, # true for TLS/SSL, false for unencrypted
            "smtp_from_email": "noreply@website.com" # todo access this from env variable or something, since it's required for sending emails
          })

          logger("Service Database: Insert default settings into database")

      except DbError as e:
        displayError("Database error: " & e.msg)
