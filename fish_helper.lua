script_name("Fish helper")
script_version("20.10.2026")
script_author("melvin-costra")
script_url("https://github.com/melvin-costra/fish-helper.git")

------------------------------------ Libs  ------------------------------------
local ev = require "samp.events"
local imgui = require 'imgui'
local encoding = require 'encoding'
local memory = require 'memory'
local vkeys = require 'vkeys'
local font_flag = require('moonloader').font_flag
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local function wrapToGame(fnName)
  local original = _G[fnName]
  _G[fnName] = function(...)
    local n = select("#", ...)
    local args = {...}
    for i = 1, n do
      if type(args[i]) == "string" then
        args[i] = u8:decode(args[i])
      end
    end
    return original(unpack(args, 1, n))
  end
end
wrapToGame("sampAddChatMessage")
wrapToGame("sampSendChat")
wrapToGame("sampProcessChatInput")

------------------------------------ Variables  ------------------------------------
local CONFIG_PATH = "moonloader/config/configFish.json"
local MIGRATION = "19.10.2026"
local ORIG_WAVE_1 = 0x0A75
local ORIG_WAVE_2 = 0x0424448B
local NOWAVES_1 = 0x9090
local NOWAVES_2 = 0x909090C3

local window = imgui.ImBool(false)
local catchingCoord = { x = 320, y = 100 }
local antiflood = os.clock() * 1000
local isEquipping, isNetting = false, false
local loc = { ocean = "Океан", lowland = "Равнинные реки", mountain = "Горные реки" }
local sampObject = {
  deer = { model = 19315, color = 0xefff08e6 },
  cow = { model = 19833, color = 0x9c08ffe6 },
}
local animalBlips = {} -- [objectId] = blip
local fishForSell = { name = nil, price = nil, amount = nil, isSelling = false }
local addrWave1 = 0x6E968A -- size 2
local addrWave2 = 0x6E7210 -- size 4
local wavesApplied = nil
local equipIndex = 0
local commandStates = {}
local seenObjects = {}
local fontHud = nil
local hudMoving = false
local pickingCancelKey = false

local caughtChanges = {}
local sessionCaught = {}
local sessionCoupons = {}
local COUPON_TYPES = { "Бесплатный скин", "Автомобиль [A]", "Автомобиль [B]" }
local huntingChanges = {}
local soldHuntingItems = {
  ["шкур дикой коровы"] = "Шкура дикой коровы",
  ["шкур дикого оленя"] = "Шкура оленя",
}
local SKIN_SALE_COOLDOWN = 3600

------------------------------------ Settings  ------------------------------------
local cfg = {
  fish = {
    ["Малоротый окунь"] = { min_price = 136, max_price = 382, caught = 0.0, location = loc.lowland, time = "Любое время" },
    ["Радужная форель"] = { min_price = 258, max_price = 509, caught = 0.0, location = loc.mountain, time = "с 06:00 до 19:00" },
    ["Лосось"] = { min_price = 327, max_price = 581, caught = 0.0, location = loc.lowland, time = "с 06:00 до 19:00" },
    ["Карп"] = { min_price = 110, max_price = 305, caught = 0.0, location = loc.mountain, time = "Любое время" },
    ["Сом"] = { min_price = 651, max_price = 1036, caught = 0.0, location = loc.lowland, time = "Любое время" },
    ["Тунец"] = { min_price = 657, max_price = 1227, caught = 0.0, location = loc.ocean, time = "с 06:00 до 19:00" },
    ["Лещ"] = { min_price = 171, max_price = 426, caught = 0.0, location = loc.lowland, time = "с 18:00 до 06:00" },
    ["Желтый судак"] = { min_price = 261, max_price = 514, caught = 0.0, location = loc.mountain, time = "с 12:00 до 06:00" },
    ["Барабулька"] = { min_price = 6250, max_price = 8823, caught = 0.0, location = loc.ocean, time = "с 06:00 до 19:00" },
    ["Угорь"] = { min_price = 631, max_price = 1228, caught = 0.0, location = loc.ocean, time = "с 16:00 до 06:00" },
    ["Кальмар"] = { min_price = 664, max_price = 1290, caught = 0.0, location = loc.ocean, time = "с 18:00 до 06:00" },
	  ["Осьминог"] = { min_price = 783, max_price = 1283, caught = 0.0, location = loc.ocean, time = "с 06:00 до 08:00" },
    ["Морской огурец"] = { min_price = 239, max_price = 483, caught = 0.0, location = loc.ocean, time = "с 06:00 до 19:00" },
    ["Мелкая камбала"] = { min_price = 296, max_price = 543, caught = 0.0, location = loc.ocean, time = "с 06:00 до 20:00" },
    ["Рыба-еж"] = { min_price = 708, max_price = 1319, caught = 0.0, location = loc.ocean, time = "с 12:00 до 16:00" },
	  ["Сардина"] = { min_price = 157, max_price = 409, caught = 0.0, location = loc.ocean, time = "с 06:00 до 19:00 (сети)" },
    ["Анчоус"] = { min_price = 161, max_price = 414, caught = 0.0, location = loc.ocean, time = "Любое время" },
    ["Щука"] = { min_price = 421, max_price = 668, caught = 0.0, location = loc.mountain, time = "Любое время" },
    ["Сельдь"] = { min_price = 127, max_price = 378, caught = 0.0, location = loc.ocean, time = "Любое время" },
    ["Тигровая форель"] = { min_price = 417, max_price = 666, caught = 0.0, location = loc.lowland, time = "с 06:00 до 19:00" },
    ["Голавль"] = { min_price = 172, max_price = 425, caught = 0.0, location = loc.mountain, time = "Любое время" },
  },
  settings = {
    enabled = false,
    auto_sell = true,
    sell_treshold_in_perc = 90,
    pick_fish_net = true,
    hunting = true,
    animal_markers = true,
    clicker_delay = 200,
    no_waves = false,
    cancel_key = 78, -- N
  },
  hunting_items = {
    ["Мясо оленя"] = { amount = 0, maximum = 1000 },
    ["Мясо дикой коровы"] = { amount = 0, maximum = 1000 },
    ["Шкура оленя"] = { amount = 0, maximum = 15 },
    ["Шкура дикой коровы"] = { amount = 0, maximum = 15 },
  },
  last_skin_sale = 0,
  ui = {
    show_hud = false,
    show_hunting_hud = false,
    pos_x = 20,
    pos_y = 220,
    hunting_pos_x = 20,
    hunting_pos_y = 400,
    font_size = 9,
  },
  migration = MIGRATION,
}

function saveCFG()
  local save = io.open(CONFIG_PATH, "w")
  if save then
    save:write(encodeJson(cfg))
    save:close()
  end
end

local function setCaughtAmount(name, amount)
  local fish = cfg.fish[name]
  if not fish then return end

  local previous = tonumber(fish.caught) or 0.00
  amount = tonumber(amount) or 0.00
  local difference = amount - previous
  fish.caught = amount
  if difference ~= 0 then
    caughtChanges[name] = { amount = difference, expires = os.clock() + 3 }
  end
end

local function setHuntingAmount(name, amount)
  local item = cfg.hunting_items[name]
  if not item then return end

  local previous = tonumber(item.amount) or 0
  amount = tonumber(amount) or 0
  local difference = amount - previous
  item.amount = amount
  if difference ~= 0 then
    huntingChanges[name] = { amount = difference, expires = os.clock() + 3 }
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
      local ok, fileCFG = pcall(decodeJson, file:read('*a'))
      file:close()
      if ok and type(fileCFG) == "table" and fileCFG.migration == MIGRATION then
        cfg = fileCFG
        saveCFG()
      else
        saveCFG()
      end
    else
      saveCFG()
    end
  end

	sampRegisterChatCommand("fh", function()
    window.v = not window.v
  end)
	sampRegisterChatCommand("fe", function()
    if not cfg.settings.enabled then return end
    if getActiveInterior() ~= 0 or not isCharOnFoot(PLAYER_PED) then
      sendChatMessage("Нельзя оснащать удочку в интерьере, в машине или в вирт. мире")
      return
    end
    isEquipping = true
    equipIndex = 0
    sendCommand("/fish equip")
  end)
  sampRegisterChatCommand("fn", function()
    if not cfg.settings.enabled then return end
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
    if not window.v then pickingCancelKey = false end
    if pickingCancelKey then
      if isKeyJustPressed(VK_ESCAPE) or isKeyJustPressed(VK_RETURN) then
        pickingCancelKey = false
      else
        for _, v in pairs(vkeys) do
          if isKeyJustPressed(v) then
            cfg.settings.cancel_key = v
            pickingCancelKey = false
            saveCFG()
            sendChatMessage("Клавиша отмены изменена на: {6AB1FF}" .. vkeys.id_to_name(v))
            break
          end
        end
      end
    end
    if cfg.settings.enabled then
      fishing()
      updateAnimalMarkers()
      selling()
      toggleWaves()
      equipping()
    end
    if hudMoving then
      local x, y = getCursorPos()
      if hudMoving == "hunting" then
        cfg.ui.hunting_pos_x, cfg.ui.hunting_pos_y = x, y
      else
        cfg.ui.pos_x, cfg.ui.pos_y = x, y
      end
      if isKeyJustPressed(1) then
        hudMoving = false
        saveCFG()
        sendChatMessage("Позиция HUD сохранена")
      end
    end
    if cfg.ui.show_hud or hudMoving == "fish" then drawFishHud() end
    if cfg.ui.show_hunting_hud or hudMoving == "hunting" then drawHuntingHud() end
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
        if (model == sampObject.deer.model or model == sampObject.cow.model) and (x == 232 and y == 203) then
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

function handleAnimalMarker(objectId, handle, color)
  if objectId == nil then return end
  seenObjects[objectId] = true

  if animalBlips[objectId] then
    return
  end

  local _, x, y, z = getObjectCoordinates(handle)
  local blip = addBlipForCoord(x, y, z)
  changeBlipScale(blip, 1)
  changeBlipColour(blip, color)

  animalBlips[objectId] = blip
end

function updateAnimalMarkers()
  if not cfg.settings.animal_markers then return end
  local objects = getAllObjects()
  seenObjects = {}
  for _, handle in ipairs(objects) do
    local model = getObjectModel(handle)
    local objectId = sampGetObjectSampIdByHandle(handle)
    if model == sampObject.deer.model then
      handleAnimalMarker(objectId, handle, sampObject.deer.color)
    elseif model == sampObject.cow.model then
      handleAnimalMarker(objectId, handle, sampObject.cow.color)
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
    local keyLabel = vkeys.id_to_name(cfg.settings.cancel_key)
    printStringNow("~y~Selling... Press ~b~~h~" .. keyLabel .. " ~y~to stop", 500)
    if isKeyJustPressed(cfg.settings.cancel_key) then
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

  applyWaves(wantNoWaves)
end

function applyWaves(noWaves)
  if noWaves then
    memory.write(addrWave1, NOWAVES_1, 2, false)
    memory.write(addrWave2, NOWAVES_2, 4, false)
  else
    memory.write(addrWave1, ORIG_WAVE_1, 2, false)
    memory.write(addrWave2, ORIG_WAVE_2, 4, false)
  end

  wavesApplied = noWaves
end

function restoreWaves()
  if wavesApplied == true then
    applyWaves(false)
  end
end

function equipping()
  if isEquipping then
    local keyLabel = vkeys.id_to_name(cfg.settings.cancel_key)
    printStringNow("~y~Equipping... Press ~b~~h~" .. keyLabel .. " ~y~to stop", 300)
    if isKeyJustPressed(cfg.settings.cancel_key) then
      isEquipping = false
      commandStates["/fish equip"] = nil
      printStringNow("", 10)
    end
  end
end

------------------------------------ Imgui  ------------------------------------
function imgui.OnDrawFrame()
  local sw, sh = getScreenResolution()
  local window_width = 280
  local window_height = 540

  local checkbox_sell_fish = imgui.ImBool(cfg.settings.auto_sell)
  local sell_treshold_in_perc = imgui.ImInt(cfg.settings.sell_treshold_in_perc)
  local checkbox_pick_fish_net = imgui.ImBool(cfg.settings.pick_fish_net)
  local checkbox_hunting = imgui.ImBool(cfg.settings.hunting)
  local input_delay = imgui.ImInt(cfg.settings.clicker_delay)
  local checkbox_animal_markers = imgui.ImBool(cfg.settings.animal_markers)
  local checkbox_no_waves = imgui.ImBool(cfg.settings.no_waves)
  local checkbox_show_fish_hud = imgui.ImBool(cfg.ui.show_hud)
  local checkbox_show_hunting_hud = imgui.ImBool(cfg.ui.show_hunting_hud)
  local hud_font_size = imgui.ImInt(cfg.ui.font_size)

  imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
  imgui.SetNextWindowSize(imgui.ImVec2(window_width, window_height), imgui.Cond.FirstUseEver)

  imgui.Begin("Fish helper by melvin-costra", window, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

  if imgui.Button("Вкл/Выкл") then toggleScriptActivation() end
  imgui.SameLine(150)
  imgui.TextColoredRGB("Статус: " .. (cfg.settings.enabled and "{00B200}Включен" or "{FF0F00}Выключен"))
  imgui.NewLine()
  imgui.Text("/fe - начать рыбалку")
  imgui.Text("/fn - установить сеть (на 24 часа)")
  imgui.NewLine()
  imgui.TextSection("Рыбалка")
  if imgui.Checkbox("Автоматическая продажа рыбы", checkbox_sell_fish) then
    cfg.settings.auto_sell = checkbox_sell_fish.v
    fishForSell = getInitialFishForSell()
    saveCFG()
  end
  imgui.SameLine()
  ShowHelpMarker("Начинает продавать рыбу при открытии диалога продажи")
  if checkbox_sell_fish.v then
    if imgui.SliderInt("%", sell_treshold_in_perc, 0, 100) then
      cfg.settings.sell_treshold_in_perc = sell_treshold_in_perc.v
      fishForSell = getInitialFishForSell()
      saveCFG()
    end
    imgui.SameLine()
    ShowHelpMarker("% от максимальной цены")
  end
  if imgui.Checkbox("Убрать волны", checkbox_no_waves) then cfg.settings.no_waves = checkbox_no_waves.v saveCFG() end
  imgui.SameLine()
  ShowHelpMarker("Убирает волны в океане чтобы не было тряски лодки")
  if imgui.Checkbox("Кликер для сетей", checkbox_pick_fish_net) then cfg.settings.pick_fish_net = checkbox_pick_fish_net.v saveCFG() end
  imgui.SameLine()
  ShowHelpMarker("Автоматически кликает по рыбе при сборе сетей")
  if imgui.Checkbox("Показывать пойманную рыбу", checkbox_show_fish_hud) then
    cfg.ui.show_hud = checkbox_show_fish_hud.v
    saveCFG()
  end
  imgui.SameLine()
  ShowHelpMarker("Показывает на экране список пойманной рыбы с её весом\nДля обновления данных введи команду /fish inv")
  if checkbox_show_fish_hud.v then
    if imgui.Button("Сменить позицию HUD") then
      hudMoving = "fish"
    end
    imgui.SameLine()
  end
  imgui.NewLine()
  imgui.TextSection("Охота")
  if imgui.Checkbox("Кликер для охоты", checkbox_hunting) then cfg.settings.hunting = checkbox_hunting.v saveCFG() end
  imgui.SameLine()
  ShowHelpMarker("Автоматически кликает по точкам при свежевании животного")
  if imgui.Checkbox("Маркеры животных", checkbox_animal_markers) then
    cfg.settings.animal_markers = checkbox_animal_markers.v
    removeAnimalBlips()
    saveCFG()
  end
  imgui.SameLine()
  ShowHelpMarker("Добавляет маркеры животных на миникарте")
  if imgui.Checkbox("Показывать мясо и шкуры", checkbox_show_hunting_hud) then
    cfg.ui.show_hunting_hud = checkbox_show_hunting_hud.v
    saveCFG()
  end
  imgui.SameLine()
  ShowHelpMarker("Показывает количество мяса и шкур\nВведи команду /inventory для обновления данных")
  if checkbox_show_hunting_hud.v then
    if imgui.Button("Сменить позицию HUD охоты") then hudMoving = "hunting" end
    imgui.SameLine()
  end
  imgui.NewLine()
  imgui.TextSection("Общее")

  imgui.PushItemWidth(100)
  if imgui.SliderInt("Размер шрифта HUD", hud_font_size, 6, 12) then
    cfg.ui.font_size = hud_font_size.v
    fontHud = renderCreateFont("Segoe UI Black", cfg.ui.font_size, font_flag.SHADOW)
    saveCFG()
  end
  if imgui.InputInt("Задержка кликеров (мс)", input_delay, 50) then cfg.settings.clicker_delay = input_delay.v saveCFG() end
  imgui.PopItemWidth()

  local cancelKeyName = vkeys.id_to_name(cfg.settings.cancel_key)
  if imgui.Button(pickingCancelKey and "Нажми клавишу..." or ("Клавиша отмены: " .. cancelKeyName)) then
    pickingCancelKey = not pickingCancelKey
  end
  imgui.SameLine()
  ShowHelpMarker("Клавиша для остановки действия\nESC или повторный клик — отменить выбор")

  imgui.NewLine()
  if imgui.Button("Информация о рыбе") then showFishInfo() end
  imgui.SameLine()
  imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.63, 0.87, 1.0))
  imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.70, 0.95, 1.0))
  imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.10, 0.55, 0.80, 1.0))
  if imgui.Button("Телеграм канал") then os.execute('explorer "https://t.me/melvin_costra"') end
  imgui.PopStyleColor(3)

  imgui.End()
end

function imgui.TextSection(text)
  local style = imgui.GetStyle()
  local drawList = imgui.GetWindowDrawList()
  local fontSize = imgui.GetFontSize()
  local accentColor = imgui.ImColor(227, 181, 74, 255):GetU32()

  local textPos = imgui.GetCursorScreenPos()
  local textSize = imgui.CalcTextSize(text)
  drawList:AddText(textPos, accentColor, text)

  local lineY = textPos.y + fontSize / 2
  local lineX1 = textPos.x + textSize.x + style.ItemSpacing.x
  local lineX2 = textPos.x + imgui.GetWindowWidth() - style.WindowPadding.x * 2
  if lineX2 > lineX1 then
    drawList:AddLine(imgui.ImVec2(lineX1, lineY), imgui.ImVec2(lineX2, lineY), imgui.ImColor(128, 128, 128, 160):GetU32(), 1.0)
  end

  imgui.Dummy(imgui.ImVec2(0, fontSize + style.ItemSpacing.y / 2))
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
          imgui.TextColored(colors_[i] or colors[1], text[i])
          imgui.SameLine(nil, 0)
        end
        imgui.NewLine()
      else imgui.Text(w) end
    end
  end

  render_text(text)
end

------------------------------------ Fish HUD  ------------------------------------
local sortedFishNames = nil

function getSortedFishNames()
  if not sortedFishNames then
    sortedFishNames = {}
    for name in pairs(cfg.fish) do
      sortedFishNames[#sortedFishNames + 1] = name
    end
    table.sort(sortedFishNames)
  end
  return sortedFishNames
end

function drawFishHud()
  if not fontHud then fontHud = renderCreateFont("Segoe UI Black", cfg.ui.font_size, font_flag.SHADOW) end

  local names = getSortedFishNames()
  local fontH = renderGetFontDrawHeight(fontHud)
  local rowH = fontH + 2
  local pad = 8
  local minGap = 12
  local items, listWidth, nameColumnWidth, sessionColumnWidth, amountColumnWidth, changeColumnWidth = {}, 0, 0, 0, 0, 0
  for _, name in ipairs(names) do
    local nameWidth = renderGetFontDrawTextLength(fontHud, u8:decode(name))
    nameColumnWidth = math.max(nameColumnWidth, nameWidth)
  end
  nameColumnWidth = nameColumnWidth + 10
  for _, name in ipairs(names) do
    local amount = cfg.fish[name].caught or 0.00
    if amount > 0 then
      local item = {
        name = u8:decode(name),
        session = string.format("%.2f", sessionCaught[name] or 0.00),
        amount = string.format("%.2f", amount),
      }
      local change = caughtChanges[name]
      if change and change.expires > os.clock() then
        item.change = string.format("%s%.2f", change.amount > 0 and "+" or "", change.amount)
        item.changeColor = change.amount > 0 and "{00B200}" or "{FF4040}"
        changeColumnWidth = math.max(changeColumnWidth, renderGetFontDrawTextLength(fontHud, item.change))
      elseif change then
        caughtChanges[name] = nil
      end
      item.nameW = renderGetFontDrawTextLength(fontHud, item.name)
      item.sessionW = renderGetFontDrawTextLength(fontHud, item.session)
      item.amountW = renderGetFontDrawTextLength(fontHud, item.amount)
      items[#items + 1] = item
      sessionColumnWidth = math.max(sessionColumnWidth, item.sessionW)
      amountColumnWidth = math.max(amountColumnWidth, item.amountW)
    end
  end

  listWidth = nameColumnWidth + minGap + sessionColumnWidth + minGap + amountColumnWidth
  if changeColumnWidth > 0 then
    listWidth = listWidth + minGap + changeColumnWidth
  end

  if #items == 0 then
    for _, message in ipairs({ "Нету пойманой рыбы", "Введи /fish inv чтобы обновить" }) do
      local item = { name = u8:decode(message) }
      item.nameW = renderGetFontDrawTextLength(fontHud, item.name)
      items[#items + 1] = item
      if item.nameW > listWidth then listWidth = item.nameW end
    end
  end

  local couponRows, couponNameWidth, couponCountWidth = {}, 0, 0
  for _, coupon in ipairs(COUPON_TYPES) do
    local count = sessionCoupons[coupon] or 0
    if count > 0 then
      local row = { name = u8:decode(coupon), count = tostring(count) }
      row.nameW = renderGetFontDrawTextLength(fontHud, row.name)
      row.countW = renderGetFontDrawTextLength(fontHud, row.count)
      couponNameWidth = math.max(couponNameWidth, row.nameW)
      couponCountWidth = math.max(couponCountWidth, row.countW)
      couponRows[#couponRows + 1] = row
    end
  end

  local title = u8:decode("Пойманая рыба  (Сейчас | Всего)")
  local titleW = renderGetFontDrawTextLength(fontHud, title)
  local couponsTitle = u8:decode("Пойманые купоны")
  local couponsTitleW = renderGetFontDrawTextLength(fontHud, couponsTitle)
  local couponsEmpty = u8:decode("Пусто")
  local couponNameCol = math.max(couponNameWidth, nameColumnWidth)
  local couponsListWidth = #couponRows > 0 and (couponNameCol + minGap + couponCountWidth) or renderGetFontDrawTextLength(fontHud, couponsEmpty)
  local hint = hudMoving == "fish" and u8:decode("ЛКМ - подтвердить позицию") or nil
  local hintW = hint and renderGetFontDrawTextLength(fontHud, hint) or 0

  local panelW = math.max(listWidth + pad * 2, titleW + pad * 2, hintW + pad * 2, couponsTitleW + pad * 2, couponsListWidth + pad * 2)

  local x, y = cfg.ui.pos_x, cfg.ui.pos_y

  local tx = x + pad
  local ty = y + pad
  renderFontDrawText(fontHud, "{E3B54A}" .. title, tx, ty, 0xFFFFFFFF)

  ty = ty + fontH + 2
  renderDrawLine(tx, ty, x + panelW - pad, ty, 1, 0xFF5A5A5A)
  ty = ty + 4

  for i, item in ipairs(items) do
    local iy = ty + (i - 1) * rowH
    renderFontDrawText(fontHud, "{FFFFFF}" .. item.name, tx, iy, 0xFFFFFFFF)
    if item.amount then
      local sessionX = tx + nameColumnWidth + minGap
      local amountX = sessionX + sessionColumnWidth + minGap
      renderFontDrawText(fontHud, "{6AB1FF}" .. item.session, sessionX, iy, 0xFFFFFFFF)
      renderFontDrawText(fontHud, "{E3B54A}" .. item.amount, amountX, iy, 0xFFFFFFFF)
      if item.change then
        renderFontDrawText(fontHud, item.changeColor .. item.change, amountX + amountColumnWidth + minGap, iy, 0xFFFFFFFF)
      end
    end
  end

  if hint then
    renderFontDrawText(fontHud, "{E3B54A}" .. hint, tx, ty + #items * rowH + 2, 0xFFFFFFFF)
  end

  local couponsY = ty + #items * rowH + 2
  if hint then couponsY = couponsY + rowH + 2 end
  couponsY = couponsY + 4

  renderFontDrawText(fontHud, "{E3B54A}" .. couponsTitle, tx, couponsY, 0xFFFFFFFF)
  couponsY = couponsY + fontH + 2
  renderDrawLine(tx, couponsY, x + panelW - pad, couponsY, 1, 0xFF5A5A5A)
  couponsY = couponsY + 4

  if #couponRows == 0 then
    renderFontDrawText(fontHud, "{FFFFFF}" .. couponsEmpty, tx, couponsY, 0xFFFFFFFF)
  else
    for i, row in ipairs(couponRows) do
      local ry = couponsY + (i - 1) * rowH
      renderFontDrawText(fontHud, "{FF8C37}" .. row.name, tx, ry, 0xFFFFFFFF)
      renderFontDrawText(fontHud, "{FF8C37}" .. row.count, tx + couponNameCol + minGap, ry, 0xFFFFFFFF)
    end
  end
end

------------------------------------ Utils  ------------------------------------
function toggleScriptActivation()
  cfg.settings.enabled = not cfg.settings.enabled
  saveCFG()
  if not cfg.settings.enabled then
    restoreWaves()
    isEquipping, isNetting = false, false
  end
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

function sendCommand(cmd, maxAttempts)
  if commandStates[cmd] then
    return
  end
  maxAttempts = maxAttempts or 10
  commandStates[cmd] = true
  lua_thread.create(function()
    local attempts = 0
    repeat
      wait(0)
      if os.clock() * 1000 - antiflood > 500 then
        sampSendChat(cmd)
        antiflood = os.clock() * 1000
        attempts = attempts + 1
      end
    until not commandStates[cmd] or attempts >= maxAttempts
    commandStates[cmd] = nil
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
    imgui.TextUnformatted(param)
    imgui.PopTextWrapPos()
    imgui.EndTooltip()
  end
end

function onWindowMessage(m, p)
  if p == VK_ESCAPE and window.v then
    consumeWindowMessage()
    window.v = false
  end
end

function escape_string(str)
  return str:gsub(".", function(c)
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
  text = u8(text)
  local fishName, amount = text:match('^ %[Рыболовный магазин%] {FFFFFF}Вы успешно продали {6AB1FF}"(.+)" %((%d+) кг%){FFFFFF}')
  local fish = fishName and cfg.fish[fishName]
  if fish and amount then
    setCaughtAmount(fishName, math.max(0, (tonumber(fish.caught) or 0) - tonumber(amount)))
    saveCFG()
  end

  local soldCount, soldDescription = text:match("^ Вы продали (%d+) (.+) за %$%d+")
  local soldItemName = soldCount and soldHuntingItems[soldDescription]
  if soldItemName and cfg.hunting_items[soldItemName] then
    setHuntingAmount(soldItemName, math.max(0, (tonumber(cfg.hunting_items[soldItemName].amount) or 0) - tonumber(soldCount)))
    cfg.last_skin_sale = os.time()
    saveCFG()
  end

  local caughtName, caughtAmount = text:match('^ %[Рыбалка%] {FFFFFF}Вы успешно поймали {6AB1FF}"(.+)"{FFFFFF}. Масса: {6AB1FF}([%d%.]+) кг')
  local caughtFish = caughtName and cfg.fish[caughtName]
  if caughtFish and caughtAmount then
    setCaughtAmount(caughtName, (tonumber(caughtFish.caught) or 0.00) + (tonumber(caughtAmount) or 0.00))
    sessionCaught[caughtName] = (sessionCaught[caughtName] or 0.00) + (tonumber(caughtAmount) or 0.00)
    saveCFG()
  end

  local netName, netAmount = text:match('^ %[Рыбалка%] {FFFFFF}Вы достали из сети: {6AB1FF}"(.+)" %(([%d%.]+) кг%)')
  local netFish = netName and cfg.fish[netName]
  if netFish and netAmount then
    setCaughtAmount(netName, (tonumber(netFish.caught) or 0.00) + (tonumber(netAmount) or 0.00))
    sessionCaught[netName] = (sessionCaught[netName] or 0.00) + (tonumber(netAmount) or 0.00)
    saveCFG()
  end

  local couponName
  if text:match('^ %[Купон%] {FFFFFF}Вам начислен купон {FF8C37}Купон на бесплатный скин') then
    couponName = "Бесплатный скин"
  elseif text:match('^ %[Купон%] {FFFFFF}Вам начислен купон {FF8C37}Купон на бесплатный автомобиль %[A%]') then
    couponName = "Автомобиль [A]"
  elseif text:match('^ %[Купон%] {FFFFFF}Вам начислен купон {FF8C37}Купон на бесплатный автомобиль %[B%]') then
    couponName = "Автомобиль [B]"
  end
  if couponName then
    sessionCoupons[couponName] = (sessionCoupons[couponName] or 0) + 1
  end

  local cooldownMinutes = text:match("^ Следующую продажу можете осуществить через %{FFFFFF%}(%d+)")
  if cooldownMinutes then
    cfg.last_skin_sale = os.time() - (SKIN_SALE_COOLDOWN - tonumber(cooldownMinutes) * 60)
    saveCFG()
  end

  if text == " Вы получили мясо и шкуру дикой коровы" then
    setHuntingAmount("Мясо дикой коровы", (tonumber(cfg.hunting_items["Мясо дикой коровы"].amount) or 0) + 1)
    setHuntingAmount("Шкура дикой коровы", (tonumber(cfg.hunting_items["Шкура дикой коровы"].amount) or 0) + 1)
    saveCFG()
  elseif text == " Вы получили мясо и шкуру дикого оленя" then
    setHuntingAmount("Мясо оленя", (tonumber(cfg.hunting_items["Мясо оленя"].amount) or 0) + 1)
    setHuntingAmount("Шкура оленя", (tonumber(cfg.hunting_items["Шкура оленя"].amount) or 0) + 1)
    saveCFG()
  elseif text == " Вы получили мясо дикой коровы" then
    setHuntingAmount("Мясо дикой коровы", (tonumber(cfg.hunting_items["Мясо дикой коровы"].amount) or 0) + 1)
    saveCFG()
  elseif text == " Вы получили мясо дикого оленя" then
    setHuntingAmount("Мясо оленя", (tonumber(cfg.hunting_items["Мясо оленя"].amount) or 0) + 1)
    saveCFG()
  end

  if text == " Не флуди!" or text == " В AFK ввод команд заблокирован" then
    antiflood = os.clock() * 1000 + 1500
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

function drawHuntingHud()
  if not fontHud then fontHud = renderCreateFont("Segoe UI Black", cfg.ui.font_size, font_flag.SHADOW) end

  local fontH = renderGetFontDrawHeight(fontHud)
  local rowH, pad, gap = fontH + 2, 8, 12
  local items, nameWidth, amountWidth, changeWidth = {}, 0, 0, 0
  for name, counts in pairs(cfg.hunting_items) do
    local item = { name = u8:decode(name), amount = string.format("%d / %d", counts.amount or 0, counts.maximum or 0) }
    local change = huntingChanges[name]
    if change and change.expires > os.clock() then
      item.change = string.format("%s%d", change.amount > 0 and "+" or "", change.amount)
      item.changeColor = change.amount > 0 and "{00B200}" or "{FF4040}"
      changeWidth = math.max(changeWidth, renderGetFontDrawTextLength(fontHud, item.change))
    elseif change then
      huntingChanges[name] = nil
    end
    item.nameW = renderGetFontDrawTextLength(fontHud, item.name)
    item.amountW = renderGetFontDrawTextLength(fontHud, item.amount)
    nameWidth = math.max(nameWidth, item.nameW)
    amountWidth = math.max(amountWidth, item.amountW)
    items[#items + 1] = item
  end
  table.sort(items, function(a, b) return a.name < b.name end)

  local title = u8:decode("Мясо и шкуры")
  local titleW = renderGetFontDrawTextLength(fontHud, title)
  local listWidth = math.max(titleW, nameWidth + gap + amountWidth)
  if changeWidth > 0 then
    listWidth = listWidth + gap + changeWidth
  end
  local x, y = cfg.ui.hunting_pos_x, cfg.ui.hunting_pos_y
  local tx, ty = x + pad, y + pad
  renderFontDrawText(fontHud, "{E3B54A}" .. title, tx, ty, 0xFFFFFFFF)
  ty = ty + fontH + 2
  renderDrawLine(tx, ty, x + listWidth + pad, ty, 1, 0xFF5A5A5A)
  ty = ty + 4

  for i, item in ipairs(items) do
    local iy = ty + (i - 1) * rowH
    renderFontDrawText(fontHud, "{FFFFFF}" .. item.name, tx, iy, 0xFFFFFFFF)
    renderFontDrawText(fontHud, "{E3B54A}" .. item.amount, tx + nameWidth + gap, iy, 0xFFFFFFFF)
    if item.change then
      renderFontDrawText(fontHud, item.changeColor .. item.change, tx + nameWidth + gap + amountWidth + gap, iy, 0xFFFFFFFF)
    end
  end

  local elapsed = os.time() - (tonumber(cfg.last_skin_sale) or 0)
  local statusY = ty + #items * rowH + 4
  local statusText, statusColor
  if elapsed >= SKIN_SALE_COOLDOWN then
    statusText = u8:decode("Доступна продажа шкур")
    statusColor = "{00B200}"
  else
    local minutes = math.ceil((SKIN_SALE_COOLDOWN - elapsed) / 60)
    statusText = u8:decode("До продажи: ") .. minutes .. u8:decode(" минут")
    statusColor = "{E3B54A}"
  end
  renderFontDrawText(fontHud, statusColor .. statusText, tx, statusY, 0xFFFFFFFF)

  if hudMoving == "hunting" then
    local hint = u8:decode("ЛКМ — подтвердить позицию")
    renderFontDrawText(fontHud, "{E3B54A}" .. hint, tx, statusY + rowH + 2, 0xFFFFFFFF)
  end
end

function ev.onSendChat(text)
	antiflood = os.clock() * 1000
end

function ev.onSendCommand(cmd)
	antiflood = os.clock() * 1000
end

function ev.onShowDialog(id, style, title, btn1, btn2, text)
  title = u8(title)
  text = u8(text)

  if style == 4 and title:find("Карманы", 1, true) then
    for _, counts in pairs(cfg.hunting_items) do
      counts.amount = 0
    end
    for line in text:gmatch("[^\r\n]+") do
      local name, amount, maximum = line:match("^%s*%[%d+%]%s*(.-)%s+([%d%.]+)%s*/%s*([%d%.]+)")
      if name and cfg.hunting_items[name] then
        cfg.hunting_items[name].amount = tonumber(amount) or 0
        cfg.hunting_items[name].maximum = tonumber(maximum) or cfg.hunting_items[name].maximum
      end
    end
    saveCFG()
  end

  if style == 4 and title:find("{FFFFFF} Инвентарь {6AB1FF}| Рыбалка") then
    local fishSection = false
    local inventoryEmpty = text:find("[ Предметы отсутствуют ]", 1, true) ~= nil
    local inventoryFish = {}
    for name in pairs(cfg.fish) do
      inventoryFish[name] = true
    end

    for line in text:gmatch("[^\r\n]+") do
      if line:find("Рыба:", 1, true) then
        fishSection = true
        for name in pairs(cfg.fish) do
          cfg.fish[name].caught = 0.00
        end
      elseif fishSection then
        local name, amount = line:match("^(.+)%s+([%d%.]+)%s+кг%s*$")
        if name and inventoryFish[name] and amount then
          cfg.fish[name].caught = tonumber(amount)
        end
      end
    end

    if inventoryEmpty then
      for name in pairs(cfg.fish) do
        cfg.fish[name].caught = 0.00
      end
      saveCFG()
    elseif fishSection then
      saveCFG()
    end
  end

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
          local name, price, amount = raw_text:match("([- \208-\209\128-\191]+)\\t{6AB1FF}%$(%d+)\\t{FFFFFF}(%d+%.%d+)")
          local fish = name and cfg.fish[name]
          if fish and price and amount then
            price = tonumber(price)
            if price > fish.max_price then
              fish.max_price = price
              saveCFG()
            elseif price < fish.min_price then
              fish.min_price = price
              saveCFG()
            end
            formattedText = formattedText .. "\n" .. name .. "\t{6AB1FF}$" .. price .. "{FFFFFF} | {00B200}$" .. fish.max_price .. "\t{FFFFFF}" .. amount
            isSellingWindow = true
            amount = math.floor(amount)
            if amount > 0 then
              local min = fish.min_price
              local max = fish.max_price
              local percent_diff = 100
              if max > min then
                percent_diff = ((price - min) / (max - min)) * 100
              end
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
          sampShowDialog(id, u8:decode(title), u8:decode(formattedText), btn1, btn2, style)
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
  restoreWaves()
  fishForSell = getInitialFishForSell()
  commandStates = {}
  removeAnimalBlips()
end
