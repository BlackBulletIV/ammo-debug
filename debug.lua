local path = ({...})[1]:gsub("%.debug$", "")
local debug = {}

-- PROPERTIES/SETTINGS --

debug.opened = false
debug.active = false
debug.visible = true

debug.input = ""
debug.history = { index = 0 }
debug.buffer = { index = 0 }
debug.commands = {}
debug.info = { keys = {} }

debug.settings = {
  pauseWorld = true,
  alwaysShowInfo = false,
  bufferLimit = 1000,
  historyLimit = 100,
  multiEraseTime = 0.35,
  multiEraseCharTime = 0.025,
  initFile = "debug-init"
}

debug.controls = {
  open = "`",
  pause = "",
  toggleInfo = "",
  up = "pageup",
  down = "pagedown",
  historyUp = "up",
  historyDown = "down",
  erase = "backspace",
  execute = "return"
}

-- visual 
debug.style = {
  -- color
  color = { 240, 240, 240, 255 },
  bgColor = { 0, 0, 0, 200 },
  borderColor = { 200, 200, 200, 220 },
  
  -- spacial
  height = 400,
  infoWidth = 300,
  borderSize = 2,
  padding = 10,
  
  -- text
  font = love.graphics.newFont(path:gsub("%.", "/") .. "/inconsolata.otf", 18),
  prompt = "> ",
  cursor = "|",
  infoSeparator = ": ",
  
  -- misc
  tween = true,
  openTime = 0.1,
  cursorBlinkTime = 0.5
}

debug.style.y = -debug.style.height

-- LOCAL --

-- a few timer variables
local timers = {
  multiErase = 0,
  multiEraseChar = 0,
  blink = -debug.style.cursorBlinkTime -- negative = cursor off, positive = cursor on
}

-- removes the last character from the input line
local function removeCharacter()
  debug.input = debug.input:sub(1, #debug.input - 1)
end

-- adds the item to the table, making sure the table's length hasn't exceeded the limit
local function addTo(t, v, limit)
  t[#t + 1] = v
  t.index = #t
  if #t > limit then table.remove(t, 1) end
end

-- compile an argument as a string if possible
local function compileArg(arg)
  if arg:sub(1, 1) == "$" then
    arg = debug._runCommand(arg:match("^$(.+)$$"), true)
  else  
    local func = loadstring("return " .. arg)
    
    if func then
      arg = func()
    else
      debug.log("Couldn't compile argument #" .. (index - 1) .. " as string.")
    end
  end
  
  return arg
end

-- run a batch file
local function runBatch(file)
  for line in love.filesystem.lines(file) do debug._runCommand(line) end
end

-- both these are used by the tween in moveConsole
local function openEnd()
  debug.active = true
end

local function closeEnd()
  debug.visible = false
end

-- change the console's position depending on debug.opened
local function moveConsole(doTween)
  local y = debug.opened and 0 or -debug.style.height - debug.style.borderSize
  if doTween == nil then doTween = true end
  
  if doTween and ammo.ext.tweens then
    debug.tween = AttrTween:new(debug.style, debug.style.openTime, { y = y }, nil, debug.opened and openEnd or closeEnd)
    debug.tween:start()
    
    if debug.opened then
      debug.visible = true
    else
      debug.active = false
    end
  else
    debug.style.y = y
    debug.active = debug.opened
    debug.visible = debug.opened
  end
end

-- handles the execution of the current input line
local function handleInput()
  debug.log(debug.style.prompt .. debug.input)
  debug._runCommand(debug.input)
  addTo(debug.history, debug.input, debug.settings.bufferLimit)
  debug.history.index = #debug.history + 1  
  debug.input = ""
end

-- displays the currently selected line in the history
local function handleHistory()
  local i = debug.history.index
  if #debug.history == 0 then return end
  
  if i == #debug.history + 1 then
    debug.input = ""
  else
    debug.input = debug.history[i]
  end
end

-- resets the console
local function reset()
  debug.buffer = { index = 0 }
  debug.log("==== ammo-debug 0.1 ====")
  
  -- initialisation file
  if love.filesystem.exists(debug.settings.initFile) then
    runBatch(debug.settings.initFile)
  end
end

-- PUBLIC HELPERS --

-- joins a list of strings, separating them with spaces
function debug._joinWithSpaces(...)
  local str = ""
  local args = { ... }
  for i, v in ipairs(args) do str = str .. v .. (i == #args and "" or " ") end
  return str
end

-- handles the execution of a command (argument splitting, compilation, calling command functions, etc.)
function debug._runCommand(line, ret)
  local terms = {}
  local quotes = false
  
  -- split and compile terms
  for t in line:gmatch("[^%s]+") do
    if quotes then
      terms[#terms] = terms[#terms] .. " " .. t
    else
      terms[#terms + 1] = t
      quotes = t:match("^[\"'$]")
    end
    
    if quotes and t:sub(-1) == quotes then
      quotes = false
      terms[#terms] = compileArg(terms[#terms])
    end
  end
  
  if terms[1] then
    local cmd = debug.commands[terms[1]]
    
    if cmd then
      terms[1] = debug -- replace the name with the self argument
      local result, msg = pcall(cmd, unpack(terms))
      
      if msg then
        if ret then
          return msg
        else
          debug.log(msg)
        end
      end
    else
      debug.log('No command named "' .. terms[1] .. '"')
    end
  end
end

-- FUNCTIONS --

function debug.init()
  debug.addInfo("FPS", love.timer.getFPS)
  debug.addInfo("Entities", function() return ammo.world and ammo.world.count or nil end)
  debug.addInfo("Memory", function() return ("%.2f MB"):format(collectgarbage("count") / 1024) end)
  reset()
end

function debug.log(...)
  local msg = ""
  local args = {...}
  
  for i, v in ipairs(args) do
    msg = msg .. tostring(v)
    if i < #args then msg = msg .. "    " end
  end
  
  for line in msg:gmatch("[^\n]+") do
    addTo(debug.buffer, line, debug.settings.bufferLimit)
  end
end

function debug.addInfo(title, val)
  debug.info[#debug.info + 1] = { title = title, value = val }
  debug.info.keys[title] = #debug.info
end

function debug.updateInfo(title, val)
  debug.info[debug.info.keys[title]].value = val
end

function debug.removeInfo(title)
  if debug.info.keys[title] then
    debug.info[debug.info.keys[title]] = nil
    debug.info.keys[title] = nil
  end
end

function debug.include(t)
  for k, v in pairs(t) do
    if type(v) == "function" then debug.commands[k] = v end
  end
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

-- CALLBACKS --

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
  
  if debug.visible then
    -- background
    love.graphics.pushColor(s.bgColor)
    love.graphics.rectangle("fill", 0, s.y, love.graphics.width, s.height)
    love.graphics.popColor()
    
    -- border
    love.graphics.pushColor(s.borderColor)
    love.graphics.rectangle("fill", 0, s.y + s.height, love.graphics.width, s.borderSize)
    love.graphics.popColor()
    
    -- text
    local str = ""
    local rows = math.floor((s.height - s.padding * 2) / s.font:getHeight())
    local begin = math.max(debug.buffer.index - rows + 2, 1) -- add 2: one for the input line, another for keeping it in bounds (not sure why its needed)
      
    for i = begin, debug.buffer.index do
      str = str .. debug.buffer[i] .. "\n"
    end
    
    str = str .. s.prompt .. debug.input
    if timers.blink > 0 then str = str .. s.cursor end
    love.graphics.setFont(s.font)
    love.graphics.printf(str, s.padding, s.y + s.padding, love.graphics.width - s.infoWidth - s.padding * 2)
  end
  
  if debug.visible or debug.settings.alwaysShowInfo then
    -- info
    str = ""
    
    for _, t in ipairs(debug.info) do
      local v = t.value
      if type(v) == "function" then v = v() end
      if v ~= nil then str = str .. t.title .. s.infoSeparator .. tostring(v) .. "\n" end
    end
    
    local y = (debug.settings.alwaysShowInfo) and 0 or s.y
    love.graphics.printf(str, love.graphics.width - s.infoWidth + s.padding, y + s.padding, s.infoWidth - s.padding * 2)
  end
end

function debug.keypressed(key, code)
  local c = debug.controls
  
  if key == c.open then
    debug.toggle()
    if debug.settings.pauseWorld and ammo.world then ammo.world.active = not debug.opened end
  elseif key == c.pause then
    if ammo.world then ammo.world.active = not ammo.world.active end
  elseif key == c.toggleInfo then
    debug.settings.alwaysShowInfo = not debug.settings.alwaysShowInfo
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
      debug.buffer.index = math.max(debug.buffer.index - 1, 0)
    elseif key == c.down then
      debug.buffer.index = math.min(debug.buffer.index + 1, #debug.buffer)
    elseif code > 31 and code < 127 then
      -- ^ those are the printable characters
      debug.input = debug.input .. string.char(code)
    end
  end
end

-- ESSENTIAL COMMANDS --

function debug.commands:lua(...)
  local func, err = loadstring(debug._joinWithSpaces(...))
  
  if err then
    return err
  else
    local result, msg = pcall(func)
    return msg
  end
end

-- works like the Lua interpreter
debug.commands["="] = function(self, ...)
  return self.commands.lua(self, "return", ...)
end

function debug.commands:bat(file)
  if love.filesystem.exists(file) then
    runBatch(file)
  else
    return "File doesn't exist."
  end
end

debug.commands["repeat"] = function(self, times, ...)
  local cmd = debug._joinWithSpaces(...)
  for i = 1, tonumber(times) do debug._runCommand(cmd) end
end

function debug.commands:clear()
  self.buffer = { index = 0 }
end

function debug.commands:echo(...)
  return debug._joinWithSpaces(...)
end

debug.commands.reset = reset
return debug
