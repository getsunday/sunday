# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

import std/[times, sequtils]
import pkg/[bag, kapsis/cli]
import pkg/ozark/driver/psql

import pkg/supranim/controller
import pkg/supranim/support/auth

import ../service/provider/[db, session, tim, events]

import pkg/supranim_session/controller/[login, register, forgot]

ctrl getAuthLogin:
  ## GET handler renders authentication page
  login.getLogin(getAccount)

ctrl postAuthLogin:
  ## POST handle authentication requests
  login.postLogin(getDashboard)

ctrl getAuthForgotPassword:
  ## GET handler renders the forgot password page
  forgot.getForgotPassword(getAccount)

ctrl postAuthForgotPassword:
  ## POST handle for forgot password requests
  forgot.postForgotPassword(getAccount)

ctrl getAuthResetPassword:
  ## GET renders the `/auth/reset-password` page
  forgot.getResetPassword(getAccount)

ctrl postAuthResetPassword:
  ## POST handle for reset password requests
  forgot.postResetPassword()

ctrl getAuthLogout:
  ## GET handle for logging out.
  ## This will clear the session and redirect to the login page.
  login.getLogout(getAuthLogin)

ctrl getAuthRegister:
  ## GET handle for rendering the registration page
  register.getRegister()

ctrl postAuthRegister:
  ## POST handle for registering a new user
  register.postRegister()

ctrl getAuth:
  ## GET handler for `/auth` route
  ## Redirects to dashboard if authenticated, else to login page
  go(getAuthLogin)