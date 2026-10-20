#!/usr/bin/env bash
# Sets up an MX Master 3 + MX Keys on macOS without Logi Options+:
#   - thumbd (patched): gesture button gestures, and F1–F4 on the keyboard
#   - Rectangle: thirds/fourths shortcuts
#   - macOS window tiling shortcuts (guided, manual)
#   - the thumbd-restart shell alias
#
# Usage:
#   ./setup.sh                 run every step
#   ./setup.sh thumbd alias    run only some steps: thumbd, rectangle, macos, alias, check
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

bold()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
info()  { printf '   %s\n' "$*"; }
warn()  { printf '   \033[33m! %s\033[0m\n' "$*"; }
good()  { printf '   \033[32m✓ %s\033[0m\n' "$*"; }
pause() { read -r -p "   $* Press Return to continue… " _; }

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------- thumbd

check_tools() {
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "The Command Line Tools (needed to build thumbd) aren't installed. Opening the installer…"
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
}

# ---------------------------------------------------------------- main

if [ $# -eq 0 ]; then set -- thumbd rectangle macos alias; fi
for step in "$@"; do
  case "$step" in
    thumbd)    setup_thumbd ;;
    rectangle) setup_rectangle ;;
    macos)     setup_macos ;;
    alias)     setup_alias ;;
    check)     check_thumbd ;;
    -h|--help) usage; exit 0 ;;
    *)         warn "Unknown step: $step"; usage; exit 1 ;;
  esac
done

bold "Done"
info "Keyboard: keep the top row in media mode (Fn lock off, toggled with Fn+Esc)."
info "Don't install Logi Options+: it breaks the scroll wheel on this setup."
