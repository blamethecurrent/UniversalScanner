--[[
    UniversalScanner — rbimgui-2 UI (v10)
]]

-- ============================================================
-- AUTOEXEC CONFIG
-- ============================================================
local LIB_URL = "https://cdn.jsdelivr.net/gh/blamethecurrent/UniversalScanner@latest/rbimgui.lua"
local ALLOWED_PLACES_OVERRIDE = nil  -- nil = use places.json

-- ============================================================
-- Constants
-- ============================================================
local FOLDER      = "UniversalScanner"
local CONFIG_PATH = FOLDER .. "/config.json"
local NAMES_PATH  = FOLDER .. "/names.txt"
local STATE_PATH  = FOLDER .. "/state.json"
local PLACES_PATH = FOLDER .. "/places.json"
local LOG_PATH    = FOLDER .. "/log.txt"

local UNIVERSE_ID = 184199275

-- honeypot !!!!! 
local BLOCKED_PLACES = {
    [12770493773] = "UF: Admin (honeypot)",
}

-- All 21 legitimate UF subplaces. Seeded to places.json on first run.
local SEED_PLACES = {
    { id = 2338325648,      name = "[🔥NIKE + 2X] NFL Universe Football" },
    { id = 4822225642,      name = "UF: Trade Hub" },
    { id = 4940687511,      name = "UF: Gameplay" },
    { id = 7097139127,      name = "UF: Tutorial" },
    { id = 7098347455,      name = "UF: Gym" },
    { id = 7098347570,      name = "UF: Private Gameplay" },
    { id = 11414445247,     name = "UF: Idle Mode" },
    { id = 12986634964,     name = "UF: Trade Hub Testing" },
    { id = 12986636453,     name = "UF: Tutorial Testing" },
    { id = 12986638725,     name = "UF: Gameplay Testing" },
    { id = 13415948659,     name = "UF: Park Match" },
    { id = 13834702475,     name = "UF: Park" },
    { id = 14801724413,     name = "UF: Practice Hub" },
    { id = 15098628040,     name = "UF: Ranked Gameplay" },
    { id = 17685156577,     name = "UF: Park [SQ]" },
    { id = 17685159087,     name = "UF: Flag Football Match" },
    { id = 17685161741,     name = "UF: Flag Football Hub" },
    { id = 17685164681,     name = "UF: Practice Hub [SQ]" },
    { id = 17685181130,     name = "UF: Ranked Queue Hub" },
    { id = 93001350941802,  name = "UF: Gameplay With Stamina" },
    { id = 125444254609144, name = "UF: Gameplay Without Stamina" },
}

local HARD_DEFAULTS = {
    version = 2, interval = 5, passDelay = 0,
    notify = true, autoStart = true,
    audioEnabled = false, audioId = "",
    webhookEnabled = false, webhookUrl = "",
    showScores = true,
    windowW = 470, windowH = 520,
}
local CLAMP = {
    interval  = { 3, 30 }, passDelay = { 0, 300 },
    windowW   = { 380, 800 }, windowH = { 240, 720 },
    retries   = 2, timeout = 30, maxBackoff = 60,
    scoreRefresh = 10, scoreTTL = 120,
}

-- ============================================================
-- Services
-- ============================================================
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")
local TeleportService   = game:GetService("TeleportService")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local LP                = Players.LocalPlayer

-- ============================================================
-- File I/O
-- ============================================================
local hasFS = writefile ~= nil and readfile ~= nil

local function ensureDir()
    if not hasFS then return end
    pcall(function()
        if isfolder and makefolder and not isfolder(FOLDER) then makefolder(FOLDER) end
    end)
end
local function fileExists(path)
    if not hasFS then return false end
    if isfile then local ok, r = pcall(isfile, path); return ok and r end
    local ok, c = pcall(readfile, path); return ok and c ~= nil
end
local function readFile(path)
    if not hasFS then return nil end
    local ok, c = pcall(readfile, path); return ok and c or nil
end
local function writeFile(path, content)
    if not hasFS then return false end
    local ok = pcall(writefile, path, content); return ok == true
end
local function appendFile(path, content)
    if not hasFS then return end
    if appendfile then pcall(appendfile, path, content); return end
    writeFile(path, (readFile(path) or "") .. content)
end
local function timestamp()
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M:%S")
    return ok and s or tostring(os.time())
end
local function logLine(msg)
    print("[Scanner] " .. msg)
    appendFile(LOG_PATH, ("[%s] %s\n"):format(timestamp(), msg))
end
ensureDir()

-- ============================================================
-- HTTP helper
-- ============================================================
local function httpRequest(opts)
    local function try(fn, arg)
        local ok, res = pcall(fn, arg)
        if ok and type(res) == "table" and res.Body then return res.Body end
        if ok and type(res) == "string" and #res > 0 then return res end
    end
    if request then local r = try(request, opts); if r then return r end end
    if syn and syn.request then local r = try(syn.request, opts); if r then return r end end
    if http and http.request then local r = try(http.request, opts); if r then return r end end
    if fluxus and fluxus.request then local r = try(fluxus.request, opts); if r then return r end end
    if (opts.Method or "GET") == "GET" then
        local ok, body = pcall(game.HttpGet, game, opts.Url)
        if ok and type(body) == "string" and #body > 0 then return body end
    end
    return nil
end

-- ============================================================
-- Places
-- ============================================================
local places = {}
local placesUniverse = UNIVERSE_ID

local function placesCount()
    local n = 0
    for _ in pairs(places) do n = n + 1 end
    return n
end

local function savePlaces()
    local list = {}
    for id, name in pairs(places) do
        if not BLOCKED_PLACES[id] then
            table.insert(list, { id = id, name = name })
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    writeFile(PLACES_PATH, HttpService:JSONEncode({
        version = 1, universe = placesUniverse, places = list,
    }))
end

local function loadPlaces()
    places = {}
    local raw = readFile(PLACES_PATH)
    if raw then
        local ok, d = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and type(d) == "table" and type(d.places) == "table" then
            for _, p in ipairs(d.places) do
                local id = tonumber(p.id)
                if id and not BLOCKED_PLACES[id] then
                    places[id] = tostring(p.name or ("Place " .. id))
                end
            end
            placesUniverse = tonumber(d.universe) or UNIVERSE_ID
        end
    end
    if not next(places) then
        for _, p in ipairs(SEED_PLACES) do places[p.id] = p.name end
        savePlaces()
        logLine("places.json seeded with " .. #SEED_PLACES .. " places")
    end
end

local function refreshPlaces(onDone)
    onDone = onDone or function() end
    task.spawn(function()
        local uBody = httpRequest({
            Url = ("https://apis.roblox.com/universes/v1/places/%d/universe"):format(game.PlaceId),
            Method = "GET",
        })
        if not uBody then onDone(false, "universe lookup failed"); return end
        local uOk, uData = pcall(function() return HttpService:JSONDecode(uBody) end)
        local universeId = uOk and uData and tonumber(uData.universeId)
        if not universeId then onDone(false, "universe parse failed"); return end
        placesUniverse = universeId

        local found, cursor, pages = {}, "", 0
        repeat
            local url = ("https://develop.roblox.com/v1/universes/%d/places?isUniverseCreation=false&sortOrder=Asc&limit=100")
                :format(universeId)
            if cursor ~= "" then url = url .. "&cursor=" .. cursor end

            local body = httpRequest({ Url = url, Method = "GET" })
            if not body then break end
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not ok or type(data) ~= "table" or type(data.data) ~= "table" then break end
            for _, p in ipairs(data.data) do
                local id = tonumber(p.id)
                if id and not BLOCKED_PLACES[id] then
                    found[id] = tostring(p.name or ("Place " .. id))
                end
            end
            pages  = pages + 1
            cursor = data.nextPageCursor or ""
        until cursor == "" or pages >= 5

        if not next(found) then onDone(false, "no places parsed"); return end
        places = found
        savePlaces()
        logLine(("refresh: %d places (universe %d)"):format(placesCount(), universeId))
        onDone(true, found)
    end)
end

loadPlaces()

-- ============================================================
-- Gate
-- ============================================================
do
    local place = game.PlaceId
    local allowed
    if ALLOWED_PLACES_OVERRIDE then
        allowed = false
        for _, id in ipairs(ALLOWED_PLACES_OVERRIDE) do
            if place == id then allowed = true; break end
        end
    else
        allowed = places[place] ~= nil
    end
    if not allowed then
        if BLOCKED_PLACES[place] then
            print(("[Scanner] Skip: place %d is blocked (%s)")
                :format(place, BLOCKED_PLACES[place]))
        else
            print(("[Scanner] Skip: place %d not in places.json (%d known)")
                :format(place, placesCount()))
        end
        return
    end
    print(("[Scanner] Place OK (%s, %d)"):format(tostring(places[place]), place))
end

if _G.Scanner and type(_G.Scanner.stop) == "function" then
    pcall(_G.Scanner.stop)
end

-- ============================================================
-- Config
-- ============================================================
local function clampInt(v, lo, hi, fb)
    v = tonumber(v); if not v then return fb end
    return math.clamp(math.floor(v + 0.5), lo, hi)
end
local function cleanAudioId(s)
    return tostring(s or ""):gsub("%D", "")
end
local function sanitizeConfig(c)
    return {
        version        = 2,
        interval       = clampInt(c.interval,  CLAMP.interval[1],  CLAMP.interval[2],  HARD_DEFAULTS.interval),
        passDelay      = clampInt(c.passDelay, CLAMP.passDelay[1], CLAMP.passDelay[2], HARD_DEFAULTS.passDelay),
        notify         = c.notify    == true,
        autoStart      = c.autoStart == true,
        audioEnabled   = c.audioEnabled == true,
        audioId        = cleanAudioId(c.audioId),
        webhookEnabled = c.webhookEnabled == true,
        webhookUrl     = tostring(c.webhookUrl or ""),
        showScores     = c.showScores ~= false,
        windowW        = clampInt(c.windowW, CLAMP.windowW[1], CLAMP.windowW[2], HARD_DEFAULTS.windowW),
        windowH        = clampInt(c.windowH, CLAMP.windowH[1], CLAMP.windowH[2], HARD_DEFAULTS.windowH),
    }
end
local function loadConfig()
    if not fileExists(CONFIG_PATH) then
        local seed = sanitizeConfig(HARD_DEFAULTS)
        writeFile(CONFIG_PATH, HttpService:JSONEncode(seed))
        logLine("config.json seeded")
        return seed
    end
    local raw = readFile(CONFIG_PATH)
    if not raw then return sanitizeConfig(HARD_DEFAULTS) end
    local ok, d = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(d) ~= "table" then return sanitizeConfig(HARD_DEFAULTS) end
    return sanitizeConfig(d)
end
local function saveConfig(c)
    writeFile(CONFIG_PATH, HttpService:JSONEncode(sanitizeConfig(c)))
end

-- ============================================================
-- Names / state
-- ============================================================
local function parseNames(raw)
    local list, seen = {}, {}
    for line in raw:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if #line > 0 and line:sub(1, 1) ~= "#" and not seen[line] then
            seen[line] = true; table.insert(list, line)
        end
    end
    return list
end
local function loadNames()
    local raw = readFile(NAMES_PATH); return raw and parseNames(raw) or {}
end
local function saveNames(list)
    writeFile(NAMES_PATH, table.concat(list, "\n") .. "\n")
end
local function loadState()
    local raw = readFile(STATE_PATH)
    if raw then
        local ok, d = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and type(d) == "table" then
            d.nextIndex = tonumber(d.nextIndex) or 1
            d.results   = d.results or {}
            return d
        end
    end
    return { version = 2, nextIndex = 1, results = {} }
end
local function saveState(s)
    local ok, e = pcall(function() return HttpService:JSONEncode(s) end)
    if ok then writeFile(STATE_PATH, e) end
end
local function pruneState(s, list)
    local keep = {}
    for _, n in ipairs(list) do keep[n] = true end
    for k in pairs(s.results) do
        if not keep[k] then s.results[k] = nil end
    end
    if s.nextIndex < 1 then s.nextIndex = 1 end
    if s.nextIndex > #list then s.nextIndex = math.max(1, #list) end
end

if hasFS and not fileExists(NAMES_PATH) then
    writeFile(NAMES_PATH, "# Universal Scanner — one username per line\n")
end

local cfg   = loadConfig()
local names = loadNames()
local state = loadState()
pruneState(state, names)

-- ============================================================
-- Game remote + scanning
-- ============================================================
local ReFunction
local function getReFunction()
    if ReFunction and ReFunction.Parent then return ReFunction end
    local re = ReplicatedStorage:FindFirstChild("ReEvent")
    ReFunction = re and re:FindFirstChild("ReFunction") or nil
    return ReFunction
end

local Variables
pcall(function()
    local m = LP.PlayerScripts.ClientMain.Utilities.Variables
    if m then Variables = require(m) end
end)

local function placeInfo(placeId)
    local name, canJoin
    if Variables and Variables.GlobalVariables
        and Variables.GlobalVariables.PlaceIdInfos then
        local info = Variables.GlobalVariables.PlaceIdInfos[placeId]
        if info then name = info.DisplayName; canJoin = info.CanJoin end
    end
    if not name then name = places[placeId] end
    return name, canJoin
end

local function scanPlayer(name)
    local fn = getReFunction()
    if not fn then return { status = "error", reason = "remote missing" } end
    local ok, a, _, c, d, e, f =
        pcall(fn.InvokeServer, fn, "GetPlayerPlaceInstanceAsync", name)
    if not ok then return { status = "error", reason = tostring(a) } end
    if a == nil and c == nil and f == nil then
        return { status = "error", reason = "empty response" }
    end
    local placeId     = tonumber(c)
    local displayName = (f and tostring(f)) or ""
    local userId      = tonumber(e)
    local jobId       = (d and tostring(d)) or ""
    local exactMatch  = displayName ~= "" and displayName:lower() == name:lower()

    if placeId and placeId > 0 then
        local pName, canJoin = placeInfo(placeId)
        return {
            status = "online", placeId = placeId, jobId = jobId,
            userId = userId, displayName = displayName, exactMatch = exactMatch,
            placeName = pName, canJoin = canJoin, at = os.time(),
        }
    elseif displayName ~= "" then
        return {
            status = "offline", displayName = displayName,
            exactMatch = exactMatch, at = os.time(),
        }
    else
        return { status = "notfound", at = os.time() }
    end
end

local function scanWithTimeout(name)
    local done, result = false, nil
    task.spawn(function() result = scanPlayer(name); done = true end)
    local elapsed = 0
    while not done and elapsed < CLAMP.timeout do
        task.wait(0.1); elapsed = elapsed + 0.1
    end
    if not done then return { status = "error", reason = "timeout" } end
    return result
end

-- ============================================================
-- Server score cache
-- ============================================================
local serverCache   = {}
local serverPage    = 1
local serverPageMax = 1
local lastServerFetch = 0

local function fetchServerPage()
    local fn = getReFunction()
    if not fn then return end
    local ok, a, b = pcall(fn.InvokeServer, fn, "GetServerPage",
        "Gameplay", serverPage, "recommended", "")
    if not ok or not a or type(b) ~= "table" then return end
    serverPageMax = tonumber(b.MaxPages) or 1
    for _, s in ipairs(b.Servers or {}) do
        if s.ServerId then
            local sc = s.ServInfo and s.ServInfo.Score or {}
            serverCache[s.ServerId] = {
                home    = tonumber(sc.Home) or 0,
                away    = tonumber(sc.Away) or 0,
                quarter = tonumber(s.Quarter) or 0,
                minutes = tonumber(s.Minutes) or 0,
                seconds = tonumber(s.Seconds) or 0,
                count   = tonumber(s.PlayerCount) or 0,
                max     = tonumber(s.MaxPlayers) or 0,
                at      = os.time(),
            }
        end
    end
    serverPage = (serverPage % math.max(1, serverPageMax)) + 1
end

local function scoreTag(jobId)
    if not cfg.showScores or not jobId or jobId == "" then return "" end
    local s = serverCache[jobId]
    if not s or (os.time() - s.at) > CLAMP.scoreTTL then return "" end
    return (" · Q%d %d:%02d · %d-%d · %d/%d")
        :format(s.quarter, s.minutes, s.seconds, s.home, s.away, s.count, s.max)
end

-- ============================================================
-- Load UI lib
-- ============================================================
local src = httpRequest({ Url = LIB_URL, Method = "GET" })
if not src or #src < 1000 or src:sub(1, 1) == "<" then
    error(("[Scanner] Could not fetch rbimgui-2 source (got %s)")
        :format(src and (#src .. " bytes, starts with '" .. src:sub(1, 1) .. "'") or "nil"))
end
local okLoad, ImGui = pcall(function() return loadstring(src)() end)
if not okLoad or not ImGui then error("[Scanner] Lib load failed: " .. tostring(ImGui)) end

-- ============================================================
-- Colors
-- ============================================================
local COL = {
    online = Color3.fromRGB(90, 220, 130), offline = Color3.fromRGB(220, 90, 90),
    unknown = Color3.fromRGB(160, 160, 160), idle = Color3.fromRGB(180, 180, 180),
    running = Color3.fromRGB(90, 220, 130), sleeping = Color3.fromRGB(220, 180, 90),
    stopped = Color3.fromRGB(220, 120, 90), error = Color3.fromRGB(220, 90, 90),
    warn = Color3.fromRGB(220, 180, 90), fuzzy = Color3.fromRGB(220, 180, 60),
    notfound = Color3.fromRGB(140, 140, 140), row = Color3.fromRGB(210, 210, 210),
    ok = Color3.fromRGB(120, 220, 140),
    btnPrimary = Color3.fromRGB(41, 74, 122), btnStart = Color3.fromRGB(46, 120, 60),
    btnStop = Color3.fromRGB(140, 60, 50), btnMuted = Color3.fromRGB(70, 70, 90),
    btnKill = Color3.fromRGB(180, 30, 30), bgInput = Color3.fromRGB(32, 59, 97),
}

local function statusChar(s)
    if s == "online" then return "●"
    elseif s == "offline" then return "○"
    elseif s == "notfound" then return "✗"
    else return "?" end
end
local function statusColor(s) return COL[s] or COL.unknown end
local function colorForResult(r)
    if not r then return COL.unknown end
    if (r.status == "online" or r.status == "offline") and r.exactMatch == false then
        return COL.fuzzy
    end
    return statusColor(r.status)
end

-- ============================================================
-- Window
-- ============================================================
local WIN_TITLE = "UniversalScanner"
local window = ImGui.new({
    text = WIN_TITLE, size = Vector2.new(cfg.windowW, cfg.windowH),
    shadow = 10, transparency = 0.15,
    color = Color3.fromRGB(41, 74, 122), boardcolor = Color3.fromRGB(21, 22, 23),
    rounding = 5, animation = 0.1, position = UDim2.new(0, 100, 0, 100),
})

local function findMainFrame(title)
    local imgui = CoreGui:FindFirstChild("imgui2")
    if not imgui then return nil end
    for _, child in ipairs(imgui:GetChildren()) do
        if child.Name == "Main" and child:FindFirstChild("Title")
            and child.Title.Text == title then
            return child
        end
    end
    return nil
end
local mainFrame    = findMainFrame(WIN_TITLE)
local contentFrame = mainFrame and mainFrame:FindFirstChild("Content")

-- ============================================================
-- Runtime flags + forward-declared switch refs
-- ============================================================
local running     = false
local scanGen     = 0
local currentMode = "Idle"
local passesDone  = 0
local killed      = false

-- These are wired in the Settings tab, but referenced by notifyChange/playAlert/webhookStatus
local notifySwitch, audioSwitch, webhookSwitch, scoreSwitch, autoSwitch
local audioBox, webhookBox

-- ============================================================
-- Toast
-- ============================================================
local toast
local function defineToast()
    toast = function(title, text)
        pcall(function()
            StarterGui:SetCore("SendNotification",
                { Title = title, Text = text, Duration = 4 })
        end)
    end
end
defineToast()

-- ============================================================
-- Audio alert
-- ============================================================
local function playAlert()
    if killed then return end
    if not audioSwitch or not audioSwitch.on then return end
    local id = audioBox and tonumber(cleanAudioId(audioBox.Text)) or nil
    if not id or id <= 0 then return end
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. id
    s.Volume = 0.6
    s.Parent = SoundService
    pcall(function() SoundService:PlayLocalSound(s) end)
    pcall(function() s:Play() end)
    task.delay(6, function() pcall(function() s:Destroy() end) end)
end

-- ============================================================
-- Webhook
-- ============================================================
local function deepLink(placeId, jobId)
    return ("https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s")
        :format(placeId, jobId)
end

local function sendWebhook(payload)
    if killed or not webhookSwitch or not webhookSwitch.on then return end
    local url = webhookBox and webhookBox.Text or ""
    if not url:match("^https://discord") then return end
    local ok, body = pcall(function() return HttpService:JSONEncode(payload) end)
    if not ok then return end
    task.spawn(function()
        httpRequest({
            Url = url, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end)
end

local function webhookStatus(name, result, prevStatus, scoreStr)
    if killed or not webhookSwitch or not webhookSwitch.on then return end
    local isOnline  = result.status == "online"
    local isOffline = result.status == "offline"
    if not isOnline and not isOffline then return end
    if isOnline  and prevStatus == "online" then return end
    if isOffline and prevStatus ~= "online" then return end

    local title = isOnline and "Player Online" or "Player Offline"
    local color = isOnline and 0x5ADC82 or 0xDC5A5A
    local desc  = isOnline
        and ("**%s** is online"):format(result.displayName or name)
        or  ("**%s** went offline"):format(name)

    local fields = {}
    if isOnline then
        if result.placeName then
            table.insert(fields, { name = "Place", value = result.placeName, inline = true })
        end
        if result.jobId and result.jobId ~= "" then
            table.insert(fields, {
                name = "Server",
                value = ("`%s…`"):format(result.jobId:sub(1, 8)),
                inline = true,
            })
        end
        if scoreStr and scoreStr ~= "" then
            table.insert(fields, { name = "Server score", value = scoreStr, inline = true })
        end
        if result.placeId and result.jobId and result.jobId ~= "" then
            table.insert(fields, {
                name = "Join",
                value = ("[Click to join](%s)"):format(deepLink(result.placeId, result.jobId)),
            })
        end
    end

    sendWebhook({
        username = "UniversalScanner",
        embeds = {{
            title = title, description = desc, color = color, fields = fields,
            footer = { text = "UF Player Scanner" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
    })
end

-- ============================================================
-- Tab layout enforcer
-- ============================================================
local function enforceTabLayout()
    if killed or not mainFrame or not mainFrame.Parent then return end
    local content = mainFrame:FindFirstChild("Content")
    local tabs    = mainFrame:FindFirstChild("Tabs")
    if not content or not tabs then return end
    local target = (content.ZIndex or 1) + 5
    if tabs.ZIndex < target then
        tabs.ZIndex = target
        for _, d in ipairs(tabs:GetDescendants()) do
            pcall(function()
                local z = d.ZIndex
                if typeof(z) == "number" and z < target then d.ZIndex = target end
            end)
        end
    end
    local items = tabs:FindFirstChild("Items")
    if items then
        for _, btn in ipairs(items:GetChildren()) do
            if btn:IsA("TextButton") then
                local tb = btn.TextBounds.X
                if tb > 0 then
                    local need = math.max(tb + 20, 60)
                    if btn.Size.X.Offset < need then
                        btn.Size = UDim2.new(0, need, 1, 0)
                    end
                    pcall(function()
                        btn.TextTruncate = Enum.TextTruncate.AtEnd
                        btn.TextXAlignment = Enum.TextXAlignment.Center
                    end)
                end
            end
        end
    end
end
task.defer(enforceTabLayout)
local lastLayoutCheck = 0
RunService.Heartbeat:Connect(function()
    if killed then return end
    local now = tick()
    if now - lastLayoutCheck < 0.2 then return end
    lastLayoutCheck = now
    enforceTabLayout()
end)

-- ============================================================
-- PLAYERS TAB
-- ============================================================
local scanTab = window.new({ text = "Players" })
local tmp = scanTab.new("label", { text = "" })
local tabItems = tmp.self.Parent
tmp.self:Destroy()

tabItems.Size = UDim2.new(1, -20, 1, -46)
tabItems.ScrollingDirection = Enum.ScrollingDirection.Y
tabItems.ScrollBarThickness = 6

local statusLbl = Instance.new("TextLabel")
statusLbl.Name = "StatusLbl"; statusLbl.LayoutOrder = 1
statusLbl.Size = UDim2.new(1, 0, 0, 16)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Code; statusLbl.TextSize = 12
statusLbl.TextColor3 = COL.idle
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
statusLbl.Text = "Idle"; statusLbl.Parent = tabItems

local addRow = Instance.new("Frame")
addRow.Name = "AddRow"; addRow.LayoutOrder = 2
addRow.Size = UDim2.new(1, 0, 0, 26)
addRow.BackgroundTransparency = 1; addRow.Parent = tabItems

local addBox = Instance.new("TextBox")
addBox.Name = "Input"
addBox.Size = UDim2.new(1, -70, 1, 0)
addBox.BackgroundColor3 = COL.bgInput
addBox.BorderSizePixel = 0
addBox.Font = Enum.Font.Code
addBox.PlaceholderText = "Username"
addBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
addBox.Text = ""; addBox.TextColor3 = Color3.fromRGB(255, 255, 255)
addBox.TextSize = 13; addBox.TextXAlignment = Enum.TextXAlignment.Left
addBox.ClearTextOnFocus = false
addBox.Parent = addRow
Instance.new("UICorner", addBox).CornerRadius = UDim.new(0, 3)
Instance.new("UIPadding", addBox).PaddingLeft = UDim.new(0, 8)

local addBtn = Instance.new("TextButton")
addBtn.Name = "Add"
addBtn.Size = UDim2.new(0, 64, 1, 0)
addBtn.Position = UDim2.new(1, -64, 0, 0)
addBtn.BackgroundColor3 = COL.btnPrimary
addBtn.BorderSizePixel = 0
addBtn.Font = Enum.Font.Code; addBtn.Text = "Add"
addBtn.TextColor3 = Color3.fromRGB(255, 255, 255); addBtn.TextSize = 13
addBtn.Parent = addRow
Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 3)

local playersHeader = Instance.new("TextLabel")
playersHeader.Name = "PlayersHeader"; playersHeader.LayoutOrder = 3
playersHeader.Size = UDim2.new(1, 0, 0, 18)
playersHeader.BackgroundTransparency = 1
playersHeader.Font = Enum.Font.Code; playersHeader.TextSize = 12
playersHeader.TextColor3 = COL.idle
playersHeader.TextXAlignment = Enum.TextXAlignment.Left
playersHeader.Text = "Players:"; playersHeader.Parent = tabItems

local ctrlBar = Instance.new("Frame")
ctrlBar.Name = "CtrlBar"
ctrlBar.Size = UDim2.new(1, -20, 0, 40)
ctrlBar.Position = UDim2.new(0, 10, 1, -42)
ctrlBar.BackgroundTransparency = 1
ctrlBar.Parent = tabItems.Parent

local function makeCtrlBtn(text, xPos, width, bg)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, width, 0, 30)
    b.Position = UDim2.new(0, xPos, 0, 5)
    b.BackgroundColor3 = bg or COL.btnPrimary
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code; b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255); b.TextSize = 13
    b.Parent = ctrlBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end

local startBtn = makeCtrlBtn("Start", 0,   80, COL.btnStart)
local stopBtn  = makeCtrlBtn("Stop",  86,  80, COL.btnStop)
local resetBtn = makeCtrlBtn("Reset", 172, 80, COL.btnMuted)

-- ============================================================
-- Player rows
-- ============================================================
local playerRows = {}

local function joinServer(placeId, jobId, canJoin)
    if killed then return end
    if not placeId or not jobId or jobId == "" then
        toast("Scanner", "No server info"); return
    end
    if BLOCKED_PLACES[placeId] then
        toast("Scanner", "Blocked — " .. BLOCKED_PLACES[placeId])
        logLine(("Join blocked: place %d is honeypot"):format(placeId))
        return
    end
    if not places[placeId] then
        toast("Scanner", "Blocked — place " .. placeId .. " not whitelisted")
        logLine(("Join blocked: place %d not in whitelist"):format(placeId))
        return
    end
    if placeId == game.PlaceId and jobId == game.JobId then
        toast("Scanner", "Already in that server"); return
    end
    if canJoin == false then
        toast("Scanner", "Server not joinable"); return
    end
    logLine(("Joining place %d · job %s"):format(placeId, tostring(jobId):sub(1, 8)))
    local ok = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, LP)
    end)
    if not ok then toast("Scanner", "Teleport failed") end
end

local function formatLabel(name, r)
    local s = r and r.status or "unknown"
    local char = statusChar(s)
    if s == "online" then
        local jobTag = ""
        if r.jobId and #r.jobId >= 6 then
            jobTag = "  ·  " .. string.upper(string.sub(r.jobId, 1, 6))
        end
        local score = scoreTag(r.jobId)
        local placeTag = ""
        if r.placeName and r.placeName ~= "" then
            placeTag = "  ·  " .. r.placeName
        elseif r.placeId then
            placeTag = "  ·  Place " .. tostring(r.placeId)
        end
        if r.exactMatch == false and r.displayName then
            return ("%s %s → %s%s%s%s"):format(
                char, name, r.displayName, jobTag, score, placeTag)
        end
        return ("%s %s%s%s%s"):format(char, name, jobTag, score, placeTag)
    elseif s == "offline" then
        if r.exactMatch == false and r.displayName then
            return ("%s %s → %s"):format(char, name, r.displayName)
        end
        return char .. " " .. (r.displayName or name)
    elseif s == "notfound" then
        return char .. " " .. name .. "  (not found)"
    else
        return char .. " " .. name .. "  " .. (r and r.reason or "?")
    end
end

local function updateTabCanvas()
    task.defer(function()
        local layout = tabItems:FindFirstChildOfClass("UIListLayout")
        if layout then
            tabItems.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
        end
    end)
end

local function buildRow(name)
    local row = Instance.new("Frame")
    row.Name = "Row_" .. name; row.LayoutOrder = 100
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundTransparency = 1; row.Parent = tabItems

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Lbl"; lbl.Size = UDim2.new(1, -32, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Code; lbl.TextSize = 12
    lbl.TextColor3 = COL.unknown
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = "? " .. name; lbl.Parent = row

    lbl.InputBegan:Connect(function(input, gpe)
        if gpe or killed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local r = state.results[name]
        if not r then return end
        if r.status == "online" then
            if r.exactMatch == false then
                toast("Scanner", ("'%s' → '%s' — joining")
                    :format(name, r.displayName or "?"))
            end
            joinServer(r.placeId, r.jobId, r.canJoin)
        elseif r.status == "offline" then
            toast("Scanner", name .. " is offline")
        elseif r.status == "notfound" then
            toast("Scanner", "'" .. name .. "' doesn't exist")
        end
    end)
    lbl.MouseEnter:Connect(function()
        if not killed then lbl.TextColor3 = Color3.new(1, 1, 1) end
    end)
    lbl.MouseLeave:Connect(function()
        if not killed then lbl.TextColor3 = colorForResult(state.results[name]) end
    end)

    local btn = Instance.new("TextButton")
    btn.Name = "Remove"; btn.Size = UDim2.new(0, 24, 0, 18)
    btn.Position = UDim2.new(1, -26, 0, 1)
    btn.BackgroundColor3 = Color3.fromRGB(70, 30, 30)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.Code; btn.TextSize = 12
    btn.TextColor3 = Color3.fromRGB(255, 150, 150)
    btn.Text = "×"; btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)

    btn.MouseButton1Click:Connect(function()
        if killed then return end
        local removedIdx
        for j, n in ipairs(names) do
            if n == name then removedIdx = j; table.remove(names, j); break end
        end
        if not removedIdx then return end
        state.results[name] = nil
        if removedIdx < state.nextIndex then
            state.nextIndex = math.max(1, state.nextIndex - 1)
        end
        if state.nextIndex > #names then
            state.nextIndex = math.max(1, #names)
        end
        saveNames(names); saveState(state)
        if playerRows[name] then
            pcall(function() playerRows[name].row:Destroy() end)
            playerRows[name] = nil
        end
        updateTabCanvas(); updateStatusLine()
        logLine("Removed " .. name)
    end)

    return { row = row, label = lbl, button = btn }
end

local function rebuildRows()
    for _, r in pairs(playerRows) do pcall(function() r.row:Destroy() end) end
    playerRows = {}
    for i, name in ipairs(names) do
        local r = buildRow(name)
        r.row.LayoutOrder = 100 + i
        playerRows[name] = r
        local res = state.results[name]
        r.label.Text = formatLabel(name, res)
        r.label.TextColor3 = colorForResult(res)
    end
    updateTabCanvas()
end

local function ensureRow(name)
    if playerRows[name] then return playerRows[name] end
    local r = buildRow(name)
    playerRows[name] = r
    updateTabCanvas()
    return r
end

local function updatePlayerLabel(name, result)
    local r = playerRows[name]
    if not r or not r.label.Parent then return end
    r.label.Text = formatLabel(name, result)
    r.label.TextColor3 = colorForResult(result)
end

local function updateStatusLine(mode, extra)
    if mode then currentMode = mode end
    if killed then return end
    local online, offline, unknown = 0, 0, 0
    for _, r in pairs(state.results) do
        if     r.status == "online"  then online  = online + 1
        elseif r.status == "offline" then offline = offline + 1
        else unknown = unknown + 1 end
    end
    if #names == 0 then
        statusLbl.Text = "No players — add one above"
        statusLbl.TextColor3 = COL.warn; return
    end
    local tail = extra
    if not tail then
        local nextName = names[state.nextIndex]
        tail = nextName and ("Next: " .. nextName) or "Pass complete"
    end
    statusLbl.Text = ("%s  ●%d ○%d ?%d  ·  %d/%d  ·  %s")
        :format(currentMode, online, offline, unknown,
                math.min(state.nextIndex - 1, #names), #names, tail)
    local color = COL.idle
    if     currentMode == "Running"  then color = COL.running
    elseif currentMode == "Sleeping" then color = COL.sleeping
    elseif currentMode == "Stopped"  then color = COL.stopped
    elseif currentMode == "Error"    then color = COL.error end
    statusLbl.TextColor3 = color
end

local function addPlayer(raw)
    if killed then return false end
    local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if #name < 3 or #name > 20 then return false end
    for _, n in ipairs(names) do
        if n:lower() == name:lower() then return false end
    end
    table.insert(names, name)
    saveNames(names); ensureRow(name); updateStatusLine()
    logLine("Added " .. name)
    return true
end

addBtn.MouseButton1Click:Connect(function()
    if addPlayer(addBox.Text) then addBox.Text = "" end
end)
addBox.FocusLost:Connect(function(enter)
    if enter and addPlayer(addBox.Text) then addBox.Text = "" end
end)

-- ============================================================
-- SETTINGS TAB
-- ============================================================
local settingsTab = window.new({ text = "Settings" })
local stmp = settingsTab.new("label", { text = "" })
local settingsItems = stmp.self.Parent
stmp.self:Destroy()

local function sectionLabel(text, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 16)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code; l.TextSize = 11
    l.TextColor3 = color or COL.idle
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text; l.Parent = settingsItems
    return l
end

local function makeSizedBtn(parent, text, xPos, width, bg)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, width, 0, 26)
    b.Position = UDim2.new(0, xPos, 0, 0)
    b.BackgroundColor3 = bg or COL.btnPrimary
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code; b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 12; b.TextTruncate = Enum.TextTruncate.AtEnd
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    return b
end

local function makeTextRow(placeholder, defaultText)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 26); row.BackgroundTransparency = 1
    row.Parent = settingsItems
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -72, 1, 0)
    box.BackgroundColor3 = COL.bgInput
    box.BorderSizePixel = 0
    box.Font = Enum.Font.Code
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    box.Text = defaultText or ""
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 12; box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false; box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
    Instance.new("UIPadding", box).PaddingLeft = UDim.new(0, 8)
    local btn = makeSizedBtn(row, "Test", 0, 64, COL.btnMuted)
    btn.Position = UDim2.new(1, -64, 0, 0)
    btn.Size = UDim2.new(0, 64, 0, 26)
    return row, box, btn
end

local intervalSlider = settingsTab.new("slider", {
    text = "Interval", size = 110,
    min = CLAMP.interval[1], max = CLAMP.interval[2], value = cfg.interval,
})
local passSlider = settingsTab.new("slider", {
    text = "Pass delay", size = 110,
    min = CLAMP.passDelay[1], max = CLAMP.passDelay[2], value = cfg.passDelay,
})
notifySwitch = settingsTab.new("switch", { text = "Notify", on = cfg.notify })
autoSwitch   = settingsTab.new("switch", { text = "Auto-start", on = cfg.autoStart })
scoreSwitch  = settingsTab.new("switch", { text = "Show server scores", on = cfg.showScores })

local function widenSliderLabel(slider, w)
    if slider and slider.self then
        local txt = slider.self:FindFirstChild("Text")
        if txt then txt.Size = UDim2.new(0, w or 240, 1, 0) end
    end
end
widenSliderLabel(intervalSlider, 240)
widenSliderLabel(passSlider,     240)

sectionLabel("Audio alert")
audioSwitch = settingsTab.new("switch", { text = "Play sound on change", on = cfg.audioEnabled })
local audioRow
audioRow, audioBox = makeTextRow("Audio asset ID (digits only)", cfg.audioId)
local audioTestBtn = audioRow:FindFirstChildOfClass("TextButton")

sectionLabel("Discord webhook")
webhookSwitch = settingsTab.new("switch", { text = "Post on change", on = cfg.webhookEnabled })
local webhookRow
webhookRow, webhookBox = makeTextRow("https://discord.com/api/webhooks/…", cfg.webhookUrl)
local webhookTestBtn = webhookRow:FindFirstChildOfClass("TextButton")

sectionLabel("Config")
local cfgStatusLabel = Instance.new("TextLabel")
cfgStatusLabel.Size = UDim2.new(1, 0, 0, 16)
cfgStatusLabel.BackgroundTransparency = 1
cfgStatusLabel.Font = Enum.Font.Code; cfgStatusLabel.TextSize = 11
cfgStatusLabel.TextColor3 = COL.idle
cfgStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
cfgStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
cfgStatusLabel.Text = "Ready"; cfgStatusLabel.Parent = settingsItems

local saveRow = Instance.new("Frame")
saveRow.Size = UDim2.new(1, 0, 0, 28); saveRow.BackgroundTransparency = 1
saveRow.Parent = settingsItems
local saveBtn    = makeSizedBtn(saveRow, "Save",    0,   70)
local reloadBtn  = makeSizedBtn(saveRow, "Reload",  74,  70)
local defaultBtn = makeSizedBtn(saveRow, "Defaults",148, 80)

sectionLabel("Files & places")
local fileRow = Instance.new("Frame")
fileRow.Size = UDim2.new(1, 0, 0, 28); fileRow.BackgroundTransparency = 1
fileRow.Parent = settingsItems
local refreshBtn    = makeSizedBtn(fileRow, "Refresh Players", 0,   130)
local resetStateBtn = makeSizedBtn(fileRow, "Reset State",   134, 100, COL.btnMuted)

local placesRow = Instance.new("Frame")
placesRow.Size = UDim2.new(1, 0, 0, 28); placesRow.BackgroundTransparency = 1
placesRow.Parent = settingsItems
local rescanBtn = makeSizedBtn(placesRow, "Rescan Places", 0, 130)
local placesLbl = Instance.new("TextLabel")
placesLbl.Size = UDim2.new(1, -136, 1, 0)
placesLbl.Position = UDim2.new(0, 136, 0, 0)
placesLbl.BackgroundTransparency = 1
placesLbl.Font = Enum.Font.Code; placesLbl.TextSize = 11
placesLbl.TextColor3 = COL.unknown
placesLbl.TextXAlignment = Enum.TextXAlignment.Left
placesLbl.TextTruncate = Enum.TextTruncate.AtEnd
placesLbl.Text = ("%d known"):format(placesCount())
placesLbl.Parent = placesRow

local addPlaceRow = Instance.new("Frame")
addPlaceRow.Size = UDim2.new(1, 0, 0, 26); addPlaceRow.BackgroundTransparency = 1
addPlaceRow.Parent = settingsItems

local addPlaceBox = Instance.new("TextBox")
addPlaceBox.Size = UDim2.new(1, -72, 1, 0)
addPlaceBox.BackgroundColor3 = COL.bgInput
addPlaceBox.BorderSizePixel = 0
addPlaceBox.Font = Enum.Font.Code
addPlaceBox.PlaceholderText = "placeId or 'placeId: Name'"
addPlaceBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
addPlaceBox.Text = ""
addPlaceBox.TextColor3 = Color3.fromRGB(255, 255, 255)
addPlaceBox.TextSize = 12; addPlaceBox.TextXAlignment = Enum.TextXAlignment.Left
addPlaceBox.ClearTextOnFocus = false; addPlaceBox.Parent = addPlaceRow
Instance.new("UICorner", addPlaceBox).CornerRadius = UDim.new(0, 3)
Instance.new("UIPadding", addPlaceBox).PaddingLeft = UDim.new(0, 8)

local addPlaceBtn = makeSizedBtn(addPlaceRow, "Add", 0, 64)
addPlaceBtn.Position = UDim2.new(1, -64, 0, 0)
addPlaceBtn.Size = UDim2.new(0, 64, 0, 26)

local pathsLabel = Instance.new("TextLabel")
pathsLabel.Size = UDim2.new(1, 0, 0, 16)
pathsLabel.BackgroundTransparency = 1
pathsLabel.Font = Enum.Font.Code; pathsLabel.TextSize = 10
pathsLabel.TextColor3 = COL.unknown
pathsLabel.TextXAlignment = Enum.TextXAlignment.Left
pathsLabel.TextTruncate = Enum.TextTruncate.AtEnd
pathsLabel.Text = "Files: UniversalScanner/ (config, names, state, places, log)"
pathsLabel.Parent = settingsItems

local killRow = Instance.new("Frame")
killRow.Size = UDim2.new(1, 0, 0, 34); killRow.BackgroundTransparency = 1
killRow.Parent = settingsItems
local killFullBtn = makeSizedBtn(killRow, "KILL SCRIPT", 0, 220, COL.btnKill)

-- ============================================================
-- Getters
-- ============================================================
local function getInterval()
    local v = intervalSlider.value
    if type(v) ~= "number" then return cfg.interval end
    return math.clamp(math.floor(v + 0.5), CLAMP.interval[1], CLAMP.interval[2])
end
local function getPassDelay()
    local v = passSlider.value
    if type(v) ~= "number" then return cfg.passDelay end
    return math.clamp(math.floor(v + 0.5), CLAMP.passDelay[1], CLAMP.passDelay[2])
end

-- ============================================================
-- Notifications
-- ============================================================
local function notifyChange(name, result, prevStatus)
    if killed then return end
    local scoreStr = ""
    if result.status == "online" and result.jobId then
        local s = serverCache[result.jobId]
        if s and (os.time() - s.at) <= CLAMP.scoreTTL then
            scoreStr = ("Q%d %d:%02d · %d-%d")
                :format(s.quarter, s.minutes, s.seconds, s.home, s.away)
        end
    end
    if notifySwitch and notifySwitch.on then
        if result.status == "online" and prevStatus ~= "online" then
            local where = result.placeName and (" in " .. result.placeName) or ""
            local who = result.exactMatch == false
                and ("'" .. name .. "' → '" .. (result.displayName or "?") .. "'")
                or name
            logLine("ONLINE " .. who .. where)
            toast("Player Online", who .. where)
        elseif result.status == "offline" and prevStatus == "online" then
            logLine("OFFLINE " .. name)
            toast("Player Offline", name .. " went offline")
        end
    end
    if result.status == "online" and prevStatus ~= "online" then playAlert() end
    webhookStatus(name, result, prevStatus, scoreStr)
end

-- ============================================================
-- Scan loop
-- ============================================================
local function stopScan()
    running = false; scanGen = scanGen + 1
    updateStatusLine("Stopped")
end

local function interruptibleSleep(seconds, myGen, tailLabel)
    local remaining = math.floor(seconds + 0.5)
    while remaining > 0 and running and scanGen == myGen and not killed do
        updateStatusLine("Sleeping", ("%s in %ds"):format(tailLabel, remaining))
        local step = math.min(1, remaining)
        task.wait(step); remaining = remaining - step
    end
    if running and scanGen == myGen then currentMode = "Running" end
end

local function scanLoop(myGen)
    while running and scanGen == myGen and not killed do
        if #names == 0 then return end
        if state.nextIndex > #names then
            passesDone = passesDone + 1
            logLine(("Pass %d complete"):format(passesDone))
            state.nextIndex = 1; saveState(state)
            local pd = getPassDelay()
            if pd > 0 then interruptibleSleep(pd, myGen, "next pass") end
        end
        if not (running and scanGen == myGen and not killed) then break end

        local name = names[state.nextIndex]
        if not name then break end
        local prev = state.results[name]
        local prevStatus = prev and prev.status or nil
        local base = getInterval()

        local result, attempt = nil, 0
        while true do
            result = scanWithTimeout(name)
            if result.status ~= "error" then break end
            attempt = attempt + 1
            if attempt > CLAMP.retries then break end
            local waitS = math.min(base * (2 ^ attempt), CLAMP.maxBackoff)
            logLine(("Retry %d/%d for %s in %.0fs — %s")
                :format(attempt, CLAMP.retries, name, waitS, result.reason or "?"))
            interruptibleSleep(waitS, myGen, ("retrying " .. name))
            if not (running and scanGen == myGen and not killed) then break end
        end
        if not (running and scanGen == myGen and not killed) then break end

        if result.status == "error" then
            state.results[name] = {
                status = "unknown", reason = result.reason, at = os.time(),
            }
            logLine("UNKNOWN " .. name .. " — " .. (result.reason or "?"))
        else
            state.results[name] = result
            notifyChange(name, result, prevStatus)
        end
        updatePlayerLabel(name, state.results[name])

        state.nextIndex = state.nextIndex + 1
        saveState(state); updateStatusLine("Running")

        local now = os.time()
        if cfg.showScores and (now - lastServerFetch) >= CLAMP.scoreRefresh then
            lastServerFetch = now
            task.spawn(fetchServerPage)
        end

        local sleep = getInterval()
        if result.status == "error" then
            sleep = math.min(sleep * 2, CLAMP.maxBackoff)
        end
        interruptibleSleep(sleep, myGen, "next scan")
    end
end

local function startScan()
    if running or killed then return end
    if #names == 0 then
        updateStatusLine("Idle")
        toast("Scanner", "Add a player first"); return
    end
    running = true; scanGen = scanGen + 1
    local myGen = scanGen
    logLine("Started")
    task.spawn(function()
        local ok, err = pcall(scanLoop, myGen)
        if not ok then
            logLine("Scan loop crashed: " .. tostring(err))
            if scanGen == myGen then
                running = false
                updateStatusLine("Error")
            end
        end
        if scanGen == myGen then running = false end
    end)
end

local function resetScanState()
    running = false; scanGen = scanGen + 1
    state = { version = 2, nextIndex = 1, results = {} }
    saveState(state)
    for name in pairs(playerRows) do
        local r = playerRows[name]
        if r and r.label.Parent then
            r.label.Text = "? " .. name
            r.label.TextColor3 = COL.unknown
        end
    end
    passesDone = 0
    logLine("State reset"); updateStatusLine("Stopped")
end

startBtn.MouseButton1Click:Connect(startScan)
stopBtn.MouseButton1Click:Connect(stopScan)
resetBtn.MouseButton1Click:Connect(resetScanState)

-- ============================================================
-- Kill (Settings only)
-- ============================================================
local function killEverything()
    if killed then return end
    killed = true; running = false; scanGen = scanGen + 1
    task.defer(function()
    pcall(function()
        local imgui = CoreGui:FindFirstChild("imgui2")
        if not imgui then return end

        -- Destroy only OUR window (matched by title) — other scripts using
        -- rbimgui-2 in the same session keep their UIs intact.
        local mine = findMainFrame(WIN_TITLE)
        if mine then mine:Destroy() end

        -- Tear down the shared container only if no other script's Main remains.
        local stillUsed = false
        for _, child in ipairs(imgui:GetChildren()) do
            if child.Name == "Main" then stillUsed = true; break end
        end
        if not stillUsed then imgui:Destroy() end
        end)
    end)

    _G.Scanner = nil
    logLine("Killed — re-run script to relaunch")
    pcall(function()
        StarterGui:SetCore("SendNotification",
            { Title = "Scanner", Text = "Script killed — re-run to relaunch", Duration = 4 })
    end)
end
killFullBtn.MouseButton1Click:Connect(killEverything)

-- ============================================================
-- Settings actions
-- ============================================================
local function currentUIAsConfig()
    return {
        interval  = getInterval(),
        passDelay = getPassDelay(),
        notify    = notifySwitch.on,
        autoStart = autoSwitch.on,
        showScores = scoreSwitch.on,
        audioEnabled = audioSwitch.on,
        audioId = audioBox.Text,
        webhookEnabled = webhookSwitch.on,
        webhookUrl = webhookBox.Text,
        windowW   = mainFrame and math.floor(mainFrame.AbsoluteSize.X) or cfg.windowW,
        windowH   = contentFrame and math.floor(contentFrame.AbsoluteSize.Y) or cfg.windowH,
    }
end

saveBtn.MouseButton1Click:Connect(function()
    if killed then return end
    cfg = sanitizeConfig(currentUIAsConfig()); saveConfig(cfg)
    audioBox.Text = cfg.audioId
    webhookBox.Text = cfg.webhookUrl
    cfgStatusLabel.Text = "Saved  " .. timestamp()
    cfgStatusLabel.TextColor3 = COL.ok
    logLine("Config saved")
end)

reloadBtn.MouseButton1Click:Connect(function()
    if killed then return end
    cfg = loadConfig()
    intervalSlider.set(cfg.interval); passSlider.set(cfg.passDelay)
    notifySwitch.set(cfg.notify); autoSwitch.set(cfg.autoStart)
    scoreSwitch.set(cfg.showScores)
    audioSwitch.set(cfg.audioEnabled); audioBox.Text = cfg.audioId
    webhookSwitch.set(cfg.webhookEnabled); webhookBox.Text = cfg.webhookUrl
    cfgStatusLabel.Text = "Reloaded"
    cfgStatusLabel.TextColor3 = COL.ok
end)

defaultBtn.MouseButton1Click:Connect(function()
    if killed then return end
    intervalSlider.set(HARD_DEFAULTS.interval)
    passSlider.set(HARD_DEFAULTS.passDelay)
    notifySwitch.set(HARD_DEFAULTS.notify)
    autoSwitch.set(HARD_DEFAULTS.autoStart)
    scoreSwitch.set(HARD_DEFAULTS.showScores)
    audioSwitch.set(false); audioBox.Text = ""
    webhookSwitch.set(false); webhookBox.Text = ""
    cfgStatusLabel.Text = "Defaults applied (not saved)"
    cfgStatusLabel.TextColor3 = COL.warn
end)

refreshBtn.MouseButton1Click:Connect(function()
    if killed then return end
    running = false; scanGen = scanGen + 1
    names = loadNames(); state = loadState(); pruneState(state, names)
    rebuildRows(); updateStatusLine("Stopped")
    cfgStatusLabel.Text = ("Refreshed: %d player(s)"):format(#names)
    cfgStatusLabel.TextColor3 = COL.ok
    logLine(("Refresh: %d players"):format(#names))
end)

resetStateBtn.MouseButton1Click:Connect(function()
    if killed then return end
    resetScanState()
    cfgStatusLabel.Text = "State cleared"
    cfgStatusLabel.TextColor3 = COL.ok
end)

rescanBtn.MouseButton1Click:Connect(function()
    if killed then return end
    cfgStatusLabel.Text = "Rescanning places…"
    cfgStatusLabel.TextColor3 = COL.warn
    refreshPlaces(function(ok, data)
        if killed then return end
        if ok then
            placesLbl.Text = ("%d known"):format(placesCount())
            cfgStatusLabel.Text = ("Places: %d"):format(placesCount())
            cfgStatusLabel.TextColor3 = COL.ok
        else
            cfgStatusLabel.Text = "Rescan failed: " .. tostring(data):sub(1, 80)
            cfgStatusLabel.TextColor3 = COL.error
        end
    end)
end)

addPlaceBtn.MouseButton1Click:Connect(function()
    if killed then return end
    local raw = addPlaceBox.Text
    local idStr, name = raw:match("^(%d+)%s*:?%s*(.-)$")
    local id = tonumber(idStr)
    if not id then
        cfgStatusLabel.Text = "Place: invalid ID"
        cfgStatusLabel.TextColor3 = COL.warn
        return
    end
    if BLOCKED_PLACES[id] then
        cfgStatusLabel.Text = "Blocked: " .. BLOCKED_PLACES[id]
        cfgStatusLabel.TextColor3 = COL.error
        return
    end
    if name == nil or name == "" then name = "Place " .. id end
    places[id] = name
    savePlaces()
    placesLbl.Text = ("%d known"):format(placesCount())
    cfgStatusLabel.Text = ("Added place %d"):format(id)
    cfgStatusLabel.TextColor3 = COL.ok
    addPlaceBox.Text = ""
    logLine(("Manual place add: %d = %s"):format(id, name))
end)

audioTestBtn.MouseButton1Click:Connect(function()
    if killed then return end
    local id = tonumber(cleanAudioId(audioBox.Text))
    if not id or id <= 0 then
        cfgStatusLabel.Text = "Audio: invalid ID"
        cfgStatusLabel.TextColor3 = COL.warn
        return
    end
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. id
    s.Volume = 0.6
    s.Parent = SoundService
    pcall(function() SoundService:PlayLocalSound(s) end)
    pcall(function() s:Play() end)
    task.delay(6, function() pcall(function() s:Destroy() end) end)
    cfgStatusLabel.Text = "Audio test: " .. id
    cfgStatusLabel.TextColor3 = COL.ok
end)

webhookTestBtn.MouseButton1Click:Connect(function()
    if killed then return end
    local url = webhookBox.Text
    if not url:match("^https://discord") then
        cfgStatusLabel.Text = "Webhook: URL must start with https://discord"
        cfgStatusLabel.TextColor3 = COL.warn
        return
    end
    local body = HttpService:JSONEncode({
        username = "UniversalScanner",
        embeds = {{
            title = "Test",
            description = "Universal webhook is wired correctly.",
            color = 0x5A82DC,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
    })
    task.spawn(function()
        local res = httpRequest({
            Url = url, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
        if killed then return end
        if res then
            cfgStatusLabel.Text = "Webhook test sent"
            cfgStatusLabel.TextColor3 = COL.ok
        else
            cfgStatusLabel.Text = "Webhook test failed"
            cfgStatusLabel.TextColor3 = COL.error
        end
    end)
end)

-- ============================================================
-- Resize grip
-- ============================================================
if mainFrame and contentFrame then
    local mainHeight = mainFrame.Size.Y.Offset

    local handle = Instance.new("TextButton")
    handle.Name = "ResizeGrip"
    handle.Size = UDim2.new(0, 16, 0, 16)
    handle.AnchorPoint = Vector2.new(1, 1)
    handle.Position = UDim2.new(1, -2, 1, -2)
    handle.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    handle.BackgroundTransparency = 0.3
    handle.BorderSizePixel = 0
    handle.Font = Enum.Font.Code; handle.TextSize = 12
    handle.TextColor3 = Color3.fromRGB(200, 200, 200)
    handle.Text = "◢"
    handle.Active = true; handle.ZIndex = 200
    handle.Parent = contentFrame
    Instance.new("UICorner", handle).CornerRadius = UDim.new(0, 3)

    local dragging, startMouse, startW, startH = false, nil, 0, 0
    handle.MouseButton1Down:Connect(function()
        if killed then return end
        dragging = true
        startMouse = UserInputService:GetMouseLocation()
        startW = mainFrame.AbsoluteSize.X
        startH = contentFrame.AbsoluteSize.Y
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging or killed then return end
        if not mainFrame.Parent or not contentFrame.Parent then
            dragging = false; return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local cur = UserInputService:GetMouseLocation()
        local dx, dy = cur.X - startMouse.X, cur.Y - startMouse.Y
        local newW = math.clamp(startW + dx, CLAMP.windowW[1], CLAMP.windowW[2])
        local newH = math.clamp(startH + dy, CLAMP.windowH[1], CLAMP.windowH[2])
        mainFrame.Size    = UDim2.new(0, newW, 0, mainHeight)
        contentFrame.Size = UDim2.new(1, 0, 0, newH)
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

-- ============================================================
-- Init
-- ============================================================
rebuildRows()
updateStatusLine("Idle")
if scanTab and scanTab.show then pcall(function() scanTab.show() end) end
task.defer(enforceTabLayout)

_G.Scanner = {
    stop = stopScan, start = startScan, reset = resetScanState,
    kill = killEverything,
    refreshPlaces = function(cb) refreshPlaces(cb) end,
    places = function() return places end,
    placesCount = placesCount,
    blocked = BLOCKED_PLACES,
    addPlace = function(id, name)
        id = tonumber(id); if not id then return false end
        if BLOCKED_PLACES[id] then return false end
        places[id] = name or ("Place " .. id)
        savePlaces()
        return true
    end,
    removePlace = function(id)
        id = tonumber(id); if not id then return false end
        places[id] = nil
        savePlaces()
        return true
    end,
    isRunning = function() return running end,
    isKilled  = function() return killed end,
    names     = function() return names end,
    state     = function() return state end,
    config    = function()
        local c = {}
        for k, v in pairs(cfg) do c[k] = v end
        c.webhookUrl = ""
        return c
    end,
    serverCache = function() return serverCache end,
}