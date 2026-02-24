-- ~/.hammerspoon/skhd_hud_settings.lua
-- Optional HUD styling overrides for skhd_hud.lua.
return {
  -- Path for saved HUD anchor/position state.
  -- Relative path is resolved inside ~/.hammerspoon.
  position_store = "skhd_hud_state.lua",

  colors = {
    -- Ordered palette for modal blocks (depth grows through this list).
    palette = {
      "#F2D5CF",
      "#EEBEBE",
      "#F4B8E4",
      "#CA9EE6",
      "#E78284",
      "#EA999C",
      "#EF9F76",
      "#E5C890",
      "#A6D189",
      "#81C8BE",
      "#99D1DB",
      "#85C1DC",
      "#8CAAEE",
      "#BABBF1",
    },
    badge = "#E5C890",
    text = "#232634",
  },

  alpha = {
    -- Common block alpha when modal hints are visible.
    blocks = 0.85,
    -- Badge alpha while inside modal stacks.
    badge = 0.85,
    -- Badge alpha when badge is the only element on screen.
    badge_idle = 0.72,
    -- Vertical separator alpha inside hint blocks.
    separator = 0.45,
  },

  typography = {
    -- Set to nil/"" to keep macOS default regular font.
    font = nil,
    bold_font = "Helvetica-Bold",
    -- Badge can use its own font; falls back to bold_font.
    badge_font = "Helvetica-Bold",

    font_size = 14,
    key_hint_size = 18,
    mode_size = 17,
    -- Separate size for the space badge symbol.
    badge_size = 15,
    -- Positive value moves the badge symbol down, negative moves it up.
    badge_y_offset = 1,
  },
}
