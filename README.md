# mac-which-key HUD (Hammerspoon + skhd.zig + yabai)

Layered modal keymap for `yabai` with HUD hints from Hammerspoon.

## What Changed In This Revision

- Unified exit strategy for all modal layers:
  - `Esc` always exits directly to `default` (`hud.sh reset`).
  - `Backspace` always returns one menu level up (`hud.sh pop`).
- HUD key hints in `[...]` are rendered larger and bold, including letters in the middle of words.
- Space badge refresh is debounced to reduce lag when switching spaces.
- `wm_stack` hints were rewritten to explain behavior in plain language.

## Repository Layout

- `./skhdrc`
  - layered modal map (`default -> wm -> submodes`)
- `./hud.sh`
  - bridge script from `skhd` to Hammerspoon module (`push/pop/reset/show/hide`)
- `./skhd_hud.lua`
  - HUD renderer, mode stack visuals, space badge, drag behavior, persisted position
- `./init.lua`
  - minimal Hammerspoon entrypoint (`require("skhd_hud").show()`)

## Requirements

- macOS
- Hammerspoon with Accessibility permission
- Hammerspoon CLI (`hs`) installed from app preferences
- `yabai` installed and running
- `skhd.zig` installed (binary commonly named `skhd`)

## Installation

```bash
mkdir -p "$HOME/.config/skhd" "$HOME/.hammerspoon"
cp ./hud.sh "$HOME/.config/skhd/hud.sh"
cp ./skhdrc "$HOME/.config/skhd/skhdrc"
cp ./skhd_hud.lua "$HOME/.hammerspoon/skhd_hud.lua"
chmod +x "$HOME/.config/skhd/hud.sh"
ln -sf "$HOME/.config/skhd/skhdrc" "$HOME/.skhdrc"
```

Ensure `~/.hammerspoon/init.lua` contains:

```lua
local skhdHud = require("skhd_hud")
skhdHud.show()
```

Reload daemons:

```bash
yabai --restart-service
skhd --restart-service
hs -c "hs.reload()"
```

## Global Navigation Model (`skhdrc`)

- Leader entry:
  - `fn+w` enters `wm`
  - `fn+x` enters `app` launcher
- Always available in `default`:
  - `fn+h/j/k/l` focus window west/south/north/east
  - `fn+p/n` focus previous/next space
- Exit rules for all modes:
  - `Esc`: hard exit to `default`
  - `Backspace`: one level up
  - `q`: hard exit to `default`

## Mode Tree

- `wm` (root)
  - `r` -> `wm_resize`
  - `s` -> `wm_swap`
  - `m` -> `wm_move`
  - `t` -> `wm_toggle`
  - `p` -> `wm_space`
  - `d` -> `wm_display`
  - `a` -> `wm_stack`

- `wm_space`
  - `h/l/p/n`: focus prev/next space
  - `j/k`: move current space prev/next
  - `c`: create space
  - `x`: destroy current space
  - `1..9`: focus exact space
  - `y` -> `wm_layout`
  - `g` -> `wm_gap`

- `wm_layout`
  - `b`: `bsp`
  - `s`: `stack`
  - `f`: `float`
  - `h/l`: mirror X/Y
  - `j/k`: rotate 270/90
  - `e`: equalize
  - `a`: balance

- `wm_gap`
  - `h/l`: gap -/+ 4
  - `j/k`: padding -/+ 4
  - `p`: toggle padding
  - `n`: toggle gap
  - `0`: reset gap and padding to 0

- `wm_resize`
  - `h/l/j/k`: resize window in direction
  - `n/p`: ratio +/-
  - `0`: equalize space

- `wm_swap`
  - `h/l/j/k`: directional swap
  - `n/p`: swap next/prev
  - `r`: swap with recent

- `wm_move`
  - `h/l/j/k`: warp in tree direction
  - `n/p`: send to next/prev space and follow
  - `1..9`: send to exact space and follow

- `wm_display`
  - `h/l/p/n`: focus prev/next display
  - `j/k`: send window prev/next display and follow
  - `1..4`: focus exact display

- `wm_toggle`
  - `f`: float
  - `z`: zoom parent
  - `x`: zoom fullscreen
  - `w`: windowed fullscreen
  - `n`: native fullscreen
  - `s`: split toggle
  - `y`: sticky
  - `p`: picture-in-picture
  - `o`: shadow
  - `e`: expose

- `wm_stack`
  - `h/l/j/k`: attach focused window into stack relative to neighbor in that direction
  - `i`: insert focused window into current stack
  - `n/p`: focus next/prev window inside stack
  - `f/o/r`: focus first/last/recent window in stack

- `app` (launcher on `fn+x`)
  - `g`: Ghostty
  - `c`: Chrome
  - `b`: Zen Browser
  - `e`: Emacs

## Stack Behavior (Detailed)

`yabai` stack mode is a pile of windows in one tile position (similar to tabbing without native tabs).

- How to create a stack quickly:
  1. Focus window A.
  2. Focus window B.
  3. `fn+w`, then `a` (stack mode), then direction key (`h/j/k/l`) toward A.
  4. B joins A's tile as a stack member.

- How to navigate a stack:
  - `n/p`: next/prev member
  - `f`: first member
  - `o`: last member
  - `r`: recent member

- When `i` is useful:
  - Use `i` when you are already inside a stack context and want to insert current window without directional targeting.

## Practical Scenarios

1. Fast workspace cleanup after opening many apps
- `fn+w` -> `p` -> `g` (gap mode) -> `0` to normalize spacing.
- Backspace to return to `wm_space`, then `y` for layout if needed.

2. Move noisy app to another space and follow it
- Focus app window.
- `fn+w` -> `m` -> `n` (or number `1..9`).
- You land on destination space with that window focused.

3. Build “tab-like” stack for related tools
- Open terminal + editor + browser.
- Focus one window, then `fn+w` -> `a`, use `h/j/k/l` to attach others.
- Cycle with `n/p`, jump with `f/o/r`.

4. Re-layout current space after manual chaos
- `fn+w` -> `p` -> `y`.
- Use `b/s/f` to choose layout type.
- Finish with `e` (equalize) or `a` (balance).

5. Move a window to another monitor while following focus
- Focus source window.
- `fn+w` -> `d` -> `j` or `k`.
- Window jumps to previous/next display and focus follows.

6. Temporary media overlay and always-on-top style behavior
- Focus media window.
- `fn+w` -> `t` -> `p` for PiP and optionally `y` for sticky.

## HUD Notes

- Badge always shows focused space index.
- Drag HUD with `Cmd + left mouse`.
- Position is saved to `~/.hammerspoon/skhd_hud_position.lua`.
- Key hints wrapped in `[...]` are rendered larger and bold to improve scan speed.

## Troubleshooting

- `hs` CLI not found
  - install from Hammerspoon preferences
- Keybinds do not react
  - ensure `~/.skhdrc` links to `~/.config/skhd/skhdrc`
  - restart `skhd`
- HUD not updating
  - ensure `~/.hammerspoon/skhd_hud.lua` exists
  - run `hs -c "hs.reload()"`
