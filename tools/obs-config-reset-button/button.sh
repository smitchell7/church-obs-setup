#!/usr/bin/env bash
# The "OBS Configuration Reset" button (app menu and dock, Ubuntu); its icon is icon.svg next to this file.
# One click downloads the latest version of this
# repository (git, fast-forward only) and runs tools/obs-config-update.py, which puts the scene collections and the
# OBS configuration back to the repo's version and keeps the cameras, microphone and NDI sources picked in OBS.
# A window asks which scene collection OBS should open on, with the current one selected.
# Runs as the logged-in user: no password and no terminal. It never installs or updates software; that is
# sudo ./setup-obs-flatpak.sh. Windows of progress and results are zenity dialogs; the output of the last run is
# in ~/.cache/church-obs-config-update.log.
set -uo pipefail

# Everything runs inside main(): bash reads a script while it runs it, and the download can replace this file.
main() {
  local TITLE="OBS Configuration Reset" REPO_DIR LOG pid choice list current
  REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)   # tools/obs-config-reset-button/ -> the repo
  LOG="${XDG_CACHE_HOME:-$HOME/.cache}/church-obs-config-update.log"
  mkdir -p "$(dirname "$LOG")"

  # The dock starts apps on a single click, so a double click starts this twice: the second one just stops.
  exec 9>"${XDG_RUNTIME_DIR:-/tmp}/church-obs-config-update.lock"
  flock -n 9 || return

  if pgrep -u "$(id -u)" -f com.obsproject.Studio >/dev/null; then
    zenity --warning --title="$TITLE" --width=420 \
      --text="OBS is open. Close OBS, then press OBS Configuration Reset again.\n\n(OBS saves its settings when it closes, which would undo the update.)"
    return
  fi

  # 1. Download the latest version (its own folder, the branch it is on). This needs no sudo: the setup script
  #    makes ~/church-obs-setup belong to the user.
  : > "$LOG"
  if ! git -C "$REPO_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    echo "$REPO_DIR is not on a branch that follows GitHub, so updates cannot be downloaded." >>"$LOG"
  elif ! git -C "$REPO_DIR" fetch --quiet origin >>"$LOG" 2>&1; then
    echo "Could not download the latest version (no internet?). Using the version already here." >>"$LOG"
  elif ! git -C "$REPO_DIR" merge --ff-only --quiet '@{u}' >>"$LOG" 2>&1; then
    echo "$REPO_DIR has local changes, so the latest version could not be applied. Using the version already here." >>"$LOG"
  fi
  echo "Version: $(git -C "$REPO_DIR" log -1 --format='%h %s (%cs)' 2>/dev/null)" >>"$LOG"

  # 2. Which scene collection OBS opens on: the same list and order as the terminal menu, current one selected.
  list=$(python3 -I "$REPO_DIR/tools/obs-config-update.py" --list 2>>"$LOG") || {
    zenity --error --title="$TITLE" --width=420 --text="Could not read the scene collections. Details are shown next."
    zenity --text-info --title="$TITLE: details" --width=800 --height=500 --filename="$LOG"
    return
  }
  local rows=() current_name= prompt
  while IFS=$'\t' read -r folder name mark; do
    [ -n "$folder" ] || continue
    if [ "$mark" = current ]; then rows+=(TRUE "$name" "$folder"); current=$folder; current_name=$name; else rows+=(FALSE "$name" "$folder"); fi
  done <<<"$list"
  if [ -n "$current_name" ]; then
    prompt="Which scene collection should OBS open on?\n\nThe one OBS is using now, <b>${current_name//&/&amp;}</b>, is already selected: press OK to keep it."
  else
    prompt="Which scene collection should OBS open on?\n\nPick one of these, then press OK."
  fi
  # Tall enough to show every collection without scrolling: room for the message and buttons, plus a row each.
  local height=$((300 + 40 * ${#rows[@]} / 3))
  choice=
  while [ -z "$choice" ]; do
    choice=$(zenity --list --radiolist --title="$TITLE" --width=600 --height="$height" \
        --text="$prompt" \
        --column="" --column="Scene collection" --column="Folder" --hide-column=3 --print-column=3 \
        "${rows[@]}") || return   # Cancel: nothing is changed
    choice=${choice:-${current:-}}   # OK with nothing ticked keeps the current one, if there is one
  done

  # 3. The update itself, in the background so closing the progress window does not stop it halfway.
  ( python3 -I "$REPO_DIR/tools/obs-config-update.py" ${choice:+--default "$choice"} </dev/null >>"$LOG" 2>&1
    echo "EXIT=$?" >>"$LOG" ) &
  pid=$!
  (
    while kill -0 "$pid" 2>/dev/null; do
      echo "# $(grep -v '^EXIT=' "$LOG" | tail -n 1 | tr -d '<>&' | cut -c1-100)"
      sleep 1
    done
    echo 100
  ) | zenity --progress --pulsate --auto-close --no-cancel --width=620 --title="$TITLE" \
      --text="Updating the OBS configuration…"
  wait "$pid"

  if [ "$(sed -n 's/^EXIT=//p' "$LOG" | tail -n 1)" = 0 ]; then
    local opens
    opens=$(sed -n "s/^OBS will open with the '\(.*\)' scene collection\.$/\1/p" "$LOG" | tail -n 1)
    zenity --info --title="$TITLE" --width=400 \
      --text="Done. The OBS configuration is up to date.\n\nOBS will open with: ${opens:-the same scene collection as before}"
  else
    zenity --error --title="$TITLE" --width=440 \
      --text="The update did not finish. The details are shown next: take a photo of them for whoever looks after the broadcast computers."
    zenity --text-info --title="$TITLE: details" --width=800 --height=500 --filename="$LOG"
  fi
}

main "$@"
exit
