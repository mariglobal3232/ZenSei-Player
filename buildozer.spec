[app]
title = ZenSei
package.name = zensei
package.domain = org.zensei
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,mp3,json
version = 0.1

# Container handles dependencies. We just list the python packages.
requirements = python3,kivy,requests,openssl,sqlite3

orientation = portrait
fullscreen = 1
android.presplash_color = #000000
android.permissions = INTERNET,READ_EXTERNAL_STORAGE,WRITE_EXTERNAL_STORAGE
android.api = 33
android.minapi = 21
android.private_storage = True

# If you uploaded an icon.png, uncomment the line below:
# icon.filename = icon.png

[buildozer]
log_level = 2
warn_on_root = 1
