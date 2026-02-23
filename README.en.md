# SKHD HUD Overlay (Hammerspoon + skhd)

A minimal macOS HUD overlay that shows the current `skhd` mode stack and available keybindings.

Russian version: `README.ru.md`.

## Features

- `push/pop/reset/show/hide` commands via `~/.config/skhd/hud.sh`
- HUD rendering with Hammerspoon `hs.canvas`, no JSON and no polling
- Background color changes by mode-stack depth
- 150ms fade in/out
- Drag HUD with mouse while holding `Cmd`
- Position persistence across Hammerspoon reloads

## Requirements

- macOS
- `Hammerspoon` installed and running
- `skhd` installed
- `hs` CLI installed (Hammerspoon -> Preferences -> Install Command Line Tool)

## Files

- `~/.config/skhd/hud.sh`
- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/skhd_hud.lua`
- `~/.hammerspoon/skhd_hud_position.lua` (auto-generated after dragging)

## Installation

1. Copy files to your home config directories:

```bash
mkdir -p ~/.config/skhd ~/.hammerspoon
cp .config/skhd/hud.sh ~/.config/skhd/hud.sh
cp .hammerspoon/skhd_hud.lua ~/.hammerspoon/skhd_hud.lua
```

2. Make the bridge script executable:

```bash
chmod +x ~/.config/skhd/hud.sh
```

3. Load the module in `~/.hammerspoon/init.lua`:

```lua
require("skhd_hud")
```

If you already have an `init.lua`, just add `require("skhd_hud")` once.

4. Reload Hammerspoon (`hs.reload()` in Console or menu: Reload Config).

## skhd Configuration

Example for `~/.skhdrc`:

```sh
window < r ; window_resize : ~/.config/skhd/hud.sh push window_resize "h(smaller)|l(larger)|k(taller)|j(shorter)"
window_resize < escape ; window : ~/.config/skhd/hud.sh pop
window < escape ; default : ~/.config/skhd/hud.sh reset
```

You can also test manually:

```bash
~/.config/skhd/hud.sh push window "s|r"
~/.config/skhd/hud.sh push swap "h|j|k|l"
~/.config/skhd/hud.sh pop
~/.config/skhd/hud.sh reset
~/.config/skhd/hud.sh show
~/.config/skhd/hud.sh hide
```

## Usage

- `push <mode> "<options>"`: append mode level and show/update HUD
- `pop`: remove top level
- `reset`: clear stack and hide HUD
- `show` / `hide`: force show/hide without changing the stack
  - if the stack is empty, `show` displays a `SKHD HUD` placeholder label

Label format: `MODE1 → MODE2 → ... → options`.

## Dragging and Position

- Hold `Cmd` and drag the HUD with the mouse.
- Position is written on mouse-up to `~/.hammerspoon/skhd_hud_position.lua`.
- Saved position is restored after `hs.reload()`.

## Quick Validation

1. Run `~/.config/skhd/hud.sh push window "s|r"` and confirm HUD appears.
2. Run `~/.config/skhd/hud.sh push swap "h|j|k|l"` and confirm label/color update.
3. Run `~/.config/skhd/hud.sh pop` and confirm stack goes one level back.
4. Run `~/.config/skhd/hud.sh reset` and confirm fade-out/hide.
5. Run `~/.config/skhd/hud.sh show` after `reset` and confirm a `SKHD HUD` placeholder is visible.

## Troubleshooting

- `hs: command not found`: install the Hammerspoon CLI from Preferences.
- HUD not visible: verify `require("skhd_hud")` exists in `~/.hammerspoon/init.lua`, then reload config.
- `skhd` commands not triggering: verify absolute path to `hud.sh` and executable permission (`chmod +x`).
