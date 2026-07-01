# A simple publishing platform powered by Supranim,
# a modern web framework for Nim.
#
# (c) 2026 George Lemon | AGPLv3 License
#     Made by Humans from OpenPeeps
#     https://github.com/openpeeps/sunday

#
# This file is automatically imported by the Supranim framework.
# It is used to define the routes for the application.
#

routes do:
  group "/dashboard":
    {.middleware: [adminOnly].}:
      # Dashboard overview
      get "/"

      # Media routes
      get "/media"
      (get, post) -> "/media/upload"
      (get, delete) -> "/media/{id:id}"

      # Plugins routes
      get "/plugins"
      post "/plugins/manage"
      post "/plugins/manage/csrf"

      # Themes routes
      get "/themes"
      post "/themes/manage"
      post "/themes/upload"

      # Users routes
      get "/users"
      (get, patch, delete) -> "/users/{id:id}"
      (get, post) -> "/users/create"
      get "/users/roles"

      # Settings routes
      (get, post) -> "/settings"
      get "/settings/stats"
      
      post "/settings/freememory"
      post "/settings/backup"

  # Account routes
  get "/account"
  get "/account/verify"

  # Authentication routes
  group "/auth":
    (get, post) -> "/login"
    (get, post) -> "/register"
    (get, post) -> "/forgot-password"
    (get, post) -> "/reset-password"
    get "/logout"

  #
  # Front-end routes
  # The `membership` middleware is applied to all front-end routes
  # TODO Supranim route handler should support applying middleware to multiple routes at once
  #
  get "/" {.middleware: [membership].}
    # GET route links to `getHomepage` controller
  
  # get "/feed.xml"
  #   # GET route links to `getFeed` controller
  
  # get "/sitemap.xml"
  #   # GET route links to `getSitemap` controller

  # # get "/{slug:slug}" {.middleware: [membership].}
  # #   # GET route links to `getSlug` controller, which handles
  # #   # rendering posts and pages based on the slug
  
  # get "/category/{slug:slug}" {.middleware: [membership].}
  #   # GET route links to `getCategorySlug` controller, which renders
  #   # a list of posts in the specified category

  # get "/tag/{slug:slug}"  {.middleware: [membership].}
  #   # GET route links to `getTagSlug` controller, which renders
  #   # a list of posts with the specified tag
