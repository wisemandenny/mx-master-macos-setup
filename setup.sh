#!/usr/bin/env bash
# Sets up an MX Master 3 + MX Keys on macOS without Logi Options+:
#   - thumbd (patched): gesture button gestures, and F1–F4 on the keyboard
#   - Mos: scroll wheel settings (smooth scrolling and reverse off)
#   - Rectangle: thirds/fourths shortcuts
#   - macOS window tiling shortcuts (guided, manual)
#   - Logitech Brio webcam framing (FoV, zoom, pan) via a patched uvc-util
#   - the thumbd-restart and brio-frame shell aliases
#
# Usage:
#   ./setup.sh                 run every step
#   ./setup.sh thumbd alias    run only some steps: thumbd, mos, rectangle, macos, brio, alias, check
#
# Every step is safe to run again. No admin rights needed (except for the Command Line
# Tools, if they're not installed yet).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
THUMBD_DIR="${THUMBD_DIR:-$HOME/dev/thumbd}"
THUMBD_REPO="https://github.com/fonstack/thumbd.git"
THUMBD_COMMIT="4cb87d4"   # the keyboard patch was written against this commit
THUMBD_BIN="$HOME/.local/bin/thumbd"
THUMBD_LOG="$HOME/Library/Logs/thumbd.log"
CONFIG_DIR="$HOME/.config/thumbd"
PANE_INPUT="x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
PANE_ACCESS="x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
PANE_KEYBOARD="x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
MOS_SMOOTH=false
MOS_REVERSE=false
MOS_STEP=7.61
MOS_SPEED=1.00
MOS_DURATION=3.99
UVC_UTIL_DIR="${UVC_UTIL_DIR:-$HOME/src/uvc-util}"
UVC_UTIL_REPO="https://github.com/jtfrey/uvc-util.git"
UVC_UTIL_COMMIT="8110da7"   # the FoV patch was written against this commit
UVC_UTIL_BIN="$HOME/.local/bin/uvc-util"
BRIO_ID="0x046d:0x085e"
# FoV: 0 = 90°, 1 = 78°, 2 = 65°. Pan/tilt step is 3600; positive pan = right, positive tilt = up.
BRIO_FRAME_CMD='~/.local/bin/uvc-util -V 0x046d:0x085e -s logitech-fov=1 -s zoom-abs=135 -s "pan-tilt-abs={pan=7200,tilt=-25200}"'

bold()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
info()  { printf '   %s\n' "$*"; }
warn()  { printf '   \033[33m! %s\033[0m\n' "$*"; }
good()  { printf '   \033[32m✓ %s\033[0m\n' "$*"; }
pause() { read -r -p "   $* Press Return to continue… " _; }

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- thumbd

check_tools() {
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "The Command Line Tools (needed to build thumbd and uvc-util) aren't installed. Opening the installer…"
    xcode-select --install || true
    warn "Run ./setup.sh again when the installation has finished."
    exit 1
  fi
}

setup_thumbd() {
  bold "thumbd: source code"
  check_tools
  if [ -d "$THUMBD_DIR/.git" ]; then
    info "Using the existing clone at $THUMBD_DIR"
  else
    mkdir -p "$(dirname "$THUMBD_DIR")"
    git clone --quiet "$THUMBD_REPO" "$THUMBD_DIR"
    info "Cloned into $THUMBD_DIR"
  fi
  cd "$THUMBD_DIR"
  if git apply --reverse --check --ignore-whitespace "$HERE/thumbd-keyboard.patch" 2>/dev/null; then
    good "Keyboard patch already applied"
  else
    if [ -n "$(git status --porcelain)" ]; then
      warn "$THUMBD_DIR has local changes. Commit, stash or delete them, then run again."
      exit 1
    fi
    git fetch --quiet origin
    git -c advice.detachedHead=false checkout --quiet "$THUMBD_COMMIT"
    git apply --ignore-whitespace "$HERE/thumbd-keyboard.patch"
    good "Applied the keyboard patch on commit $THUMBD_COMMIT"
  fi

  bold "thumbd: config"
  mkdir -p "$CONFIG_DIR"
  if [ -f "$CONFIG_DIR/config.json" ] && ! cmp -s "$HERE/config.json" "$CONFIG_DIR/config.json"; then
    local backup="$CONFIG_DIR/config.json.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG_DIR/config.json" "$backup"
    info "Backed up the existing config to $backup"
  fi
  cp "$HERE/config.json" "$CONFIG_DIR/config.json"
  good "Installed $CONFIG_DIR/config.json"

  bold "thumbd: build and install (about a minute)"
  local out; out="$(mktemp)"
  if ! ./scripts/install.sh >"$out" 2>&1; then
    cat "$out"
    warn "The build failed; see the output above."
    exit 1
  fi
  # The "ld: warning: search path … not found" lines are harmless; hide them.
  grep -v "ld: warning: search path" "$out" | sed 's/^/   /' || true
  rm -f "$out"

  bold "thumbd: permissions"
  info "Every new build needs its permissions granted again, even if the switches look on."
  info "In each of the two lists that open:"
  info "  1. If there's a 'thumbd' entry, select it and remove it with the − button."
  info "  2. Click +, press Cmd+Shift+G, paste the path (already on your clipboard), and add it:"
  info "     $THUMBD_BIN"
  printf '%s' "$THUMBD_BIN" | pbcopy
  open "$PANE_INPUT"
  pause "Grant Input Monitoring."
  printf '%s' "$THUMBD_BIN" | pbcopy
  open "$PANE_ACCESS"
  pause "Grant Accessibility."

  check_thumbd
}

check_thumbd() {
  bold "thumbd: check"
  info "Waiting for thumbd to pick up the permissions…"
  sleep 15
  local recent; recent="$(tail -n 40 "$THUMBD_LOG" 2>/dev/null || true)"
  printf '%s\n' "$recent" | tail -n 8 | sed 's/^/   /'
  echo
  if printf '%s' "$recent" | grep -q "✓ MX Master"; then
    good "Mouse gestures are active"
  else
    warn "The mouse isn't set up yet. Check the permissions, turn the mouse off and on, then run: ./setup.sh check"
  fi
  if printf '%s' "$recent" | grep -q "✓ MX Keys"; then
    good "Keyboard F1–F4 are active"
  else
    warn "The keyboard isn't set up yet. Make sure it's connected, then run: ./setup.sh check"
  fi
}

# ---------------------------------------------------------------- Mos

setup_mos() {
  bold "Mos: app"
  local app=""
  for d in /Applications "$HOME/Applications"; do
    if [ -d "$d/Mos.app" ]; then app="$d/Mos.app"; fi
  done
  if [ -n "$app" ]; then
    good "Already installed: $app"
  else
    local dest="/Applications"
    [ -w "$dest" ] || dest="$HOME/Applications"
    mkdir -p "$dest"
    local url
    url="$(curl -fsSL https://api.github.com/repos/Caldis/Mos/releases/latest \
      | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -n 1 | cut -d'"' -f4)"
    if [ -z "$url" ]; then
      warn "Couldn't find the Mos download. Install it from mos.caldis.me, then run: ./setup.sh mos"
      exit 1
    fi
    local tmp; tmp="$(mktemp -d)"
    info "Downloading $url"
    curl -fsSL -o "$tmp/Mos.zip" "$url"
    ditto -x -k "$tmp/Mos.zip" "$tmp/unzipped"
    cp -R "$(find "$tmp/unzipped" -maxdepth 2 -name Mos.app -type d | head -n 1)" "$dest/"
    rm -rf "$tmp"
    app="$dest/Mos.app"
    good "Installed $app"
  fi

  bold "Mos: scroll settings"
  # Without optionsExist, Mos's first launch saves its defaults over anything written here.
  if ! defaults read com.caldis.Mos optionsExist >/dev/null 2>&1; then
    info "Opening Mos once so it creates its settings…"
    open "$app"
    for _ in $(seq 1 20); do
      defaults read com.caldis.Mos optionsExist >/dev/null 2>&1 && break
      sleep 1
    done
  fi
  if pgrep -xq Mos; then
    osascript -e 'tell application "Mos" to quit' >/dev/null 2>&1 || true
    sleep 2
  fi
  defaults write com.caldis.Mos optionsExist -string optionsExist
  defaults write com.caldis.Mos smooth   -bool  "$MOS_SMOOTH"
  defaults write com.caldis.Mos reverse  -bool  "$MOS_REVERSE"
  defaults write com.caldis.Mos step     -float "$MOS_STEP"
  defaults write com.caldis.Mos speed    -float "$MOS_SPEED"
  defaults write com.caldis.Mos duration -float "$MOS_DURATION"
  # Once optionsExist is set, Mos reads a missing hotkey as "none"; this clears the Option/Shift/Cmd defaults.
  for key in dash toggle block; do
    defaults delete com.caldis.Mos "$key" >/dev/null 2>&1 || true
  done
  good "Smooth scrolling off, reverse off, no scroll hotkeys, step $MOS_STEP, speed $MOS_SPEED, duration $MOS_DURATION"
  open "$app"
  info "Mos is open. If it asks, allow its Accessibility permission."
  info "To check the settings, click the Mos menu bar icon > Preferences > Scrolling."
  pause "When Mos is set up,"
}

# ---------------------------------------------------------------- Rectangle

setup_rectangle() {
  bold "Rectangle: app"
  local app=""
  for d in /Applications "$HOME/Applications"; do
    if [ -d "$d/Rectangle.app" ]; then app="$d/Rectangle.app"; fi
  done
  if [ -n "$app" ]; then
    good "Already installed: $app"
  else
    local dest="/Applications"
    [ -w "$dest" ] || dest="$HOME/Applications"
    mkdir -p "$dest"
    local url
    url="$(curl -fsSL https://api.github.com/repos/rxhanson/Rectangle/releases/latest \
      | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -n 1 | cut -d'"' -f4)"
    if [ -z "$url" ]; then
      warn "Couldn't find the Rectangle download. Install it from rectangleapp.com, then run: ./setup.sh rectangle"
      exit 1
    fi
    local tmp; tmp="$(mktemp -d)"
    info "Downloading $url"
    curl -fsSL -o "$tmp/Rectangle.dmg" "$url"
    hdiutil attach -quiet -nobrowse -mountpoint "$tmp/mnt" "$tmp/Rectangle.dmg"
    cp -R "$tmp/mnt/Rectangle.app" "$dest/"
    hdiutil detach -quiet "$tmp/mnt"
    rm -rf "$tmp"
    app="$dest/Rectangle.app"
    good "Installed $app"
  fi

  bold "Rectangle: shortcuts"
  if pgrep -xq Rectangle; then
    osascript -e 'tell application "Rectangle" to quit' >/dev/null 2>&1 || true
    sleep 2
  fi
  # Key codes: 1=18, 2=19, 3=20, 4=21. Modifier flags: Control (1<<18) + Option (1<<19).
  local ctrl_opt=786432
  # "Recommended" preset (vs. Spectacle's); setting it before first launch skips the picker.
  defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
  defaults write com.knollsoft.Rectangle launchOnLogin -bool true
  defaults write com.knollsoft.Rectangle firstThird        -dict keyCode -int 18 modifierFlags -int $ctrl_opt
  defaults write com.knollsoft.Rectangle firstTwoThirds    -dict keyCode -int 19 modifierFlags -int $ctrl_opt
  defaults write com.knollsoft.Rectangle firstThreeFourths -dict keyCode -int 20 modifierFlags -int $ctrl_opt
  defaults write com.knollsoft.Rectangle firstFourth       -dict keyCode -int 21 modifierFlags -int $ctrl_opt
  # Every other action the "Recommended" preset binds by default. An empty dict is Rectangle's
  # own "no shortcut" value (confirmed by clearing one by hand in the app and reading it back).
  for action in leftHalf rightHalf maximize maximizeHeight previousDisplay nextDisplay \
                larger smaller bottomHalf topHalf center bottomLeft bottomRight topLeft topRight \
                restore centerThird lastTwoThirds lastThird secondFourth thirdFourth lastFourth; do
    defaults write com.knollsoft.Rectangle "$action" -dict
  done
  good "First Third ⌃⌥1, First Two Thirds ⌃⌥2, First Three Fourths ⌃⌥3, First Fourth ⌃⌥4"
  good "Every other default shortcut cleared, and Launch on login turned on"
  open "$app"
  info "Rectangle is open. If it asks, allow its Accessibility permission."
  pause "When Rectangle is set up,"
}

# ---------------------------------------------------------------- macOS tiling

setup_macos() {
  bold "macOS window shortcuts (manual)"
  info "macOS doesn't offer a reliable way to set these from a script, so set them by hand."
  info "In System Settings > Keyboard > Keyboard Shortcuts… > Windows, turn off every shortcut except:"
  info ""
  info "  General > Minimize         ⌃⇧⌘=        (Ctrl+Shift+Cmd+=)"
  info "  General > Zoom             ⌃⇧⌘Return   (Ctrl+Shift+Cmd+Return)"
  info "  Halves  > Tile Left Half   ⌃⌘←         (Ctrl+Cmd+Left)"
  info "  Halves  > Tile Right Half  ⌃⌘→         (Ctrl+Cmd+Right)"
  info ""
  info "To change one, double-click its current shortcut and press the new keys."
  info "Leave Mission Control (⌃↑) on: it's the gesture button's tap."
  open "$PANE_KEYBOARD"
  pause "When the shortcuts are set,"
}

# ---------------------------------------------------------------- Brio webcam

setup_brio() {
  bold "Brio: uvc-util source code"
  check_tools
  if [ -d "$UVC_UTIL_DIR/.git" ]; then
    info "Using the existing clone at $UVC_UTIL_DIR"
  else
    mkdir -p "$(dirname "$UVC_UTIL_DIR")"
    git clone --quiet "$UVC_UTIL_REPO" "$UVC_UTIL_DIR"
    info "Cloned into $UVC_UTIL_DIR"
  fi
  cd "$UVC_UTIL_DIR"
  if git apply --reverse --check "$HERE/uvc-util-logitech-fov.patch" 2>/dev/null; then
    good "FoV patch already applied"
  else
    if [ -n "$(git status --porcelain)" ]; then
      warn "$UVC_UTIL_DIR has local changes. Commit, stash or delete them, then run again."
      exit 1
    fi
    git fetch --quiet origin
    git -c advice.detachedHead=false checkout --quiet "$UVC_UTIL_COMMIT"
    git apply "$HERE/uvc-util-logitech-fov.patch"
    good "Applied the FoV patch on commit $UVC_UTIL_COMMIT"
  fi

  bold "Brio: build and install uvc-util"
  local out; out="$(mktemp)"
  if ! (cd src && gcc -o uvc-util -framework IOKit -framework Foundation \
          uvc-util.m UVCController.m UVCType.m UVCValue.m) >"$out" 2>&1; then
    cat "$out"
    warn "The build failed; see the output above."
    exit 1
  fi
  rm -f "$out"
  mkdir -p "$(dirname "$UVC_UTIL_BIN")"
  cp src/uvc-util "$UVC_UTIL_BIN"
  good "Installed $UVC_UTIL_BIN"

  bold "Brio: framing"
  if "$UVC_UTIL_BIN" -V "$BRIO_ID" -g zoom-abs >/dev/null 2>&1; then
    eval "$BRIO_FRAME_CMD"
    "$UVC_UTIL_BIN" -V "$BRIO_ID" -g logitech-fov -g zoom-abs -g pan-tilt-abs | sed 's/^/   /'
    good "Applied FoV 78°, zoom 135 and pan/tilt; the camera keeps them between apps"
  else
    warn "No Brio found. Plug it in, then run: ./setup.sh brio"
  fi
}

# ---------------------------------------------------------------- alias

setup_alias() {
  bold "Shell alias"
  local rc="$HOME/.zshrc"
  if grep -q 'alias thumbd-restart=' "$rc" 2>/dev/null; then
    good "thumbd-restart is already in $rc"
  else
    cat >> "$rc" <<'EOF'

# Restart thumbd after editing ~/.config/thumbd/config.json
alias thumbd-restart="~/.local/bin/thumbd check-config && launchctl kickstart -k gui/$(id -u)/local.thumbd"
EOF
    good "Added thumbd-restart to $rc (open a new Terminal window to use it)"
  fi
  if grep -q 'alias brio-frame=' "$rc" 2>/dev/null; then
    good "brio-frame is already in $rc"
  else
    printf '\n# Re-apply the Brio webcam framing (FoV 78°, zoom, pan/tilt)\nalias brio-frame='\''%s'\''\n' "$BRIO_FRAME_CMD" >> "$rc"
    good "Added brio-frame to $rc (open a new Terminal window to use it)"
  fi
}

# ---------------------------------------------------------------- main

if [ $# -eq 0 ]; then set -- thumbd mos rectangle macos brio alias; fi
for step in "$@"; do
  case "$step" in
    thumbd)    setup_thumbd ;;
    mos)       setup_mos ;;
    rectangle) setup_rectangle ;;
    macos)     setup_macos ;;
    brio)      setup_brio ;;
    alias)     setup_alias ;;
    check)     check_thumbd ;;
    -h|--help) usage; exit 0 ;;
    *)         warn "Unknown step: $step"; usage; exit 1 ;;
  esac
done

bold "Done"
info "Keyboard: keep the top row in media mode (Fn lock off, toggled with Fn+Esc)."
info "Don't install Logi Options+: it breaks the scroll wheel on this setup."
info "Don't install Logi Tune: it overrides the Brio framing set here."
