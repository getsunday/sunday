import std/[options, tables, times, strformat, json, os, strutils]

import pkg/[ozark, twofa]
import pkg/kapsis/interactive/prompts

import pkg/supranim/service/events
import pkg/supranim/support/[url, auth, nanoid]

import ../../provider/db

from pkg/supranim/application import appInstance, config

listener "account.password.request":
  ## Event listener for requesting a password reset
  ## link sent to the user email address.
  assert args.isSome()
  {.gcsafe.}:
    withDBPool do:
      # connect to the database and check if the user exists.
      # if found retrieve user's object
      let dbres =
        Models.table(Users)
              .select(["id", "pk", "sk"])
              .where("email", args.get()[0])
              .getAll()
      if unlikely(dbres.isEmpty):
        return # no user found with the given email address. abort listener
      let
        user = dbres.first()
        userId = user.getId()
      # check if the user has already
      # requested a password reset link and if it's not expired
      let anyPassRequests =
        Models.table(UserAccountPasswordResets)
              .selectAll()
              .where("user_id", userId).getAll()
      if anyPassRequests.isEmpty() == false:
        var hasAnyValidRequests: bool
        for anyPassReq in anyPassRequests:
          # todo enimsql must be able to automatically
          # parse columns with DateTime type
          let expValue = anyPassReq.getExpiresAt()
          let expiresAt: DateTime = times.parse(expValue, "yyyy-MM-dd HH:mm:sszz")
      
          if expiresAt > now():
            # the already generated password reset link is still valid
            # omit the generation of a new password reset link
            hasAnyValidRequests = true
          else:
            # todo move the cleanup of expired password reset links
            # to a queue worker (once implemented)
            Models.table(UserAccountPasswordResets)
                  .removeRow()
                  .where("token", anyPassReq.getToken())
                  .exec()
        if hasAnyValidRequests:
          return # the already generated password reset link is still valid

      # otherwise, generate a new password reset link
      # and store it in the database.
      let
        createdAt = now()
        rawToken = generateSalt().toHex()
        signature = sign(secretKeyFromHex(user.getSk()), rawToken).toHex()
        token = fmt"{rawToken}:{signature}"
        # token = boxEncrypt(boxRandomBytes().bin2hex, user.getPk(), user.getSk())
        expInterval = appInstance().config("session.settings.expiration_time").getInt
        # default expiration time is 60 minutes.
        # use `config/session.expiration` to customize the expiration time

      # store the password reset link in the database
      # and send it to the user email address.
      Models.table(UserAccountPasswordResets).insert({
        "user_id": userId,
        "token": token,
        "created_at": $(createdAt),
        "expires_at": $(createdAt + minutes(expInterval))
      }).exec()

      when not defined release:
        displayInfo("account.password.request")
        display("generate password reset link:")
        display($link("/auth/reset-password", {"token": token}))
      else:
        # TODO send the password reset link to the user email address using the configured email provider
        discard

listener "account.register":
  ## Event listener for registering a new user account.
  ## 
  ## Registering a new user account involves creating a new user record in the database
  ## and sending a confirmation email to the user with a link to verify their email address
  ## 
  ## The verification step is important to ensure that the email address provided
  ## by the user is valid and belongs to them. If you want you can disable
  ## the verification step (TODO)
  ## 
  assert args.isSome()
  {.gcsafe.}:
    withDBPool do:
      let fields = args.get()
      let anyUser = Models.table(Users)
                          .select("id")
                          .where("email", fields[0])
                          .getAll()
      
      # check if the user already exists
      # if so, abort the registration process
      if anyUser.isEmpty() == false: return

      # otherwise, create a new user account and store it in the database.
      let (pk, sk) = auth.boxKeys()         # X25519 keys (hex) required for E2EE features like encrypted notes, files, etc.
      let (signPk, signSk) = auth.signKeys() # Ed25519 keys (hex) required for signing messages, generating TOTP secrets, etc.
      # sign it with the user secret key to gen a unique totp secret for the user account
      let totpSecret = sign(signSk.secretKeyFromHex(), generateSalt(16).toHex())
      let userId = Models.table(Users).insert({
          "name": nanoid.generate(size = 12),
          "username": nanoid.generate(size = 32),
          "email": fields[0],
          "pk": pk,
          "sk": sk,
          "sign_pk": signPk,
          "sign_sk": signSk,
          "totp_secret": twofa.genTotpUri(totpSecret.toHex(), "MyApp", "MyCompany"),
          "password": auth.hashPassword(fields[1]),
          "created_at": $(now())
        }).execGet()

      # generate the confirmation link for the freshly
      # created user account and store it in the database
      let confToken = sign(signSk.secretKeyFromHex(), generateSalt(16).toHex()).toHex().toLowerAscii()
      Models.table(UserAccountConfirmations).insert({
        "user_id": $userId,
        "token": confToken,
        "created_at": $(now()),
        "expires_at": $(now() + 10.minutes)
      }).exec()
      
      when not defined release:
        # when not in release mode we'll output the generated user account
        # and the confirmation link to the console this is useful for testing purposes.
        let emailAddress = fields[0]
        let password = fields[1]
        let confirmationLink = $link("/account/verify", {"token": confToken})
        displaySuccess(fmt"""
Created test account:
  E-mail address: {emailAddress}
  Password: {password}
  Confirmation link: {confirmationLink}
""")