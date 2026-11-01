import os
import subprocess

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "Cable.icns")
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
window_rect = ((200, 140), (680, 460))
default_view = "icon-view"
icon_size = 104
text_size = 13
icon_locations = {"Cable.app": (174, 244), "Applications": (506, 244)}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False


def create_hook(mount_point, options):
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", os.path.join(mount_point, "Cable.app")],
        check=True,
    )
