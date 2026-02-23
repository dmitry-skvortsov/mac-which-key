local M = {}

local HUD_HEIGHT = 44
local MIN_WIDTH = 120
local FONT_SIZE = 14
local KEY_HINT_FONT_SIZE = 18
local FADE_DURATION = 0.150
local DEFAULT_TOP_MARGIN = 16
local EMPTY_SHOW_LABEL = "SKHD HUD"
local BACKGROUND_ALPHA = 0.85
local BLOCK_GAP = 8
local BLOCK_CORNER_RADIUS = 12
local BADGE_CORNER_RADIUS = 22
local BLOCK_PADDING_X = 14
local BADGE_PADDING_X = 12
local SEPARATOR_GAP_X = 10
local SEPARATOR_WIDTH = 1
local SEPARATOR_ALPHA = 0.45
local FALLBACK_GLYPH_WIDTH = 9
local FALLBACK_BOLD_GLYPH_WIDTH = 10
local MODE_FONT_SIZE = 17
local BADGE_FONT_SIZE = 16
local DRAG_REQUIRES_CMD = true
local SPACE_REFRESH_DEBOUNCE = 0.06
local SPACE_POLL_INTERVAL = 1.0

-- Catppuccin Frappe accents (non-gray), configurable palette.
local BLOCK_PALETTE = {
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
local BADGE_COLOR_HEX = "#E5C890" -- yellow (higher contrast, Catppuccin Frappe)

local TEXT_COLOR = { red = 35 / 255, green = 38 / 255, blue = 52 / 255, alpha = 1 } -- crust
local SEPARATOR_COLOR = {
  red = TEXT_COLOR.red,
  green = TEXT_COLOR.green,
  blue = TEXT_COLOR.blue,
  alpha = SEPARATOR_ALPHA,
}
local POSITION_FILE = hs.configdir .. "/skhd_hud_position.lua"
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

local function loadPosition()
  if not fileExists(POSITION_FILE) then
    return nil
  end

  local ok, data = pcall(dofile, POSITION_FILE)
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
    "-- skhd_hud_position.lua (auto-generated, do not edit manually)\nreturn { right = %d, bottom = %d }\n",
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
    return hexToColor("#8CAAEE", BACKGROUND_ALPHA)
  end
  local wrapped = ((index - 1) % count) + 1
  return hexToColor(BLOCK_PALETTE[wrapped], BACKGROUND_ALPHA)
end

local function blockColorForDepth(depth, offset)
  local safeDepth = math.max(1, tonumber(depth) or 1)
  local safeOffset = tonumber(offset) or 0
  return paletteColor(safeDepth + safeOffset)
end

local BADGE_COLOR = hexToColor(BADGE_COLOR_HEX, BACKGROUND_ALPHA)

local function badgeColor()
  return BADGE_COLOR
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

local function measureRunWidth(text, isBold, size)
  local safeText = tostring(text or "")
  if safeText == "" then
    return 0
  end

  local textSize = tonumber(size) or FONT_SIZE
  local textStyle = { size = textSize }
  local font = fontForRun(isBold)
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
    run.width = measureRunWidth(run.text, run.bold, run.size)
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

local function makeSingleRunSegment(text, isBold, size)
  local safeText = trim(text)
  if safeText == "" then
    return nil
  end

  local run = {
    text = safeText,
    bold = isBold == true,
    size = tonumber(size) or FONT_SIZE,
  }
  run.width = measureRunWidth(run.text, run.bold, run.size)

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
  local segment = makeSingleRunSegment(text, true, BADGE_FONT_SIZE)
  if segment then
    return segment
  end
  return makeSingleRunSegment("?", true, BADGE_FONT_SIZE)
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
  local font = fontForRun(run.bold)
  if font then
    textElement.textFont = font
  end
  elements[#elements + 1] = textElement
end

local function appendSegmentBlock(elements, blockX, blockWidth, paddingX, radius, fillColor, segments, alignCenter)
  elements[#elements + 1] = {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = radius, yRadius = radius },
    fillColor = fillColor,
    frame = { x = round(blockX), y = 0, w = round(blockWidth), h = HUD_HEIGHT },
  }

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

local function buildHudLayout(content, depth)
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
    badgeColor(),
    badgeSegments,
    true
  )
  cursor = cursor + badgeWidth

  return {
    width = math.max(MIN_WIDTH, round(cursor)),
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

local function applyContent(content, depth)
  local canvas = ensureCanvas()
  local layout = buildHudLayout(content or {}, depth or 1)
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
    applyContent(buildIdleContent(), 1)
    return true
  end

  local last = M.modeStack[#M.modeStack]
  local content = buildHudContent(last.name, last.options)
  applyContent(content, #M.modeStack)
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
