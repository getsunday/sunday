import std/[macros, os]

when defined(macosx):
  --passL:"/opt/local/lib/libevent.a"
  --passL:"/opt/local/lib/libevent_pthreads.a"
  --passL:"/usr/local/lib/libmonocypher.a"
  --passC:"-I /opt/local/include"
  --passC:"-I /usr/local/include"
  --passC:"-Wno-incompatible-function-pointer-types"
elif defined(linux):
  --passL:"-L/usr/local/lib/lib -L/usr/local/lib -Wl,-rpath,/usr/local/lib/lib -Wl,-rpath,/usr/local/lib -levent -levent_pthreads -lmonocypher"
  # --passL:"/usr/lib/x86_64-linux-gnu/libevent.a"
  # --passL:"/usr/lib/x86_64-linux-gnu/libevent_pthreads.a"
  # --passL:"/usr/lib/lib/x86_64-linux-gnu/libmonocypher.a"
  --passC:"-I /usr/include"

--define:supraNative
--mm:atomicArc
--deepcopy:on
--define:webapp # todo supWebApp
--define:ssl
--define:supraFileserver

--forceBuild:on
--define:avx2
--passC:"-mavx2"
--passL:"-mavx2"

when defined supranimDebug:
  --define:checkBounds
  --define:assertions
  --define:useMalloc
  --passC:"-fsanitize=address -fno-omit-frame-pointer"
  --passL:"-fsanitize=address"

when not defined release:
  --define:timHotCode
else:
  let outputEmbedAssets = getProjectPath().parentDir() / ".cache" / "embed_assets.nim"
  let assetsPath = absolutePath(joinPath(getProjectPath() / "storage", "assets"))
  if dirExists(assetsPath):
    exec "supra bundle.assets \"" & assetsPath & "\" \"" & outputEmbedAssets & "\""

  let outputSVGIcons = getProjectPath().parentDir() / ".cache" / "embed_storage_icons.nim"
  let iconsPath = absolutePath(joinPath(getProjectPath() / "storage", "icons"))
  if dirExists(iconsPath):
    exec "supra bundle.assets \"" & iconsPath & "\" \"" & outputSVGIcons & "\""

--path:"/Users/georgelemon/Development/packages/supranim-packages/pluginkit/src"