local path = ({...})[1]:gsub("%.debug$", "")
local debug = {}

debug.opened = false
debug.active = false
debug.input = ""
debug.history = { index = 0 }
debug.buffer = { index = 0 }
debug.commands = {}

debug.settings = {
  pauseWorld = true,
  bufferLimit = 1000,
  historyLimit = 100,
  prompt = "> ",
  multiEraseTime = 0.35,
  multiEraseCharTime = 0.025
}

debug.controls = {
  open = "`",
  pause = "",
  up = "pageup",
  down = "pagedown",
  historyUp = "up",
  historyDown = "down",
  erase = "backspace",
  execute = "return"
}

debug.style = {
  color = { 240, 240, 240, 255 },
  bgColor = { 0, 0, 0, 200 },
  borderColor = { 200, 200, 200, 220 },
  height = 400,
  borderSize = 2,
  font = love.graphics.newFont(path:gsub("%.", "/") .. "/inconsolata.otf", 18),
  padding = 10,
  cursor = "|",
  tween = true,
  openTime = 0.1,
  cursorBlinkTime = 0.5
}

debug.style.y = -debug.style.height

local timers = {
  multiErase = 0,
  multiEraseChar = 0,
  blink = -debug.style.cursorBlinkTime -- negative = cursor off, positive = cursor on
}

local function makeActive()
  debug.active = true
end

local function joinWithSpaces(...)
  local str = ""
  for _, v in ipairs{...} do str = str .. v .. " " end
  return str
end

local function addTo(t, v, limit)
  t[#t + 1] = v
  t.index = #t
  if #t > limit then table.remove(t, 1) end
end

local function removeCharacter()
  debug.input = debug.input:sub(1, #debug.input - 1)
end

local function moveConsole(doTween)
  local y = debug.opened and 0 or -debug.style.height - debug.style.borderSize
  if doTween == nil then doTween = true end
  
  if doTween and ammo.ext.tweens then
    debug.tween = AttrTween:new(debug.style, debug.style.openTime, { y = y }, nil, debug.opened and makeActive or nil)
    debug.tween:start()
    if not debug.opened then debug.active = false end
  else
    debug.style.y = y
    debug.active = debug.opened
  end
end

local function handleInput()
  debug.log(debug.settings.prompt .. debug.input)
  local terms = {}
  
  for t in debug.input:gmatch("[^%s]+") do
    terms[#terms + 1] = t
  end
  
  if terms[1] then
    local cmd = debug.commands[terms[1]]
    
    if cmd then
      table.remove(terms, 1)
      
      local result, msg = pcall(cmd, unpack(terms))
      if msg then debug.log(msg) end
    else
      debug.log('No command named "' .. terms[1] .. '"')
    end
    
    addTo(debug.history, debug.input, debug.settings.bufferLimit)
    debug.history.index = #debug.history + 1
  end
  
  debug.input = ""
end

local function handleHistory()
  local i = debug.history.index
  if #debug.history == 0 then return end
  
  if i == #debug.history + 1 then
    debug.input = ""
  else
    debug.input = debug.history[i]
  end
end

function debug.log(...)
  local msg = ""
  local args = {...}
  
  for i, v in ipairs(args) do
    msg = msg .. tostring(v)
    if i < #args then msg = msg .. "    " end
  end
  
  addTo(debug.buffer, msg, debug.settings.bufferLimit)
end

function debug.open(tween)
  debug.opened = true
  moveConsole(tween or debug.style.tween)
end

function debug.close(tween)
  debug.opened = false
  moveConsole(tween or debug.style.tween)
end

function debug.toggle(tween)
  debug.opened = not debug.opened
  moveConsole(tween or debug.style.tween)
end

function debug.update(dt)
  if debug.active then
    -- erasing characters
    if love.keyboard.isDown(debug.controls.erase) and #debug.input > 0 then
      if timers.multiErase == 0 then
        removeCharacter() -- first character when pressed
      elseif timers.multiErase > debug.settings.multiEraseTime then
        -- rapidly erasing multiple characters
        if timers.multiEraseChar <= 0 then
          removeCharacter()
          timers.multiEraseChar = timers.multiEraseChar + debug.settings.multiEraseCharTime
        else
          timers.multiEraseChar = timers.multiEraseChar - dt
        end
      end
      
      timers.multiErase = timers.multiErase + dt
    else
      timers.multiErase = 0
      timers.multiEraseChar = 0
    end
    
    -- cursor blink
    if timers.blink >= debug.style.cursorBlinkTime then
      timers.blink = -debug.style.cursorBlinkTime
    else
      timers.blink = timers.blink + dt
    end
  end
  
  if debug.tween and debug.tween.active then debug.tween:update(dt) end
end

function debug.draw()
  local s = debug.style
  love.graphics.pushColor(s.bgColor)
  love.graphics.rectangle("fill", 0, s.y, love.graphics.width, s.height)
  love.graphics.popColor()
  
  love.graphics.pushColor(s.borderColor)
  love.graphics.rectangle("fill", 0, s.y + s.height, love.graphics.width, s.borderSize)
  love.graphics.popColor()
  
  local str = ""
  local rows = math.floor((s.height - s.padding * 2) / s.font:getHeight())
  local begin = math.max(debug.buffer.index - rows + 2, 1) -- add 2: one for the input line, another for keeping it in bounds (not sure why its needed)
    
  for i = begin, debug.buffer.index do
    str = str .. debug.buffer[i] .. "\n"
  end
  
  str = str .. debug.settings.prompt .. debug.input
  if timers.blink > 0 then str = str .. debug.style.cursor end
  love.graphics.setFont(debug.style.font)
  love.graphics.printf(str, s.padding, debug.style.y + s.padding, love.graphics.width - s.padding * 2)
end

function debug.keypressed(key, code)
  local c = debug.controls
  
  if key == c.open then
    debug.toggle()
    if debug.settings.pauseWorld and ammo.world then ammo.world.active = not debug.opened end
  elseif key == c.pause then
    if ammo.world then ammo.world.active = not ammo.world.active end
  elseif debug.active then
    if key == c.execute then
      handleInput()
    elseif key == c.historyUp then
      debug.history.index = math.max(debug.history.index - 1, 1)
      handleHistory()
    elseif key == c.historyDown then
      -- have to use if statement since handleHistory shouldn't be called if index is already one over #history
      if debug.history.index < #debug.history + 1 then
        debug.history.index = debug.history.index + 1
        handleHistory()
      end
    elseif key == c.up then
      debug.buffer.index = math.max(debug.buffer.index - 1, 1)
    elseif key == c.down then
      debug.buffer.index = math.min(debug.buffer.index + 1, #debug.buffer)
    elseif code > 31 and code < 127 then
      -- ^ those are the printable characters
      debug.input = debug.input .. string.char(code)
    end
  end
end

function debug.commands.lua(...)
  local func, err = loadstring(joinWithSpaces(...))
  
  if err then
    return err
  else
    local result, msg = pcall(func)
    return msg
  end
end

-- works like the Lua interpreter
debug.commands["="] = function(...)
  return debug.commands.lua("return", ...)
end

function debug.commands.clear()
  debug.buffer = { index = 0 }
end

function debug.commands.echo(...)
  return joinWithSpaces(...)
end

function debug.commands.pause()
  if ammo.world then ammo.world.active = not ammo.world.active end
end

function debug.commands.mkcmd(...)
  local args = { ... }
  local name = args[1]
  table.remove(args, 1)
  local func, err = loadstring(joinWithSpaces(unpack(args)))
  
  if err then
    return err
  else
    local msg = 'Command "' .. name .. '" has been ' .. (debug.commands[name] and "replaced." or "added.")
    debug.commands[name] = func
    return msg
  end
end

function debug.commands.rmcmd(name)
  if debug.commands[name] then
    debug.commands[name] = nil
    return 'Command "' .. name .. '" has been removed.'
  else
    return 'No command named "' .. name .. '"'
  end
end

debug.log("==== ammo-debug 0.1 ====")
return debug