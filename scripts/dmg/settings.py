# dmgbuild settings for the Takt disk image, used by scripts/package-unsigned.sh:
#   dmgbuild -s scripts/dmg/settings.py -D app=<path to Takt.app> [-D icon=<.icns>] Takt <out.dmg>
# Icon positions must match scripts/dmg/make-background.py.
import os.path

# `defines` is provided by dmgbuild (values passed with -D).
app = defines["app"]  # noqa: F821
icon_path = defines.get("icon")  # noqa: F821
here = os.path.dirname(os.path.abspath(settings_file))  # noqa: F821

format = "UDZO"
filesystem = "HFS+"

files = [app]
symlinks = {"Applications": "/Applications"}

# dmgbuild picks up background@2x.png next to it and combines both into a HiDPI TIFF.
background = os.path.join(here, "background.png")
if icon_path and os.path.exists(icon_path):
    icon = icon_path

window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 190),
    "Applications": (490, 190),
}
