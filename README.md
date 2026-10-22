# MX Master 3 + MX Keys + Brio setup without Logitech's apps

This folder sets up an MX Master 3, MX Keys and Brio webcam on a new Mac the way they work now: a working scroll wheel, gestures on the mouse's gesture button, custom F1–F4 keys, window shortcuts through Rectangle and macOS, and the webcam's field of view, zoom and pan. Logi Options+ isn't used, because on recent macOS it takes over the scroll wheel and stops it from working. Logi Tune isn't used either, because it overrides the webcam framing whenever an app opens the camera.

## What's in this folder

| File | What it is |
| --- | --- |
| `setup.sh` | Runs the whole setup. Each step can be re-run safely. |
| `config.json` | thumbd's settings: gestures and F1–F4. |
| `thumbd-keyboard.patch` | A small change to thumbd so it also handles the keyboard (the original only handles mice). |
| `uvc-util-logitech-fov.patch` | A small change to uvc-util so it can set the Brio's field of view (the original only handles standard webcam controls). |
| `README.md` | This guide. |

## Before you start

1. **Don't install Logi Options+ or Logi Tune.** If either is already installed, remove it with Logitech's uninstaller and restart.
2. **Pair the mouse and keyboard** over Bluetooth, and plug in the Brio.
3. **Put the keyboard's top row in media mode** (Fn lock off). Press Fn+Esc to toggle it. In this mode F5–F12 handle backlight, playback and volume on their own, and thumbd handles F1–F4.

No admin rights are needed, except to install Apple's Command Line Tools if the Mac doesn't have them. The script offers to install them and asks you to run it again afterward.

## Run the setup

Open Terminal in this folder and run:

```
./setup.sh
```

It runs five steps in order and pauses whenever you need to do something by hand. To run just some of them, name them, for example `./setup.sh brio alias`. The steps are `thumbd`, `rectangle`, `macos`, `brio`, `alias`, plus `check`, which only checks that thumbd is working.

### 1. thumbd

The script downloads thumbd into `~/dev/thumbd` (set `THUMBD_DIR` to use another folder), switches to the version the patch was written for (commit `4cb87d4`), applies the patch, installs `config.json` (backing up any existing one), and builds and installs thumbd. The build takes about a minute.

Then it opens the two permission lists. In **both Input Monitoring and Accessibility**:

1. If a `thumbd` entry is already there, select it and remove it with the minus button.
2. Click the plus button, press Cmd+Shift+G, paste `~/.local/bin/thumbd` (the script copies the full path to your clipboard), and add it.

This is needed after every build, because macOS ties permissions to the exact build. Old entries look switched on but no longer apply.

Finally the script checks thumbd's log. You should see one line saying the mouse is set up and one saying the keyboard is.

### 2. Rectangle

The script installs Rectangle if it isn't there (into Applications, or the Applications folder in your home folder without admin rights) and sets these shortcuts:

| Rectangle action | Shortcut |
| --- | --- |
| First Third | Ctrl+Opt+1 |
| First Two Thirds | Ctrl+Opt+2 |
| First Three Fourths | Ctrl+Opt+3 |
| First Fourth | Ctrl+Opt+4 |

It also turns on **Launch on login** and clears every other shortcut from Rectangle's "Recommended" default set, so only the four above are active — no manual entry needed. When Rectangle opens, just allow its Accessibility permission.

### 3. macOS window shortcuts (by hand)

macOS doesn't offer a reliable way to set these from a script, so the script opens Keyboard settings and waits. Go to **System Settings > Keyboard > Keyboard Shortcuts… > Windows**, turn off every shortcut, then turn on and set only these:

| Section | Shortcut name | Keys |
| --- | --- | --- |
| General | Minimize | Ctrl+Shift+Cmd+= |
| General | Zoom | Ctrl+Shift+Cmd+Return |
| Halves | Tile Left Half | Ctrl+Cmd+Left |
| Halves | Tile Right Half | Ctrl+Cmd+Right |

To change a shortcut, double-click it and press the new keys. Leave **Mission Control** (Ctrl+Up, in the Mission Control section) turned on, since it's the gesture button's tap.

### 4. Brio webcam

The script downloads [uvc-util](https://github.com/jtfrey/uvc-util) into `~/src/uvc-util` (set `UVC_UTIL_DIR` to use another folder), switches to the version the patch was written for (commit `8110da7`), applies the patch, builds it, and installs it to `~/.local/bin/uvc-util`. The build takes a few seconds and needs no permissions.

Then, if the Brio is plugged in, it applies the framing: field of view 78°, zoom 135, pan 7200 and tilt -25200. The camera remembers these between apps, so nothing needs to run in the background. If the Brio isn't plugged in, plug it in and run `./setup.sh brio` again, or use the `brio-frame` alias from the next step.

### 5. Shell aliases

The script adds these to `~/.zshrc`:

```
alias thumbd-restart="~/.local/bin/thumbd check-config && launchctl kickstart -k gui/$(id -u)/local.thumbd"
alias brio-frame='~/.local/bin/uvc-util -V 0x046d:0x085e -s logitech-fov=1 -s zoom-abs=135 -s "pan-tilt-abs={pan=7200,tilt=-25200}"'
```

Open a new Terminal window to use them.

- `thumbd-restart`: run it after editing `~/.config/thumbd/config.json`. Config changes never need a rebuild, so they don't affect permissions.
- `brio-frame`: puts the webcam framing back if it's ever lost, for example after the camera is unplugged or an app changes it.

## How everything is mapped

### Mouse gesture button (thumbd)

| Action | Sends | Does |
| --- | --- | --- |
| Tap | Ctrl+Up | Mission Control |
| Hold and move up | Ctrl+Shift+Cmd+Return | Zoom (macOS) |
| Hold and move down | Ctrl+Shift+Cmd+= | Minimize (macOS) |
| Hold and move left | Ctrl+Cmd+Left | Tile left half (macOS) |
| Hold and move right | Ctrl+Cmd+Right | Tile right half (macOS) |

### Keyboard top row (media mode)

| Key | Does | Handled by |
| --- | --- | --- |
| F1 | Ctrl+Opt+1, First Third | thumbd → Rectangle |
| F2 | Ctrl+Opt+2, First Two Thirds | thumbd → Rectangle |
| F3 | Ctrl+Opt+3, First Three Fourths | thumbd → Rectangle |
| F4 | Ctrl+Opt+4, First Fourth | thumbd → Rectangle |
| F5 / F6 | Keyboard backlight down / up | Keyboard |
| F7 / F8 / F9 | Previous / play-pause / next track | Keyboard |
| F10 / F11 / F12 | Mute / volume down / volume up | Keyboard |

The F1–F4 entries in `config.json` use the MX Keys for Mac's internal key IDs (`0x00C7`, `0x00C8`, `0x00E0`, `0x00E1`). A different Logitech keyboard may use different IDs. Run `~/.local/bin/thumbd list` to see them.

### Brio webcam (uvc-util)

| Control | Value | Range |
| --- | --- | --- |
| `logitech-fov` | `1` (78°) | `0` = 90°, `1` = 78°, `2` = 65° |
| `zoom-abs` | `135` | `100` (no zoom) to `500` |
| `pan-tilt-abs` | `{pan=7200,tilt=-25200}` | Each from `-36000` to `36000` in steps of `3600`. Positive pan moves the image right; positive tilt moves it up. |

Pan and tilt only move the image when zoom is above 100. To try other values, open Photo Booth and change one control at a time:

```
~/.local/bin/uvc-util -V 0x046d:0x085e -s zoom-abs=150
~/.local/bin/uvc-util -V 0x046d:0x085e -s "pan-tilt-abs={pan=3600,tilt=-18000}"
~/.local/bin/uvc-util -V 0x046d:0x085e -g pan-tilt-abs    # read the current value
```

When the framing looks right, update `BRIO_FRAME_CMD` in `setup.sh` and the `brio-frame` line in `~/.zshrc`.

`0x046d:0x085e` is the Brio 4K's vendor and product ID. A different webcam will have a different ID; run `~/.local/bin/uvc-util -d` to list it, and `~/.local/bin/uvc-util -V <id> -c` to see which controls it supports.

## Troubleshooting

**Gestures or F1–F4 stop working.** Check the log with `tail -20 ~/Library/Logs/thumbd.log`. The usual cause is lost permissions (after a rebuild or a macOS update). Remove and re-add `~/.local/bin/thumbd` in Input Monitoring and Accessibility, then run `./setup.sh check`.

**F1–F4 change brightness or open Mission Control.** thumbd isn't running or doesn't have its permissions. When thumbd stops, the keys go back to their normal functions.

**The Mac beeps when a gesture or key fires.** Nothing is set to that shortcut. Check the macOS and Rectangle shortcuts above.

**The scroll wheel stops working.** Something is taking over the wheel, usually Logi Options+. Check that it isn't installed or running.

**Updating thumbd.** The patch only applies cleanly to commit `4cb87d4`. If you pull a newer version, the patch may need updating. Each rebuild also means granting the permissions again.

**The webcam framing resets.** Run `brio-frame`. If it keeps resetting every time an app opens the camera, check that Logi Tune isn't installed or running.

**`logitech-fov` is missing from `uvc-util -c`.** The camera doesn't have the Logitech extension unit the patch looks for (GUID `49E40215-F434-47FE-B158-0E885023E51B`). Zoom and pan still work.

**Build warnings.** Lines like `ld: warning: search path ... not found` and the ad-hoc signature warning are normal.

## Credits

`thumbd-keyboard.patch` modifies [thumbd](https://github.com/fonstack/thumbd) by Carlos Fontes, licensed under MIT. `uvc-util-logitech-fov.patch` modifies [uvc-util](https://github.com/jtfrey/uvc-util) by Jeffrey Frey, licensed under MIT. See [NOTICE](NOTICE) for their license text. The Brio field-of-view control's location (extension unit GUID and selector 5) comes from [OpenLogi issue #1222](https://github.com/AprilNEA/OpenLogi/issues/1222).

## License

The files in this repository are licensed under the MIT License (see [LICENSE](LICENSE)), except for the thumbd excerpts in `thumbd-keyboard.patch` and the uvc-util excerpts in `uvc-util-logitech-fov.patch`, which remain under their own MIT Licenses (see [NOTICE](NOTICE)).
