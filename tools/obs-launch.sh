#!/usr/bin/env bash
# Start OBS and maximize its main window. Only used on computers where OBS runs under X11 (a Flatpak override with
# sockets=x11;!wayland / QT_QPA_PLATFORM=xcb). The Independence building runs OBS under X11 so that OBS's
# full-screen projector works there, which it needs.
# Why this script: on those computers, the first time OBS opens after a computer restart its window doesn't open
# maximized, although OBS saved it maximized (seen on the three-screen Independence computer;
# harmanmj/church-obs-setup#4). Added untested on that computer, to be confirmed with the next update there, and
# adjusted if it doesn't help.
# tools/set-obs-launcher.py points the OBS app-menu entry (and the dock icon) at this script on those computers only.
# OBS opens where it was, on the screen it was on; this only adds "maximized", like double-clicking the title bar.
# Arguments are passed on to OBS (e.g. --startvirtualcam).
set -u

flatpak run --branch=stable --arch=x86_64 --command=obs com.obsproject.Studio "$@" &
pid=$!

if command -v wmctrl >/dev/null; then
  # Wait (up to about 30 seconds) for the main window, whose title starts "OBS <version>", then maximize it.
  for _ in $(seq 1 60); do
    win=$(wmctrl -lx 2>/dev/null | awk '{cls = tolower($3); t = ""; for (i = 5; i <= NF; i++) t = t " " $i}
                                        cls ~ /obs/ && t ~ /^ OBS [0-9]/ {print $1; exit}')
    if [ -n "$win" ]; then
      sleep 1   # let OBS finish restoring its own geometry first
      wmctrl -i -r "$win" -b add,maximized_vert,maximized_horz
      break
    fi
    kill -0 "$pid" 2>/dev/null || break   # OBS closed (or failed to start)
    sleep 0.5
  done
fi

wait "$pid"
