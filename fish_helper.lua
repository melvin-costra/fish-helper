script_author("melvin-costra")
script_name("Fish helper")
script_version("08.02.2026")
script_url("https://github.com/melvin-costra/fish-helper.git")

------------------------------------ Libs  ------------------------------------
local ev = require "samp.events"
local imgui = require 'imgui'
local encoding = require 'encoding'
local memory = require 'memory'
encoding.default = 'CP1251'
u8 = encoding.UTF8
require "lib.moonloader"

------------------------------------ Variables  ------------------------------------
local CONFIG_PATH = "moonloader/config/configFish.json"
local ORIG_WAVE_1 = 0x0A75
local ORIG_WAVE_2 = 0x0424448B
local NOWAVES_1 = 0x9090
local NOWAVES_2 = 0x909090C3

local window = imgui.ImBool(false)
local catchingCoord = { x = 320, y = 100 }
local satiety, antiflood = -1, os.clock() * 1000
local isEating, isEquipping, isNetting = false, false, false
local loc = { ocean = "Океан", lowland = "Равнинные реки", mountain = "Горные реки" }
local sampObject = { deer = 19315, cow = 19833 }
local animalBlips = {} -- [objectId] = blip
local fishForSell = { name = nil, price = nil, amount = nil, isSelling = false }
local addrWave1 = 0x6E968A -- size 2
local addrWave2 = 0x6E7210 -- size 4
local wavesApplied = nil
local equipIndex = 0
local commandStates = {}

------------------------------------ Settings  ------------------------------------
local cfg = {
  fish = {
    ["Малоротый окунь"] = { min_price = 136, max_price = 380, location = loc.lowland, time = "Любое время" },
    ["Радужная форель"] = { min_price = 258, max_price = 509, location = loc.mountain, time = "с 06:00 до 19:00" },
    ["Лосось"] = { min_price = 327, max_price = 581, location = loc.lowland, time = "с 06:00 до 19:00" },
    ["Карп"] = { min_price = 114, max_price = 302, location = loc.mountain, time = "Любое время" },
    ["Сом"] = { min_price = 652, max_price = 1036, location = loc.lowland, time = "Любое время" },
    ["Тунец"] = { min_price = 657, max_price = 1227, location = loc.ocean, time = "с 06:00 до 19:00" },
    ["Лещ"] = { min_price = 175, max_price = 426, location = loc.lowland, time = "с 18:00 до 06:00" },
    ["Желтый судак"] = { min_price = 261, max_price = 512, location = loc.mountain, time = "с 12:00 до 06:00" },
    ["Барабулька"] = { min_price = 6250, max_price = 8823, location = loc.ocean, time = "с 06:00 до 19:00" },
    ["Угорь"] = { min_price = 634, max_price = 1215, location = loc.ocean, time = "с 16:00 до 06:00" },
    ["Кальмар"] = { min_price = 672, max_price = 1290, location = loc.ocean, time = "с 18:00 до 06:00" },
	  ["Осьминог"] = { min_price = 783, max_price = 1281, location = loc.ocean, time = "с 06:00 до 08:00" },
    ["Морской огурец"] = { min_price = 239, max_price = 483, location = loc.ocean, time = "с 06:00 до 19:00" },
    ["Мелкая камбала"] = { min_price = 296, max_price = 543, location = loc.ocean, time = "с 06:00 до 20:00" },
    ["Рыба-еж"] = { min_price = 708, max_price = 1319, location = loc.ocean, time = "с 12:00 до 16:00" },
	  ["Сардина"] = { min_price = 161, max_price = 409, location = loc.ocean, time = "с 06:00 до 19:00 (сети)" },
    ["Анчоус"] = { min_price = 161, max_price = 404, location = loc.ocean, time = "Любое время" },
    ["Щука"] = { min_price = 421, max_price = 668, location = loc.mountain, time = "Любое время" },
    ["Сельдь"] = { min_price = 131, max_price = 378, location = loc.ocean, time = "Любое время" },
    ["Тигровая форель"] = { min_price = 422, max_price = 660, location = loc.lowland, time = "с 06:00 до 19:00" },
    ["Голавль"] = { min_price = 176, max_price = 425, location = loc.mountain, time = "Любое время" },
  },
  settings = {
    enabled = false,
    auto_sell = true,
    sell_treshold_in_perc = 90,
    pick_fish_net = true,
    hunting = true,
    animal_markers = true,
    grib_eat = true,
    clicker_delay = 200,
    no_waves = false,
  }
}

function checkSavedCFG(savedCFG)
  if savedCFG.settings == nil and savedCFG.fish == nil then
    return false
  end
  local count1, count2 = 0, 0
  for key in pairs(cfg.settings) do
    if savedCFG.settings[key] == nil then
      return false
    end
    count1 = count1 + 1
  end
  for key in pairs(cfg.fish) do
    if savedCFG.fish[key] == nil then
      return false
    end
  end
  for key in pairs(savedCFG.settings) do
    count2 = count2 + 1
  end
  return count1 == count2
end

function saveCFG()
  local save = io.open(CONFIG_PATH, "w")
  if save then
    save:write(encodeJson(cfg))
    save:close()
  end
end

------------------------------------ Main  ------------------------------------
function main()
	if not isSampfuncsLoaded() or not isSampLoaded() then return end
	while not isSampAvailable() do wait(100) end
  if not doesDirectoryExist('moonloader/config') then createDirectory("moonloader/config") end
  if not doesFileExist(CONFIG_PATH) then
    saveCFG()
  else
    local file = io.open(CONFIG_PATH, 'r')
    if file then
      local fileCFG = decodeJson(file:read('*a'))
      if checkSavedCFG(fileCFG) then
        cfg = fileCFG
      end
    end
  end

  _, MyID = sampGetPlayerIdByCharHandle(PLAYER_PED)
	sampRegisterChatCommand("fh", function()
    window.v = not window.v
  end)
	sampRegisterChatCommand("fe", function()
    if getActiveInterior() ~= 0 or not isCharOnFoot(PLAYER_PED) then
      sendChatMessage("Нельзя оснащать удочку в интерьере, в машине или в вирт. мире")
      return
    end
    isEquipping = true
    equipIndex = 0
    sendCommand("/fish equip")
  end)
  sampRegisterChatCommand("fn", function()
    if getActiveInterior() ~= 0 or not isCharInWater(PLAYER_PED) then
      sendChatMessage("Установка сетей доступна только в воде в игровом мире")
      return
    end
    isNetting = true
    sendCommand("/fish net")
  end)

	while true do
		wait(0)
    imgui.Process = window.v
    if cfg.settings.enabled then
      fishing()
      eating()
      updateAnimalMarkers()
      selling()
      toggleWaves()
      equipping()
      netting()
    end
	end
end

------------------------------------ Fishing  ------------------------------------
function fishing()
  local fishing_float = { id = -1, y = -1 }
  local fish = { id = -1, y = -1 }
  local netting = { net_id = -1, fish_id = -1 }
  local hunting = { animal_id = -1, point_id = -1 }
  for i = 0, 2500 do
    if sampTextdrawIsExists(i) then
      local x, y = sampTextdrawGetPos(i)
      local text = sampTextdrawGetString(i)
      if string.find(text, "CATCHING") and x == catchingCoord.x and y == catchingCoord.y then
        sendKey(1024) -- нажать левый alt
        break
      end
      x, y = math.ceil(x), math.ceil(y)
      local _, _, color = sampTextdrawGetLetterSizeAndColor(i)
      local model = select(1, sampTextdrawGetModelRotationZoomVehColor(i))
      if color == 2685694719 and x == 422 then -- поплавок найден
        fishing_float.id = i
        fishing_float.y = y
      end
      if color == 4278190080 and x == 420 then -- рыба найдена
        fish.id = i
        fish.y = y
      end
      if cfg.settings.pick_fish_net then
        if model == 1600 or model == 1599 or model == 1604 or model == 19630 then
          netting.fish_id = i -- ид рыбы в сетях
        elseif model == 2945 and x == 228 and y == 117 then
          netting.net_id = i -- ид сетей
        end
      end
      if cfg.settings.hunting then
        if (model == sampObject.deer or model == sampObject.cow) and (x == 232 and y == 203) then
          hunting.animal_id = i -- ид животного
        elseif text == 'ld_beat:chit' and color == 4294967295 then
          hunting.point_id = i -- ид точки
        end
      end
    end
  end

  if fishing_float.id ~= -1 and fish.id ~= -1 then
    if fishing_float.y > fish.y then
      setGameKeyState(16, 255) -- нажимать пробел
    end
  end
  if os.clock() * 1000 - antiflood > cfg.settings.clicker_delay then
    if netting.net_id ~= -1 and netting.fish_id ~= -1 then
      clickTextdraw(netting.fish_id) -- кликнуть по рыбе в сетях
    end
    if hunting.animal_id ~= -1 and hunting.point_id ~= -1 then
      clickTextdraw(hunting.point_id) -- кликнуть по точке на животном
    end
  end
end

function eating()
  if not cfg.settings.grib_eat then return end
  if IDsatietyTextdraw == nil then
    for i = 0, 2500 do
      if sampTextdrawIsExists(i) then
        local x, y = sampTextdrawGetPos(i)
        local text = sampTextdrawGetString(i)
        if string.format('%.1f %.1f', x, y) == string.format('%.1f %.1f', 614.50030517578, 134.24440002441) then
          IDsatietyTextdraw = i
          _, satiety = text:match('~(%a)~(%d+)')
          break
        end
      end
    end
  end
  if not sampIsCursorActive() then
    if not isEating and tonumber(satiety) == 0 then
      isEating = true
    elseif isEating and tonumber(satiety) >= 50 then
      isEating = false
    end
    if isEating then
      printStringNow("~y~Eating... Press ~b~~h~R ~y~to stop", 300)
      if isKeyJustPressed(VK_R) then
        isEating = false
        cfg.settings.grib_eat = false
        printStringNow("", 10)
        saveCFG()
      end
      if (os.clock() * 1000) - antiflood > 1000 then
        sampSendChat("/grib eat")
      end
    end
  end
end

function updateAnimalMarkers()
  if not cfg.settings.animal_markers then return end
  local objects = getAllObjects()
  local seenObjects = {}
  for _, handle in ipairs(objects) do
    local model = getObjectModel(handle)
    local objectId = sampGetObjectSampIdByHandle(handle)
    if model == sampObject.deer or model == sampObject.cow then
      seenObjects[objectId] = true
      if not animalBlips[objectId] then
        local _, x, y, z = getObjectCoordinates(handle)
        local blip = addBlipForCoord(x, y, z)
        changeBlipScale(blip, 1)
        changeBlipColour(blip, 0xFF08ffe6)
        animalBlips[objectId] = blip
      end
    end
  end

  for id, blipHandle in pairs(animalBlips) do
    if not seenObjects[id] then
      if doesBlipExist(blipHandle) then 
        removeBlip(blipHandle) 
      end
      animalBlips[id] = nil
    end
  end
end

function selling()
  if fishForSell.isSelling then
    printStringNow("~y~Selling... Press ~b~~h~R ~y~to stop", 500)
    if isKeyJustPressed(VK_R) then
      fishForSell = getInitialFishForSell()
      cfg.settings.auto_sell = false
      saveCFG()
      printStringNow("", 10)
    end
  end
end

function toggleWaves()
  if not cfg.settings.enabled then return end

  local wantNoWaves = cfg.settings.no_waves

  if wavesApplied == wantNoWaves then
    return
  end

  if wantNoWaves then
    memory.write(addrWave1, NOWAVES_1, 2, false)
    memory.write(addrWave2, NOWAVES_2, 4, false)
  else
    memory.write(addrWave1, ORIG_WAVE_1, 2, false)
    memory.write(addrWave2, ORIG_WAVE_2, 4, false)
  end

  wavesApplied = wantNoWaves
end

function equipping()
  if isEquipping then
    printStringNow("~y~Equipping... Press ~b~~h~R ~y~to stop", 300)
    if isKeyJustPressed(VK_R) then
      isEquipping = false
      commandStates["/fish equip"] = nil
      printStringNow("", 10)
    end
  end
end

function netting()
  if isNetting then
    printStringNow("~y~Netting... Press ~b~~h~R ~y~to stop", 300)
    if isKeyJustPressed(VK_R) then
      isNetting = false
      commandStates["/fish net"] = nil
      printStringNow("", 10)
    end
  end
end

------------------------------------ Imgui  ------------------------------------
function imgui.OnDrawFrame()
  local sw, sh = getScreenResolution()
  local window_width = 280
  local window_height = 440

  local checkbox_sell_fish = imgui.ImBool(cfg.settings.auto_sell)
  local sell_treshold_in_perc = imgui.ImInt(cfg.settings.sell_treshold_in_perc)
  local checkbox_pick_fish_net = imgui.ImBool(cfg.settings.pick_fish_net)
  local checkbox_hunting = imgui.ImBool(cfg.settings.hunting)
  local checkbox_grib_eat = imgui.ImBool(cfg.settings.grib_eat)
  local input_delay = imgui.ImInt(cfg.settings.clicker_delay)
  local checkbox_animal_markers = imgui.ImBool(cfg.settings.animal_markers)
  local checkbox_no_waves = imgui.ImBool(cfg.settings.no_waves)

  imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
  imgui.SetNextWindowSize(imgui.ImVec2(window_width, window_height), imgui.Cond.FirstUseEver)

  imgui.Begin("Fish helper by melvin-costra", window, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

  if imgui.Button(u8("Вкл/Выкл")) then toggleScriptActivation() end
  imgui.SameLine(150)
  imgui.TextColoredRGB("Статус: " .. (cfg.settings.enabled and "{00B200}Включен" or "{FF0F00}Выключен"))
  imgui.NewLine()
  imgui.Text(u8("/fe - начать рыбалку"))
  imgui.Text(u8("/fn - установить сеть (на 24 часа)"))
  imgui.NewLine()
  if imgui.Checkbox(u8("Автоматическая продажа рыбы"), checkbox_sell_fish) then
    cfg.settings.auto_sell = checkbox_sell_fish.v
    fishForSell = getInitialFishForSell()
    saveCFG()
  end
  imgui.SameLine()
  ShowHelpMarker("Начинает продавать рыбу при открытии диалога продажи")
  if checkbox_sell_fish.v then
    if imgui.SliderInt(u8("%"), sell_treshold_in_perc, 0, 100) then
      cfg.settings.sell_treshold_in_perc = sell_treshold_in_perc.v
      fishForSell = getInitialFishForSell()
      saveCFG()
    end
    imgui.SameLine()
    ShowHelpMarker("% от максимальной цены")
  end
  imgui.NewLine()
  if imgui.Checkbox(u8("Убрать волны"), checkbox_no_waves) then cfg.settings.no_waves = checkbox_no_waves.v saveCFG() end
  imgui.SameLine()
  ShowHelpMarker("Убирает волны в океане чтобы не было тряски лодки")
  imgui.NewLine()
  if imgui.Checkbox(u8("Кликер для сетей"), checkbox_pick_fish_net) then cfg.settings.pick_fish_net = checkbox_pick_fish_net.v saveCFG() end
  imgui.SameLine()
  ShowHelpMarker("Автоматически кликает по рыбе при сборе сетей")
  imgui.NewLine()
  if imgui.Checkbox(u8("Кликер для охоты"), checkbox_hunting) then cfg.settings.hunting = checkbox_hunting.v saveCFG() end
  imgui.SameLine()
  ShowHelpMarker("Автоматически кликает по точкам при свежевании животного")
  imgui.NewLine()
  if imgui.Checkbox(u8("Маркеры животных"), checkbox_animal_markers) then
    cfg.settings.animal_markers = checkbox_animal_markers.v
    removeAnimalBlips()
    saveCFG()
  end
  imgui.SameLine()
  ShowHelpMarker("Добавляет маркеры животных на миникарте")
  imgui.NewLine()
  if imgui.Checkbox(u8("Поедание грибов"), checkbox_grib_eat) then cfg.settings.grib_eat = checkbox_grib_eat.v saveCFG() end
  imgui.SameLine()
  ShowHelpMarker("Автоматически кушает грибы когда сытность = 0")
  imgui.NewLine()

  imgui.Separator()
  imgui.NewLine()
  imgui.PushItemWidth(100)
  if imgui.InputInt(u8"Задержка кликеров (мс)", input_delay, 50) then cfg.settings.clicker_delay = input_delay.v saveCFG() end
  imgui.PopItemWidth()
  imgui.NewLine()
  if imgui.Button(u8("Информация о рыбе")) then showFishInfo() end
  imgui.SameLine()
  imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.63, 0.87, 1.0))
  imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.70, 0.95, 1.0))
  imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.10, 0.55, 0.80, 1.0))
  if imgui.Button(u8("Телеграм канал")) then os.execute('explorer "https://t.me/melvin_costra"') end
  imgui.PopStyleColor(3)

  imgui.End()
end

function apply_custom_style()
  local style = imgui.GetStyle()

  style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
end

function imgui.TextColoredRGB(text)
  local style = imgui.GetStyle()
  local colors = style.Colors
  local ImVec4 = imgui.ImVec4

  local explode_argb = function(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF)
    local r = bit.band(bit.rshift(argb, 16), 0xFF)
    local g = bit.band(bit.rshift(argb, 8), 0xFF)
    local b = bit.band(argb, 0xFF)
    return a, r, g, b
  end

  local getcolor = function(color)
    if color:sub(1, 6):upper() == 'SSSSSS' then
      local r, g, b = colors[1].x, colors[1].y, colors[1].z
      local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
      return ImVec4(r, g, b, a / 255)
    end
    local color = type(color) == 'string' and tonumber(color, 16) or color
    if type(color) ~= 'number' then return end
    local r, g, b, a = explode_argb(color)
    return imgui.ImColor(r, g, b, a):GetVec4()
  end

  local render_text = function(text_)
    for w in text_:gmatch('[^\r\n]+') do
      local text, colors_, m = {}, {}, 1
      w = w:gsub('{(......)}', '{%1FF}')
      while w:find('{........}') do
        local n, k = w:find('{........}')
        local color = getcolor(w:sub(n + 1, k - 1))
        if color then
          text[#text], text[#text + 1] = w:sub(m, n - 1), w:sub(k + 1, #w)
          colors_[#colors_ + 1] = color
          m = n
        end
        w = w:sub(1, n - 1) .. w:sub(k + 1, #w)
      end
      if text[0] then
        for i = 0, #text do
          imgui.TextColored(colors_[i] or colors[1], u8(text[i]))
          imgui.SameLine(nil, 0)
        end
        imgui.NewLine()
      else imgui.Text(u8(w)) end
    end
  end

  render_text(text)
end

------------------------------------ Utils  ------------------------------------
function toggleScriptActivation()
  cfg.settings.enabled = not cfg.settings.enabled
  saveCFG()
  fishForSell = getInitialFishForSell()
  removeAnimalBlips()
  commandStates = {}
end

function sendKey(key)
  local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
  local data = allocateMemory(68)
  sampStorePlayerOnfootData(myId, data)
  setStructElement(data, 4, 2, key, false)
  sampSendOnfootData(data)
  freeMemory(data)
end

function sendCommand(cmd)
  if commandStates[cmd] then
    return
  end
  commandStates[cmd] = true
  lua_thread.create(function()
    repeat
      wait(0)
      if os.clock() * 1000 - antiflood > 500 then
        sampSendChat(cmd)
        antiflood = os.clock() * 1000
      end
    until not commandStates[cmd]
  end)
end

function showFishInfo()
  for key, value in pairs(cfg.fish) do
    local text = string.format("%s | {FF0F00}%s {FFFFFF}| {00B200}%s {FFFFFF}| %s | %s", key, value.min_price, value.max_price, value.location, value.time)
    sendChatMessage(text)
  end
end

function ShowHelpMarker(param)
  imgui.TextDisabled('(?)')
  if imgui.IsItemHovered() then
    imgui.BeginTooltip()
    imgui.PushTextWrapPos(imgui.GetFontSize() * 35.0)
    imgui.TextUnformatted(u8(param))
    imgui.PopTextWrapPos()
    imgui.EndTooltip()
  end
end

function format_number(n)
  local formatted = tostring(n)
  local k
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1 %2")
    if k == 0 then break end
  end
  return formatted
end

function onWindowMessage(m, p)
  if p == VK_ESCAPE and window.v then
    consumeWindowMessage()
    window.v = false
  end
end

function escape_string(str)
  return str:gsub(".", function(c)
    local b = string.byte(c)
    if c == "\\" then
      return "\\\\"
    elseif c == "\n" then
      return "\\n"
    elseif c == "\t" then
      return "\\t"
    elseif c == "\r" then
      return "\\r"
    else
      return c
    end
  end)
end

function clickTextdraw(textdrawId)
  sampSendClickTextdraw(textdrawId)
  antiflood = os.clock() * 1000
end

function removeAnimalBlips()
  for _, blipHandle in pairs(animalBlips) do
    if doesBlipExist(blipHandle) then removeBlip(blipHandle) end
  end
  animalBlips = {}
end

function getInitialFishForSell()
  return { name = nil, price = nil, amount = nil, isSelling = false }
end

function sendChatMessage(text)
  sampAddChatMessage("{0088CC}[FH]: {FFFFFF}" .. text, -1)
end

------------------------------------ Events  ------------------------------------
function ev.onServerMessage(c, text)
  if text == " Не флуди!" or text == " В AFK ввод команд заблокирован" then
    antiflood = os.clock() * 1000 + 1500
	end
  if text == " У вас нет этой еды" then
    cfg.settings.grib_eat = false
  end

  if cfg.settings.enabled then
    if isEquipping then
      if text == " [Рыбалка] {FFFFFF}Необходимо покинуть помещение" then
        isEquipping = false
      elseif text == " [Рыбалка] {FFFFFF}У вас отсутствуют удочки" then
        isEquipping = false
      elseif text == " [Рыбалка] {FFFFFF}У вас отсутствуют снасти" then
        equipIndex = equipIndex + 1
        sendCommand("/fish equip")
      elseif text == " [Рыбалка] {FFFFFF}У вас отсутствуют наживки" then
        isEquipping = false
        sendKey(1024)
      elseif text == " [Рыбалка] {FFFFFF}Установка снастей доступна только на Иридиевую удочку"
      or text == " [Рыбалка] {FFFFFF}Для использования наживки необходимо экипировать Стеклопластиковую удочку (или лучше)"
      then
        equipIndex = equipIndex + 1
      end
    end

    if text == " [Рыбалка] {FFFFFF}У вас сломалась удочка"
    or text == " [Рыбалка] {FFFFFF}У вас сломалась снасть"
    or text == " [Рыбалка] {FFFFFF}У вас сломалась наживка"
    then
      if not isEquipping then
        isEquipping = true
        equipIndex = 0
        sendCommand("/fish equip")
      end
    end

    if isNetting then
      if text == " [Рыбалка] {FFFFFF}У вас уже установлено максимальное число сетей" then
        isNetting = false
      end
    end
  end
end

function ev.onSendChat(text)
	antiflood = os.clock() * 1000
end

function ev.onSendCommand(cmd)
	antiflood = os.clock() * 1000
end

function ev.onTextDrawSetString(id, text)
	if IDsatietyTextdraw ~= nil then
		if IDsatietyTextdraw == id then
			_, satiety = text:match('~(%a)~(%d+)')
		end
	end
end

function ev.onShowDialog(id, style, title, btn1, btn2, text)
  if cfg.settings.enabled then
    if cfg.settings.auto_sell then
      if style == 0 and title:find("Продажа рыбы") then
        if fishForSell.isSelling then
          sampSendDialogResponse(id, 1, 0, "")
          return false
        end
      end
  
      if style == 1 and title:find("Продажа рыбы") then
        if fishForSell.isSelling then
          sampSendDialogResponse(id, 1, 1, fishForSell.amount)
          return false
        end
      end
  
      if style == 5 and title:find('Рыболовные товары') then
        fishForSell = getInitialFishForSell()
        local isSellingWindow = false
        local formattedText = text:match("[^\n]+")
        local i = 0
        for line in text:gmatch("[^\n]+") do
          local raw_text = escape_string(line)
          local name, price, amount = raw_text:match("([- А-Яа-яёЁ]+)\\t{6AB1FF}%$(%d+)\\t{FFFFFF}(%d+%.%d+)")
          if name and price and amount then
            formattedText = formattedText .. "\n" .. name .. "\t{6AB1FF}$" .. price .. "{FFFFFF} | {00B200}$" .. cfg.fish[name].max_price .. "\t{FFFFFF}" .. amount
            isSellingWindow = true
            amount = math.floor(amount)
            price = tonumber(price)
            -- Обновляем цены в конфиге
            if price > cfg.fish[name].max_price then
              cfg.fish[name].max_price = price
              saveCFG()
            elseif price < cfg.fish[name].min_price then
              cfg.fish[name].min_price = price
              saveCFG()
            end
            if amount > 0 then
              local min = cfg.fish[name].min_price
              local max = cfg.fish[name].max_price
              local percent_diff = ((price - min) / (max - min)) * 100
              if percent_diff >= cfg.settings.sell_treshold_in_perc then
                fishForSell.name = name
                fishForSell.price = price
                fishForSell.amount = math.floor(amount)
                fishForSell.isSelling = true
                sampSendDialogResponse(id, 1, i, "")
                break
              end
            end
            i = i + 1
          end
        end
        if isSellingWindow then
          if not fishForSell.isSelling then
            sendChatMessage("Нету рыбы соответствующей указаному ценовому порогу")
          end
          sampShowDialog(id, title, formattedText, btn1, btn2, style)
          sampSetDialogClientside(false)
          return false
        end
      end
    end

    if isEquipping then
      if style == 4 then
        if title:find("Экипировка {6AB1FF}| Рыбалка") then
          commandStates["/fish equip"] = nil
          local isEquipped = true
          local i = 0
          for line in text:gmatch("[^\n]+") do
            if i >= equipIndex then
              local name, value = line:match("(.+)\t{FFFFFF}(.+)")
              if name and value then
                if value:find("Не выбрано") then
                  sampSendDialogResponse(id, 1, i, "")
                  isEquipped = false
                  equipIndex = i
                  break
                end
              end
            end
            i = i + 1
          end
          if isEquipped then
            isEquipping = false
            sendKey(1024)
            return false
          end
        elseif title:find("Список удочек {6AB1FF}| Рыбалка")
        or title:find("Список снастей {6AB1FF}| Рыбалка")
        or title:find("Список наживок {6AB1FF}| Рыбалка") then
          local i = 0
          for _ in text:gmatch("[^\n]+") do
            i = i + 1
          end
          sampSendDialogResponse(id, 1, i - 1, "")
        end

        return false
      end
    end

    if isNetting then
      if style == 2 then
        if title == "{FFFFFF} Меню {6AB1FF}| Рыболовные сети" then
          commandStates["/fish net"] = nil
          local amount = text:match("[^\n].+В наличии: (%d+)")
          if amount and tonumber(amount) > 0 then
            sampSendDialogResponse(id, 1, 0, "")
          else
            isNetting = false
            sendChatMessage("У тебя нету рыболовных сетей")
          end
          return false
        end
        
        if title == "{FFFFFF} Установка сети {6AB1FF}| Рыболовные сети" then
          local i = 0
          for _ in text:gmatch("[^\n]+") do
            i = i + 1
          end
          sampSendDialogResponse(id, 1, i - 1, "")
          isNetting = false
          return false
        end
      end
    end
  end
end

function onScriptTerminate()
  fishForSell = getInitialFishForSell()
  commandStates = {}
  removeAnimalBlips()
end
