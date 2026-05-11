# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[strutils, tables, json, macros, os]
import pkg/ozark
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
    proc init*() =
      loadEnv()
      ozark.initOzarkDatabase(
        address = getEnv("database.address"),
        name = getEnv("database.name"),
        user = getEnv("database.user"),
        password = getEnv("database.password")
      )

      initOzarkPool(10)
      logger("Service Database: Initialize DB service and connection pool")

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
            let userRes = Models.table(Users)
                                .selectAll().where("id", "1")
                                .getAll()
            if userRes.isEmpty:
              event().emit("account.register",
                some(@["test@example.com", "strong password here"]))

          # first time setup
          let hasSettings = Models.table(Settings).selectAll().getAll().isEmpty == false
          if not hasSettings:
            Models.table(Settings).insert({
              "tab": "general",
              "description": "General application settings",
              "data": toJson(%*{
                "site_name": "Awesome Sunday Blog",
                "site_description": "Just another blog powered by Sunday",
                "site_keywords": "blog, sunday, cms, nim, supranim",
                "site_visibility": true
              })
            }).exec()
            logger("Service Database: Insert default settings into database")

      except DbError as e:
        displayError("Database error: " & e.msg)