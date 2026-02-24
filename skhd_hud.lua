local M = {}

local HUD_HEIGHT = 44
local MIN_WIDTH = 120
local FADE_DURATION = 0.150
local DEFAULT_TOP_MARGIN = 16
local EMPTY_SHOW_LABEL = "SKHD HUD"

local BLOCK_GAP = 8
local BLOCK_CORNER_RADIUS = 12
local BADGE_CORNER_RADIUS = 22
local BLOCK_PADDING_X = 14
local BADGE_PADDING_X = 12
local SEPARATOR_GAP_X = 10
local SEPARATOR_WIDTH = 1
local FALLBACK_GLYPH_WIDTH = 9
local FALLBACK_BOLD_GLYPH_WIDTH = 10
local DRAG_REQUIRES_CMD = true
local SPACE_REFRESH_DEBOUNCE = 0.06
local SPACE_POLL_INTERVAL = 1.0

local DEFAULT_FONT_SIZE = 14
local DEFAULT_KEY_HINT_FONT_SIZE = 18
local DEFAULT_MODE_FONT_SIZE = 17
local DEFAULT_BADGE_FONT_SIZE = 15
local DEFAULT_BADGE_TEXT_Y_OFFSET = 1
local DEFAULT_BLOCK_ALPHA = 0.85
local DEFAULT_BADGE_ALPHA = 0.85
local DEFAULT_IDLE_BADGE_ALPHA = 0.72
local DEFAULT_SEPARATOR_ALPHA = 0.45

local DEFAULT_POSITION_STORE_FILE = "skhd_hud_state.lua"
local LEGACY_POSITION_FILE = hs.configdir .. "/skhd_hud_position.lua"
local SETTINGS_FILE = hs.configdir .. "/skhd_hud_settings.lua"
local LEGACY_SETTINGS_FILE = hs.configdir .. "/skhd_hud_config.lua"

-- Catppuccin Frappe accents (non-gray), configurable palette.
local DEFAULT_BLOCK_PALETTE = {
  "#F2D5CF", -- rosewater
  "#EEBEBE", -- flamingo
  "#F4B8E4", -- pink
  "#CA9EE6", -- mauve
  "#E78284", -- red
  "#EA999C", -- maroon
  "#EF9F76", -- peach
  "#E5C890", -- yellow
  "#A6D189", -- green
  "#81C8BE", -- teal
  "#99D1DB", -- sky
  "#85C1DC", -- sapphire
  "#8CAAEE", -- blue
  "#BABBF1", -- lavender
}
local DEFAULT_BADGE_COLOR_HEX = "#E5C890" -- yellow (higher contrast, Catppuccin Frappe)
local DEFAULT_TEXT_COLOR_HEX = "#232634" -- crust

local FONT_SIZE = DEFAULT_FONT_SIZE
local KEY_HINT_FONT_SIZE = DEFAULT_KEY_HINT_FONT_SIZE
local MODE_FONT_SIZE = DEFAULT_MODE_FONT_SIZE
local BADGE_FONT_SIZE = DEFAULT_BADGE_FONT_SIZE
local BADGE_TEXT_Y_OFFSET = DEFAULT_BADGE_TEXT_Y_OFFSET
local BLOCK_ALPHA = DEFAULT_BLOCK_ALPHA
local BADGE_ALPHA = DEFAULT_BADGE_ALPHA
local IDLE_BADGE_ALPHA = DEFAULT_IDLE_BADGE_ALPHA
local SEPARATOR_ALPHA = DEFAULT_SEPARATOR_ALPHA
local BADGE_COLOR_HEX = DEFAULT_BADGE_COLOR_HEX

local BLOCK_PALETTE = {}
for _, color in ipairs(DEFAULT_BLOCK_PALETTE) do
  BLOCK_PALETTE[#BLOCK_PALETTE + 1] = color
end

local TEXT_COLOR = { red = 35 / 255, green = 38 / 255, blue = 52 / 255, alpha = 1 } -- crust
local SEPARATOR_COLOR = {
  red = TEXT_COLOR.red,
  green = TEXT_COLOR.green,
  blue = TEXT_COLOR.blue,
  alpha = SEPARATOR_ALPHA,
}
local POSITION_FILE = hs.configdir .. "/" .. DEFAULT_POSITION_STORE_FILE
local RUNTIME_KEY = "__skhd_hud_runtime"

local function hexToColor(hex, alpha)
  local clean = (hex or ""):gsub("#", "")
  if #clean ~= 6 then
    return { red = 0, green = 0, blue = 0, alpha = alpha or 1 }
  end

  local r = tonumber(clean:sub(1, 2), 16) or 0
  local g = tonumber(clean:sub(3, 4), 16) or 0
  local b = tonumber(clean:sub(5, 6), 16) or 0

  return {
    red = r / 255,
    green = g / 255,
    blue = b / 255,
    alpha = alpha or 1,
  }
end

local function cleanupExistingRuntime()
  local existing = rawget(_G, RUNTIME_KEY)
  if not existing then
    return
  end

  if existing.fadeTimer then
    existing.fadeTimer:stop()
    existing.fadeTimer = nil
  end
  if existing.spaceWatcher then
    existing.spaceWatcher:stop()
    existing.spaceWatcher = nil
  end
  if existing.spacePollTimer then
    existing.spacePollTimer:stop()
    existing.spacePollTimer = nil
  end
  if existing.spaceRefreshTimer then
    existing.spaceRefreshTimer:stop()
    existing.spaceRefreshTimer = nil
  end
  if existing.dragTap then
    existing.dragTap:stop()
    existing.dragTap = nil
  end
  if existing.canvas then
    existing.canvas:delete()
    existing.canvas = nil
  end
end

cleanupExistingRuntime()

local runtime = {
  canvas = nil,
  visible = false,
  fadeTimer = nil,
  spaceWatcher = nil,
  spacePollTimer = nil,
  spaceRefreshTimer = nil,
  lastSpaceNumber = nil,
  elementCount = 0,
  dragTap = nil,
  dragStartAllowed = false,
  dragging = false,
  dragOffset = nil,
  anchor = nil,
  positionLocked = false,
}
_G[RUNTIME_KEY] = runtime

M.modeStack = {}

local ACTIVE_FONT = nil
local ACTIVE_BOLD_FONT = "Helvetica-Bold"
local ACTIVE_BADGE_FONT = "Helvetica-Bold"

local function round(n)
  return math.floor((n or 0) + 0.5)
end

local function fileExists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function trimSpaces(value)
  local text = tostring(value or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function clampUnit(value, fallback)
  local number = tonumber(value)
  if type(number) ~= "number" then
    return fallback
  end
  if number < 0 then
    return 0
  end
  if number > 1 then
    return 1
  end
  return number
end

local function clampTextSize(value, fallback)
  local number = tonumber(value)
  if type(number) ~= "number" then
    return fallback
  end
  number = round(number)
  if number < 8 then
    return fallback
  end
  return number
end

local function normalizeHex(hex, fallback)
  local clean = tostring(hex or ""):gsub("#", "")
  if #clean == 6 and clean:match("^[%x]+$") then
    return "#" .. clean:upper()
  end
  return fallback
end

local function resolveConfigPath(pathValue, fallbackFileName)
  local fallback = hs.configdir .. "/" .. fallbackFileName
  if type(pathValue) ~= "string" then
    return fallback
  end

  local clean = trimSpaces(pathValue)
  if clean == "" then
    return fallback
  end
  if clean:sub(1, 1) == "/" then
    return clean
  end
  return hs.configdir .. "/" .. clean
end

local function copyPalette(source)
  local palette = {}
  for _, color in ipairs(source or {}) do
    palette[#palette + 1] = color
  end
  return palette
end

local function loadHudConfigData()
  local settingsFile = nil
  if fileExists(SETTINGS_FILE) then
    settingsFile = SETTINGS_FILE
  elseif fileExists(LEGACY_SETTINGS_FILE) then
    settingsFile = LEGACY_SETTINGS_FILE
  else
    return {}
  end

  local ok, data = pcall(dofile, settingsFile)
  if not ok or type(data) ~= "table" then
    return {}
  end
  return data
end

local function applyHudConfig()
  local config = loadHudConfigData()
  local colors = type(config.colors) == "table" and config.colors or {}
  local alpha = type(config.alpha) == "table" and config.alpha or {}
  local typography = type(config.typography) == "table" and config.typography or {}

  local configuredPalette = {}
  if type(colors.palette) == "table" then
    for _, rawColor in ipairs(colors.palette) do
      local clean = normalizeHex(rawColor)
      if clean then
        configuredPalette[#configuredPalette + 1] = clean
      end
    end
  end
  if #configuredPalette == 0 then
    BLOCK_PALETTE = copyPalette(DEFAULT_BLOCK_PALETTE)
  else
    BLOCK_PALETTE = configuredPalette
  end

  BADGE_COLOR_HEX = normalizeHex(colors.badge, DEFAULT_BADGE_COLOR_HEX)
  local textHex = normalizeHex(colors.text, DEFAULT_TEXT_COLOR_HEX)
  TEXT_COLOR = hexToColor(textHex, 1)

  BLOCK_ALPHA = clampUnit(alpha.blocks, DEFAULT_BLOCK_ALPHA)
  BADGE_ALPHA = clampUnit(alpha.badge, DEFAULT_BADGE_ALPHA)
  IDLE_BADGE_ALPHA = clampUnit(alpha.badge_idle, DEFAULT_IDLE_BADGE_ALPHA)
  SEPARATOR_ALPHA = clampUnit(alpha.separator, DEFAULT_SEPARATOR_ALPHA)
  SEPARATOR_COLOR = {
    red = TEXT_COLOR.red,
    green = TEXT_COLOR.green,
    blue = TEXT_COLOR.blue,
    alpha = SEPARATOR_ALPHA,
  }

  FONT_SIZE = clampTextSize(typography.font_size, DEFAULT_FONT_SIZE)
  KEY_HINT_FONT_SIZE = clampTextSize(typography.key_hint_size, DEFAULT_KEY_HINT_FONT_SIZE)
  MODE_FONT_SIZE = clampTextSize(typography.mode_size, DEFAULT_MODE_FONT_SIZE)
  BADGE_FONT_SIZE = clampTextSize(typography.badge_size, DEFAULT_BADGE_FONT_SIZE)
  BADGE_TEXT_Y_OFFSET = round(tonumber(typography.badge_y_offset) or DEFAULT_BADGE_TEXT_Y_OFFSET)

  local regularFont = trimSpaces(typography.font)
  if regularFont ~= "" then
    ACTIVE_FONT = regularFont
  else
    ACTIVE_FONT = nil
  end

  local boldFont = trimSpaces(typography.bold_font)
  if boldFont ~= "" then
    ACTIVE_BOLD_FONT = boldFont
  else
    ACTIVE_BOLD_FONT = "Helvetica-Bold"
  end

  local badgeFont = trimSpaces(typography.badge_font)
  if badgeFont ~= "" then
    ACTIVE_BADGE_FONT = badgeFont
  else
    ACTIVE_BADGE_FONT = ACTIVE_BOLD_FONT or ACTIVE_FONT
  end

  POSITION_FILE = resolveConfigPath(config.position_store, DEFAULT_POSITION_STORE_FILE)
end

applyHudConfig()

local function resolveScreenFrame(screen)
  if not screen then
    return nil
  end

  local frame = screen:frame()
  if type(frame) ~= "table" or type(frame.w) ~= "number" then
    frame = screen:fullFrame()
  end
  if type(frame) ~= "table" then
    return nil
  end

  return frame
end

local function screenFrameForPoint(point)
  if type(point) ~= "table" then
    return nil
  end
  if type(point.x) ~= "number" or type(point.y) ~= "number" then
    return nil
  end
  if type(hs.screen) ~= "table" or type(hs.screen.allScreens) ~= "function" then
    return nil
  end

  for _, screen in ipairs(hs.screen.allScreens()) do
    local frame = resolveScreenFrame(screen)
    if frame and point.x >= frame.x and point.x <= (frame.x + frame.w) and point.y >= frame.y and point.y <= (frame.y + frame.h) then
      return frame
    end
  end

  return nil
end

local function fallbackScreenFrame()
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen() or hs.screen.primaryScreen()
  return resolveScreenFrame(screen) or { x = 0, y = 0, w = 1440, h = 900 }
end

local function loadPositionFromFile(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if not fileExists(path) then
    return nil
  end

  local ok, data = pcall(dofile, path)
  if not ok or type(data) ~= "table" then
    return nil
  end
  if type(data.right) == "number" and type(data.bottom) == "number" then
    return { right = round(data.right), bottom = round(data.bottom) }
  end

  -- Backward compatibility with older top-left format.
  if type(data.x) == "number" and type(data.y) == "number" then
    return {
      right = round(data.x + MIN_WIDTH),
      bottom = round(data.y + HUD_HEIGHT),
    }
  end

  return nil
end

local function loadPosition()
  local position = loadPositionFromFile(POSITION_FILE)
  if position then
    return position
  end
  if POSITION_FILE ~= LEGACY_POSITION_FILE then
    return loadPositionFromFile(LEGACY_POSITION_FILE)
  end
  return nil
end

local function defaultAnchor(width)
  local frame = fallbackScreenFrame()
  local x = frame.x + round((frame.w - width) / 2)
  local y = frame.y + DEFAULT_TOP_MARGIN
  return { right = x + width, bottom = y + HUD_HEIGHT }
end

local function savePosition(anchor)
  if type(anchor) ~= "table" then
    return false
  end
  if type(anchor.right) ~= "number" or type(anchor.bottom) ~= "number" then
    return false
  end

  local out = io.open(POSITION_FILE, "w")
  if not out then
    return false
  end

  local line = string.format(
    "-- skhd_hud_state.lua (auto-generated, do not edit manually)\nreturn { right = %d, bottom = %d }\n",
    round(anchor.right),
    round(anchor.bottom)
  )
  out:write(line)
  out:close()
  return true
end

local function paletteColor(index)
  local count = #BLOCK_PALETTE
  if count == 0 then
    return hexToColor("#8CAAEE", BLOCK_ALPHA)
  end
  local wrapped = ((index - 1) % count) + 1
  return hexToColor(BLOCK_PALETTE[wrapped], BLOCK_ALPHA)
end

local function blockColorForDepth(depth, offset)
  local safeDepth = math.max(1, tonumber(depth) or 1)
  local safeOffset = tonumber(offset) or 0
  return paletteColor(safeDepth + safeOffset)
end

local function badgeColor(isIdleBadgeOnly)
  local alpha = BADGE_ALPHA
  if isIdleBadgeOnly then
    alpha = IDLE_BADGE_ALPHA
  end
  return hexToColor(BADGE_COLOR_HEX, alpha)
end

local function trim(text)
  local safe = tostring(text or "")
  safe = safe:gsub("^%s+", "")
  safe = safe:gsub("%s+$", "")
  return safe
end

local function splitByPipe(raw)
  local segments = {}
  local safe = tostring(raw or "")
  for part in safe:gmatch("[^|]+") do
    local clean = trim(part)
    if clean ~= "" then
      segments[#segments + 1] = clean
    end
  end
  return segments
end

local function splitOptions(raw)
  local safe = tostring(raw or "")
  local transitionPart = safe
  local directPart = ""

  local openPos = safe:find("{", 1, true)
  if openPos then
    local closePos = safe:find("}", openPos + 1, true)
    if closePos and closePos > openPos then
      transitionPart = safe:sub(1, openPos - 1)
      directPart = safe:sub(openPos + 1, closePos - 1)
    end
  end

  return splitByPipe(transitionPart), splitByPipe(directPart)
end

local function fontForRun(isBold)
  if isBold then
    return ACTIVE_BOLD_FONT or ACTIVE_FONT
  end
  return ACTIVE_FONT
end

local function measureRunWidth(text, isBold, size, fontName)
  local safeText = tostring(text or "")
  if safeText == "" then
    return 0
  end

  local textSize = tonumber(size) or FONT_SIZE
  local textStyle = { size = textSize }
  local font = fontName
  if type(font) ~= "string" or font == "" then
    font = fontForRun(isBold)
  end
  if font then
    textStyle.font = font
  end

  local ok, measuredSize = pcall(hs.drawing.getTextDrawingSize, safeText, textStyle)
  if ok and type(measuredSize) == "table" and type(measuredSize.w) == "number" then
    return round(measuredSize.w + 1)
  end

  local okLen, glyphs = pcall(utf8.len, safeText)
  if not okLen or type(glyphs) ~= "number" then
    glyphs = string.len(safeText)
  end

  local fallbackWidth = isBold and FALLBACK_BOLD_GLYPH_WIDTH or FALLBACK_GLYPH_WIDTH
  fallbackWidth = fallbackWidth * (textSize / FONT_SIZE)
  return round(glyphs * fallbackWidth)
end

local function parseRuns(raw)
  local safe = tostring(raw or "")
  local runs = {}
  local cursor = 1

  while cursor <= #safe do
    local openPos = safe:find("[", cursor, true)
    if not openPos then
      local tail = safe:sub(cursor)
      if tail ~= "" then
        runs[#runs + 1] = { text = tail, bold = false, size = FONT_SIZE }
      end
      break
    end

    if openPos > cursor then
      runs[#runs + 1] = { text = safe:sub(cursor, openPos - 1), bold = false, size = FONT_SIZE }
    end

    local closePos = safe:find("]", openPos + 1, true)
    if not closePos then
      runs[#runs + 1] = { text = safe:sub(openPos), bold = false, size = FONT_SIZE }
      break
    end

    local marked = safe:sub(openPos + 1, closePos - 1)
    if marked ~= "" then
      runs[#runs + 1] = { text = marked, bold = true, size = KEY_HINT_FONT_SIZE }
    end
    cursor = closePos + 1
  end

  for _, run in ipairs(runs) do
    run.width = measureRunWidth(run.text, run.bold, run.size, run.font)
  end
  return runs
end

local function buildSegment(raw)
  local clean = trim(raw)
  if clean == "" then
    return nil
  end

  local runs = parseRuns(clean)
  local width = 0
  for _, run in ipairs(runs) do
    width = width + (run.width or 0)
  end

  return { runs = runs, width = width }
end

local function buildSegments(rawSegments)
  local segments = {}
  for _, raw in ipairs(rawSegments or {}) do
    local segment = buildSegment(raw)
    if segment and segment.width > 0 then
      segments[#segments + 1] = segment
    end
  end
  return segments
end

local function makeSingleRunSegment(text, isBold, size, fontName)
  local safeText = trim(text)
  if safeText == "" then
    return nil
  end

  local run = {
    text = safeText,
    bold = isBold == true,
    size = tonumber(size) or FONT_SIZE,
    font = fontName,
  }
  run.width = measureRunWidth(run.text, run.bold, run.size, run.font)

  return {
    runs = { run },
    width = run.width,
  }
end

local function currentSpaceNumber()
  if type(hs.spaces) ~= "table" then
    return nil
  end

  local okFocused, focusedSpace = pcall(hs.spaces.focusedSpace)
  if not okFocused or type(focusedSpace) ~= "number" then
    return nil
  end

  local screen
  if type(hs.window) == "table" and type(hs.window.focusedWindow) == "function" then
    local okWindow, focusedWindow = pcall(hs.window.focusedWindow)
    if okWindow and focusedWindow and type(focusedWindow.screen) == "function" then
      local okScreen, focusedScreen = pcall(focusedWindow.screen, focusedWindow)
      if okScreen then
        screen = focusedScreen
      end
    end
  end
  if not screen then
    screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen() or hs.screen.primaryScreen()
  end
  if screen and type(hs.spaces.allSpaces) == "function" then
    local okAll, allSpaces = pcall(hs.spaces.allSpaces)
    if okAll and type(allSpaces) == "table" then
      local ordered = allSpaces[screen:getUUID()]
      if type(ordered) == "table" then
        for idx, spaceID in ipairs(ordered) do
          if spaceID == focusedSpace then
            return tostring(idx)
          end
        end
      end
    end
  end

  return tostring(focusedSpace)
end

local function buildHudContent(modeName, optionsText)
  local safeMode = trim(modeName)
  if safeMode == "" then
    safeMode = EMPTY_SHOW_LABEL
  end

  local transitionSegments, directSegments = splitOptions(optionsText)
  local modeSegments = {}

  local modeHeadline = makeSingleRunSegment(safeMode, true, MODE_FONT_SIZE)
  if modeHeadline then
    modeSegments[#modeSegments + 1] = modeHeadline
  end

  local transitionBuilt = buildSegments(transitionSegments)
  for _, segment in ipairs(transitionBuilt) do
    modeSegments[#modeSegments + 1] = segment
  end

  return {
    badgeText = currentSpaceNumber() or "?",
    modeSegments = modeSegments,
    directSegments = buildSegments(directSegments),
  }
end

local function frameFromAnchor(anchor, width, height)
  local safeW = round(width or MIN_WIDTH)
  local safeH = round(height or HUD_HEIGHT)
  return {
    x = round(anchor.right - safeW),
    y = round(anchor.bottom - safeH),
    w = safeW,
    h = safeH,
  }
end

local function anchorFromFrame(frame)
  return {
    right = round(frame.x + frame.w),
    bottom = round(frame.y + frame.h),
  }
end

local function clampFrameToBounds(frame, bounds)
  if type(frame) ~= "table" then
    return nil
  end
  if type(bounds) ~= "table" then
    return frame
  end

  local clamped = {
    x = round(frame.x or 0),
    y = round(frame.y or 0),
    w = round(frame.w or MIN_WIDTH),
    h = round(frame.h or HUD_HEIGHT),
  }

  if clamped.w <= (bounds.w or 0) then
    local maxX = round(bounds.x + bounds.w - clamped.w)
    clamped.x = math.min(math.max(clamped.x, round(bounds.x)), maxX)
  else
    clamped.x = round(bounds.x)
  end

  if clamped.h <= (bounds.h or 0) then
    local maxY = round(bounds.y + bounds.h - clamped.h)
    clamped.y = math.min(math.max(clamped.y, round(bounds.y)), maxY)
  else
    clamped.y = round(bounds.y)
  end

  return clamped
end

local function screenFrameForAnchor(anchor)
  local point = {
    x = round((anchor and anchor.right) or 0) - 1,
    y = round((anchor and anchor.bottom) or 0) - 1,
  }
  return screenFrameForPoint(point) or fallbackScreenFrame()
end

local function makeBadgeSegment(text)
  local segment = makeSingleRunSegment(text, true, BADGE_FONT_SIZE, ACTIVE_BADGE_FONT)
  if segment then
    return segment
  end
  return makeSingleRunSegment("?", true, BADGE_FONT_SIZE, ACTIVE_BADGE_FONT)
end

local function measureBlockWidth(segments, paddingX)
  local width = (paddingX or 0) * 2
  for idx, segment in ipairs(segments or {}) do
    width = width + (segment.width or 0)
    if idx < #segments then
      width = width + (SEPARATOR_GAP_X * 2) + SEPARATOR_WIDTH
    end
  end
  return round(width)
end

local function measureSegmentsContentWidth(segments)
  local width = 0
  for idx, segment in ipairs(segments or {}) do
    width = width + (segment.width or 0)
    if idx < #segments then
      width = width + (SEPARATOR_GAP_X * 2) + SEPARATOR_WIDTH
    end
  end
  return round(width)
end

local function appendTextRunElement(elements, run, x)
  local textSize = tonumber(run.size) or FONT_SIZE
  local textHeight = textSize + 8
  local textY = round((HUD_HEIGHT - textHeight) / 2)
  local width = math.max(1, round(run.width or 0))
  local textElement = {
    type = "text",
    text = run.text or "",
    textColor = TEXT_COLOR,
    textSize = textSize,
    textAlignment = "left",
    frame = { x = round(x), y = textY, w = width, h = textHeight },
  }
  local font = run.font
  if type(font) ~= "string" or font == "" then
    font = fontForRun(run.bold)
  end
  if font then
    textElement.textFont = font
  end
  elements[#elements + 1] = textElement
end

local function appendCenteredSingleRunElement(elements, blockX, blockWidth, segment, yOffset)
  if type(segment) ~= "table" or type(segment.runs) ~= "table" then
    return false
  end
  if #segment.runs ~= 1 then
    return false
  end

  local run = segment.runs[1]
  local textSize = tonumber(run.size) or FONT_SIZE
  local textHeight = textSize + 8
  local offset = tonumber(yOffset) or 0
  local textY = round((HUD_HEIGHT - textHeight) / 2 + offset)
  local textElement = {
    type = "text",
    text = run.text or "",
    textColor = TEXT_COLOR,
    textSize = textSize,
    textAlignment = "center",
    frame = { x = round(blockX), y = textY, w = round(blockWidth), h = textHeight },
  }
  local font = run.font
  if type(font) ~= "string" or font == "" then
    font = fontForRun(run.bold)
  end
  if font then
    textElement.textFont = font
  end
  elements[#elements + 1] = textElement
  return true
end

local function appendSegmentBlock(elements, blockX, blockWidth, paddingX, radius, fillColor, segments, alignCenter, centeredYOffset)
  elements[#elements + 1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = radius, yRadius = radius },
    fillColor = fillColor,
    frame = { x = round(blockX), y = 0, w = round(blockWidth), h = HUD_HEIGHT },
  }

  if alignCenter
    and type(segments) == "table"
    and #segments == 1
    and appendCenteredSingleRunElement(elements, blockX, blockWidth, segments[1], centeredYOffset)
  then
    return
  end

  local cursorStart = blockX + (paddingX or 0)
  if alignCenter then
    local contentWidth = measureSegmentsContentWidth(segments)
    cursorStart = blockX + round((blockWidth - contentWidth) / 2)
  end
  local cursor = cursorStart

  for segIdx, segment in ipairs(segments or {}) do
    for _, run in ipairs(segment.runs or {}) do
      if run.width and run.width > 0 then
        appendTextRunElement(elements, run, cursor)
        cursor = round(cursor + run.width)
      end
    end

    if segIdx < #segments then
      cursor = round(cursor + SEPARATOR_GAP_X)
      elements[#elements + 1] = {
        type = "rectangle",
        action = "fill",
        fillColor = SEPARATOR_COLOR,
        frame = { x = round(cursor), y = 0, w = SEPARATOR_WIDTH, h = HUD_HEIGHT },
      }
      cursor = round(cursor + SEPARATOR_WIDTH + SEPARATOR_GAP_X)
    end
  end
end

local function shiftElementsX(elements, offset)
  if offset == 0 then
    return
  end

  for _, element in ipairs(elements or {}) do
    if type(element.frame) == "table" and type(element.frame.x) == "number" then
      element.frame.x = round(element.frame.x + offset)
    end
  end
end

local function buildHudLayout(content, depth, isIdleBadgeOnly)
  local badgeSegments = { makeBadgeSegment(content.badgeText) }
  local modeSegments = content.modeSegments or {}
  local directSegments = content.directSegments or {}

  local badgeWidth = math.max(HUD_HEIGHT, measureBlockWidth(badgeSegments, BADGE_PADDING_X))
  local hasMode = #modeSegments > 0
  local modeWidth = 0
  if hasMode then
    modeWidth = measureBlockWidth(modeSegments, BLOCK_PADDING_X)
  end
  local directWidth = 0
  local hasDirect = hasMode and (#directSegments > 0)
  if hasDirect then
    directWidth = measureBlockWidth(directSegments, BLOCK_PADDING_X)
  end

  local elements = {}
  local cursor = 0

  if hasMode then
    appendSegmentBlock(
      elements,
      cursor,
      modeWidth,
      BLOCK_PADDING_X,
      BLOCK_CORNER_RADIUS,
      blockColorForDepth(depth, 1),
      modeSegments
    )
    cursor = cursor + modeWidth
  end

  if hasDirect then
    cursor = cursor + BLOCK_GAP
    appendSegmentBlock(
      elements,
      cursor,
      directWidth,
      BLOCK_PADDING_X,
      BLOCK_CORNER_RADIUS,
      blockColorForDepth(depth, 2),
      directSegments
    )
    cursor = cursor + directWidth
  end

  -- Keep the space badge as the rightmost block, so anchoring to the screen
  -- right edge remains intuitive even when mode text grows.
  if cursor > 0 then
    cursor = cursor + BLOCK_GAP
  end
  appendSegmentBlock(
    elements,
    cursor,
    badgeWidth,
    BADGE_PADDING_X,
    BADGE_CORNER_RADIUS,
    badgeColor(isIdleBadgeOnly == true),
    badgeSegments,
    true,
    BADGE_TEXT_Y_OFFSET
  )
  cursor = cursor + badgeWidth

  local contentWidth = round(cursor)
  local totalWidth = math.max(MIN_WIDTH, contentWidth)
  if totalWidth > contentWidth then
    shiftElementsX(elements, totalWidth - contentWidth)
  end

  return {
    width = totalWidth,
    elements = elements,
  }
end

local function stopFadeTimer()
  if runtime.fadeTimer then
    runtime.fadeTimer:stop()
    runtime.fadeTimer = nil
  end
end

local function ensureCanvas()
  if runtime.canvas then
    return runtime.canvas
  end

  runtime.anchor = loadPosition()
  runtime.positionLocked = runtime.anchor ~= nil
  if not runtime.anchor then
    runtime.anchor = defaultAnchor(MIN_WIDTH)
  end

  runtime.canvas = hs.canvas.new(frameFromAnchor(runtime.anchor, MIN_WIDTH, HUD_HEIGHT))
  runtime.canvas:level(hs.canvas.windowLevels.overlay)
  runtime.canvas:behavior(
    hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary
  )
  runtime.canvas:alpha(0)
  runtime.canvas:hide()
  runtime.elementCount = 0

  return runtime.canvas
end

local function applyContent(content, depth, isIdleBadgeOnly)
  local canvas = ensureCanvas()
  local layout = buildHudLayout(content or {}, depth or 1, isIdleBadgeOnly == true)
  local width = layout.width

  if not runtime.anchor then
    runtime.anchor = defaultAnchor(width)
  end

  local frame = frameFromAnchor(runtime.anchor, width, HUD_HEIGHT)
  frame = clampFrameToBounds(frame, screenFrameForAnchor(runtime.anchor))
  canvas:frame(frame)

  if type(canvas.replaceElements) == "function" then
    canvas:replaceElements(layout.elements or {})
  else
    while #canvas > 0 do
      canvas[#canvas] = nil
    end
    for i, element in ipairs(layout.elements or {}) do
      canvas[i] = element
    end
  end
  runtime.elementCount = #(layout.elements or {})
end

local function fadeTo(targetAlpha, onComplete)
  local canvas = ensureCanvas()
  stopFadeTimer()

  local startAlpha = canvas:alpha()
  if math.abs(startAlpha - targetAlpha) < 0.001 then
    runtime.visible = targetAlpha > 0
    if runtime.visible then
      canvas:show()
    else
      canvas:hide()
    end
    if onComplete then
      onComplete()
    end
    return
  end

  if targetAlpha > 0 then
    canvas:show()
    pcall(function()
      canvas:bringToFront(true)
    end)

    -- In one-shot hs -c invocations fade timers may not execute reliably.
    -- Ensure HUD is still visible when transitioning from fully transparent.
    if startAlpha <= 0.001 then
      canvas:alpha(targetAlpha)
      runtime.visible = true
      if onComplete then
        onComplete()
      end
      return
    end
  end

  local startedAt = hs.timer.secondsSinceEpoch()
  runtime.fadeTimer = hs.timer.doEvery(1 / 60, function()
    local elapsed = hs.timer.secondsSinceEpoch() - startedAt
    local progress = elapsed / FADE_DURATION
    if progress >= 1 then
      canvas:alpha(targetAlpha)
      stopFadeTimer()
      runtime.visible = targetAlpha > 0
      if not runtime.visible then
        canvas:hide()
      end
      if onComplete then
        onComplete()
      end
      return
    end

    local alpha = startAlpha + ((targetAlpha - startAlpha) * progress)
    canvas:alpha(alpha)
  end)
end

local function pointInFrame(point, frame)
  return point.x >= frame.x
    and point.x <= (frame.x + frame.w)
    and point.y >= frame.y
    and point.y <= (frame.y + frame.h)
end

local function installDragTap()
  if runtime.dragTap then
    return
  end

  local eventTypes = hs.eventtap.event.types
  runtime.dragTap = hs.eventtap.new({
    eventTypes.leftMouseDown,
    eventTypes.leftMouseDragged,
    eventTypes.leftMouseUp,
  }, function(event)
    local canvas = ensureCanvas()
    local kind = event:getType()

    if kind == eventTypes.leftMouseDown then
      runtime.dragStartAllowed = false
      runtime.dragging = false
      runtime.dragOffset = nil

      if canvas:alpha() <= 0 then
        return false
      end
      if DRAG_REQUIRES_CMD and not event:getFlags().cmd then
        return false
      end

      local mouse = hs.mouse.absolutePosition()
      if not pointInFrame(mouse, canvas:frame()) then
        return false
      end

      local frame = canvas:frame()
      runtime.dragStartAllowed = true
      runtime.dragOffset = { x = mouse.x - frame.x, y = mouse.y - frame.y }
      return false
    end

    if kind == eventTypes.leftMouseDragged then
      if not runtime.dragStartAllowed then
        return false
      end
      if DRAG_REQUIRES_CMD and not event:getFlags().cmd then
        runtime.dragStartAllowed = false
        runtime.dragging = false
        runtime.dragOffset = nil
        return false
      end

      local mouse = hs.mouse.absolutePosition()
      local frame = canvas:frame()
      local offset = runtime.dragOffset or { x = frame.w / 2, y = frame.h / 2 }

      frame.x = round(mouse.x - offset.x)
      frame.y = round(mouse.y - offset.y)
      frame = clampFrameToBounds(frame, fallbackScreenFrame())
      canvas:frame(frame)

      runtime.anchor = anchorFromFrame(frame)
      runtime.positionLocked = true
      runtime.dragging = true
      return false
    end

    if kind == eventTypes.leftMouseUp then
      if runtime.dragging then
        savePosition(runtime.anchor)
      end

      runtime.dragStartAllowed = false
      runtime.dragging = false
      runtime.dragOffset = nil
      return false
    end

    return false
  end)

  runtime.dragTap:start()
end

local function buildIdleContent()
  return {
    badgeText = currentSpaceNumber() or "?",
    modeSegments = {},
    directSegments = {},
  }
end

local function renderCurrentState()
  if #M.modeStack == 0 then
    applyContent(buildIdleContent(), 1, true)
    return true
  end

  local last = M.modeStack[#M.modeStack]
  local content = buildHudContent(last.name, last.options)
  applyContent(content, #M.modeStack, false)
  return true
end

local function refreshSpaceBadge(force)
  local current = currentSpaceNumber() or "?"
  if not force and runtime.lastSpaceNumber == current then
    return false
  end
  runtime.lastSpaceNumber = current
  renderCurrentState()
  if not runtime.visible then
    fadeTo(1)
  end
  return true
end

local function requestSpaceBadgeRefresh(force)
  if runtime.spaceRefreshTimer then
    runtime.spaceRefreshTimer:stop()
    runtime.spaceRefreshTimer = nil
  end
  local forceUpdate = force == true
  runtime.spaceRefreshTimer = hs.timer.doAfter(SPACE_REFRESH_DEBOUNCE, function()
    runtime.spaceRefreshTimer = nil
    refreshSpaceBadge(forceUpdate)
  end)
end

local function installSpaceTracking()
  if runtime.spaceWatcher then
    return
  end

  if type(hs.spaces) == "table"
    and type(hs.spaces.watcher) == "table"
    and type(hs.spaces.watcher.new) == "function"
  then
    runtime.spaceWatcher = hs.spaces.watcher.new(function()
      requestSpaceBadgeRefresh(true)
    end)
    runtime.spaceWatcher:start()
  end

  runtime.spacePollTimer = hs.timer.doEvery(SPACE_POLL_INTERVAL, function()
    refreshSpaceBadge(false)
  end)
end

function M.push(name, options)
  local safeName = tostring(name or "")
  local safeOptions = tostring(options or "")
  table.insert(M.modeStack, { name = safeName, options = safeOptions })

  if not renderCurrentState() then
    return
  end
  fadeTo(1)
end

function M.pop()
  if #M.modeStack == 0 then
    return
  end

  table.remove(M.modeStack, #M.modeStack)
  if #M.modeStack == 0 then
    M.reset()
    return
  end

  renderCurrentState()
end

function M.reset()
  M.modeStack = {}
  runtime.lastSpaceNumber = currentSpaceNumber() or runtime.lastSpaceNumber
  renderCurrentState()
  fadeTo(1)
end

function M.show()
  if not renderCurrentState() then
    return
  end
  fadeTo(1)
end

function M.hide()
  -- Keep the always-on space badge visible in default mode.
  M.reset()
end

ensureCanvas()
installDragTap()
installSpaceTracking()
M.reset()

return M
