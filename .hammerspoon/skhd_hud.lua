local M = {}

local HUD_HEIGHT = 44
local PADDING_X = 16
local CORNER_RADIUS = 12
local FONT_SIZE = 14
local MIN_WIDTH = 120
local FADE_DURATION = 0.150
local DEFAULT_TOP_MARGIN = 16
local EMPTY_SHOW_LABEL = "SKHD HUD"
local BACKGROUND_ALPHA = 0.90
local DRAG_REQUIRES_CMD = true

local DEPTH_COLORS = {
  [1] = "#8CAAEE", -- blue
  [2] = "#A6D189", -- green
  [3] = "#CA9EE6", -- mauve
}
local OVERFLOW_COLOR = "#E78284" -- red

local TEXT_COLOR = { red = 35 / 255, green = 38 / 255, blue = 52 / 255, alpha = 1 } -- crust
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
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen() or hs.screen.primaryScreen()
  local frame = nil
  if screen then
    frame = screen:frame()
    if type(frame) ~= "table" or type(frame.w) ~= "number" then
      frame = screen:fullFrame()
    end
  end
  frame = frame or { x = 0, y = 0, w = 1440, h = 900 }
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

local function colorForDepth(depth)
  if depth <= 0 then
    return hexToColor(DEPTH_COLORS[1], BACKGROUND_ALPHA)
  end
  if depth >= 4 then
    return hexToColor(OVERFLOW_COLOR, BACKGROUND_ALPHA)
  end
  return hexToColor(DEPTH_COLORS[depth], BACKGROUND_ALPHA)
end

local function measureWidth(text)
  local textStyle = { size = FONT_SIZE }
  if ACTIVE_FONT then
    textStyle.font = ACTIVE_FONT
  end

  local ok, size = pcall(hs.drawing.getTextDrawingSize, text, textStyle)
  if ok and type(size) == "table" and type(size.w) == "number" then
    return math.max(MIN_WIDTH, round(size.w + (PADDING_X * 2)))
  end

  return math.max(MIN_WIDTH, (string.len(text or "") * 8) + (PADDING_X * 2))
end

local function textFrameForWidth(width)
  local textHeight = FONT_SIZE + 8
  return {
    x = PADDING_X,
    y = round((HUD_HEIGHT - textHeight) / 2),
    w = width - (PADDING_X * 2),
    h = textHeight,
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

local function currentSpaceLabel()
  if type(hs.spaces) ~= "table" then
    return nil
  end

  local okFocused, focusedSpace = pcall(hs.spaces.focusedSpace)
  if not okFocused or type(focusedSpace) ~= "number" then
    return nil
  end

  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen() or hs.screen.primaryScreen()
  if screen and type(hs.spaces.allSpaces) == "function" then
    local okAll, allSpaces = pcall(hs.spaces.allSpaces)
    if okAll and type(allSpaces) == "table" then
      local ordered = allSpaces[screen:getUUID()]
      if type(ordered) == "table" then
        for idx, spaceID in ipairs(ordered) do
          if spaceID == focusedSpace then
            return "S" .. tostring(idx)
          end
        end
      end
    end
  end

  return "SPACE " .. tostring(focusedSpace)
end

local function addSpacePrefix(label)
  local spaceLabel = currentSpaceLabel()
  if not spaceLabel then
    return label
  end
  return spaceLabel .. " → " .. label
end

local function buildLabel()
  if #M.modeStack == 0 then
    return nil
  end

  local parts = {}
  for _, entry in ipairs(M.modeStack) do
    parts[#parts + 1] = string.upper(entry.name)
  end

  local last = M.modeStack[#M.modeStack]
  return addSpacePrefix(table.concat(parts, " → ") .. " → " .. last.options)
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

  runtime.canvas[1] = {
    id = "bg",
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = CORNER_RADIUS, yRadius = CORNER_RADIUS },
    fillColor = colorForDepth(1),
    frame = { x = 0, y = 0, w = MIN_WIDTH, h = HUD_HEIGHT },
  }

  local textElement = {
    id = "text",
    type = "text",
    text = "",
    textColor = TEXT_COLOR,
    textSize = FONT_SIZE,
    textAlignment = "left",
    frame = textFrameForWidth(MIN_WIDTH),
  }
  if ACTIVE_FONT then
    textElement.textFont = ACTIVE_FONT
  end
  runtime.canvas[2] = textElement

  return runtime.canvas
end

local function applyContent(label, depth)
  local canvas = ensureCanvas()
  local width = measureWidth(label)
  if not runtime.anchor then
    runtime.anchor = defaultAnchor(width)
  end
  local frame = frameFromAnchor(runtime.anchor, width, HUD_HEIGHT)
  canvas:frame(frame)

  canvas[1].fillColor = colorForDepth(depth)
  canvas[1].frame = { x = 0, y = 0, w = width, h = HUD_HEIGHT }
  canvas[2].text = label
  canvas[2].frame = textFrameForWidth(width)
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

local function renderStack()
  local label = buildLabel()
  if not label then
    return false
  end
  applyContent(label, #M.modeStack)
  return true
end

function M.push(name, options)
  local safeName = tostring(name or "")
  local safeOptions = tostring(options or "")
  table.insert(M.modeStack, { name = safeName, options = safeOptions })

  if not renderStack() then
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

  renderStack()
end

function M.reset()
  M.modeStack = {}
  fadeTo(0)
end

function M.show()
  if #M.modeStack == 0 then
    applyContent(addSpacePrefix(EMPTY_SHOW_LABEL), 1)
    fadeTo(1)
    return
  end

  if not renderStack() then
    return
  end
  fadeTo(1)
end

function M.hide()
  fadeTo(0)
end

ensureCanvas()
installDragTap()

return M
