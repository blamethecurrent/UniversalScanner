--[[
    UniversalScanner — rbimgui-2 UI (v13)
    v10: original
    v11: age display, drag-reorder, labeled Scan button, autostart wiring
    v12: sequential skip-fresh scan loop; separate offline/online recheck intervals
    v13: tick-based queue (expired players are scanned on each tick, not the instant
         they expire); per-status expiry; notify + webhook on subplace/server change;
         avatar headshots; up/down/drag reordering; nearly everything configurable in UI
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

-- Numeric settings: each one gets a slider in the Settings tab.
local NUMS = {
    { key = "interval",       label = "Check for updates every (seconds)",          min = 1, max = 60,   def = 5   },
    { key = "batchSize",      label = "Players looked up per check",    min = 1, max = 50,  def = 1   },
    { key = "passDelay",      label = "Pause between lookups in a check (seconds)",   min = 0, max = 60,   def = 1   },
    { key = "expireOnline",   label = "Online result stays current for (seconds)",      min = 5, max = 3600, def = 60  },
    { key = "expireOffline",  label = "Offline result stays current for (seconds)",     min = 1, max = 3600, def = 5   },
    { key = "expireNotFound", label = "Not-found result stays current for (seconds)",   min = 5, max = 3600, def = 120 },
    { key = "expireUnknown",  label = "Failed lookup stays current for (seconds)", min = 1, max = 600, def = 10 },
    { key = "timeout",        label = "Give up on a lookup after (seconds)",        min = 5, max = 120,  def = 30  },
    { key = "retries",        label = "Retry failed lookups (times)",        min = 0, max = 5,    def = 2   },
    { key = "maxBackoff",     label = "Longest wait between retries (seconds)",   min = 5, max = 300,  def = 60  },
    { key = "scoreRefresh",   label = "Refresh game scores every (seconds)",       min = 3, max = 120,  def = 10  },
    { key = "uiScale",        label = "Menu size (percent)",            min = 50, max = 200, def = 100 },
    { key = "scoreTTL",       label = "Keep game scores for (seconds)",     min = 10, max = 600, def = 120 },
}
local NUM_BY_KEY = {}
for _, f in ipairs(NUMS) do NUM_BY_KEY[f.key] = f end

local CLAMP = { windowW = { 380, 800 }, windowH = { 240, 720 } }

local HARD_DEFAULTS = {
    version = 4,
    notify = true, autoStart = true,
    audioEnabled = false, audioId = "",
    webhookEnabled = false, webhookUrl = "",
    showScores = true, showAvatars = true,
    windowW = 470, windowH = 520,
}
for _, f in ipairs(NUMS) do HARD_DEFAULTS[f.key] = f.def end

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
    return (tostring(s or ""):gsub("%D", ""))
end
local function sanitizeConfig(c)
    local out = {
        version        = 4,
        notify         = c.notify    == true,
        autoStart      = c.autoStart == true,
        audioEnabled   = c.audioEnabled == true,
        audioId        = cleanAudioId(c.audioId),
        webhookEnabled = c.webhookEnabled == true,
        webhookUrl     = tostring(c.webhookUrl or ""),
        showScores     = c.showScores ~= false,
        showAvatars    = c.showAvatars ~= false,
        windowW        = clampInt(c.windowW, CLAMP.windowW[1], CLAMP.windowW[2], HARD_DEFAULTS.windowW),
        windowH        = clampInt(c.windowH, CLAMP.windowH[1], CLAMP.windowH[2], HARD_DEFAULTS.windowH),
    }
    for _, f in ipairs(NUMS) do
        out[f.key] = clampInt(c[f.key], f.min, f.max, f.def)
    end
    return out
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
    -- migrate pre-v4 configs
    if (tonumber(d.version) or 0) < 4 then
        if d.expireOffline == nil then d.expireOffline = d.interval end
        if d.expireOnline  == nil then d.expireOnline  = d.onlineRecheck end
    end
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
            d.nextIndex = nil
            d.results   = d.results or {}
            d.userIds   = d.userIds or {}
            return d
        end
    end
    return { version = 3, results = {}, userIds = {} }
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
end

if hasFS and not fileExists(NAMES_PATH) then
    writeFile(NAMES_PATH, "# Universal Scanner — one username per line\n")
end

local cfg   = loadConfig()
local names = loadNames()
local state = loadState()
pruneState(state, names)

-- ============================================================
-- Forward-declared UI handles + live-value getters
-- ============================================================
local numBoxes = {}  -- key -> TextBox for each numeric setting
local notifySwitch, audioSwitch, webhookSwitch, scoreSwitch, autoSwitch, avatarSwitch
local audioBox, webhookBox
local updateStatusLine   -- forward declaration (assigned below)

-- Live value of a numeric setting (text box if it exists, else saved config).
-- Anything typed that isn't a number falls back to the saved value; out-of-range
-- numbers are clamped.
local function getNum(key)
    local f = NUM_BY_KEY[key]
    local b = numBoxes[key]
    local v = b and tonumber(b.Text)
    if type(v) ~= "number" then v = cfg[key] end
    if type(v) ~= "number" then v = f.def end
    return math.clamp(math.floor(v + 0.5), f.min, f.max)
end
-- Live value of a toggle
local function flag(sw, key)
    if sw and sw.on ~= nil then return sw.on == true end
    return cfg[key] == true
end

-- user-id helpers (state-based; no UI needed)
local function knownUserId(name)
    local r = state.results[name]
    if r and tonumber(r.userId) and tonumber(r.userId) > 0 then
        state.userIds[name:lower()] = tonumber(r.userId)
        return tonumber(r.userId)
    end
    return tonumber(state.userIds[name:lower()])
end

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

local function extractServerPopulation(...)
    local seen = {}
    for i = 1, select('#', ...) do
        local v = select(i, ...)
        if type(v) == "table" and not seen[v] then
            seen[v] = true
            local count = tonumber(v.PlayerCount) or tonumber(v.CurrentPlayers) or tonumber(v.Count)
            local max = tonumber(v.MaxPlayers) or tonumber(v.Max) or tonumber(v.Capacity)
            if count and max then return count, max end
            if count and v.MaxPlayers then return count, tonumber(v.MaxPlayers) end
            if v.ServerInfo and type(v.ServerInfo) == "table" then
                local c2 = tonumber(v.ServerInfo.PlayerCount) or tonumber(v.ServerInfo.CurrentPlayers) or tonumber(v.ServerInfo.Count)
                local m2 = tonumber(v.ServerInfo.MaxPlayers) or tonumber(v.ServerInfo.Max) or tonumber(v.ServerInfo.Capacity)
                if c2 and m2 then return c2, m2 end
            end
        end
    end
    return nil, nil
end

local function scanPlayer(name)
    local fn = getReFunction()
    if not fn then return { status = "error", reason = "remote missing" } end
    local ok, a, b, c, d, e, f, g, h, i, j, k =
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
    local playerCount, maxPlayers = extractServerPopulation(a, b, c, d, e, f, g, h, i, j, k)

    if placeId and placeId > 0 then
        local pName, canJoin = placeInfo(placeId)
        return {
            status = "online", placeId = placeId, jobId = jobId,
            userId = userId, displayName = displayName, exactMatch = exactMatch,
            placeName = pName, canJoin = canJoin, at = os.time(),
            playerCount = playerCount, maxPlayers = maxPlayers,
        }
    elseif displayName ~= "" then
        return {
            status = "offline", displayName = displayName, userId = userId,
            exactMatch = exactMatch, at = os.time(),
            playerCount = playerCount, maxPlayers = maxPlayers,
        }
    else
        return { status = "notfound", at = os.time() }
    end
end

local function scanWithTimeout(name)
    local done, result = false, nil
    task.spawn(function() result = scanPlayer(name); done = true end)
    local elapsed, limit = 0, getNum("timeout")
    while not done and elapsed < limit do
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

local function scoreTag(jobId, fallbackCount, fallbackMax)
    local s = serverCache[jobId]
    if flag(scoreSwitch, "showScores") and s and (os.time() - s.at) <= getNum("scoreTTL") then
        local count = tonumber(s.count) or tonumber(fallbackCount) or 0
        local max = tonumber(s.max) or tonumber(fallbackMax) or 0
        if max > 0 or count > 0 then
            return (" · %d/%d"):format(count, max)
        end
    end
    if fallbackCount and fallbackMax and tonumber(fallbackMax) and tonumber(fallbackMax) > 0 then
        return (" · %d/%d"):format(tonumber(fallbackCount), tonumber(fallbackMax))
    end
    return ""
end

-- ============================================================
-- Load UI lib
-- ============================================================
local ImGui
do
    local function fetchLib(url)
        local s = httpRequest({ Url = url, Method = "GET" })
        if not s or #s < 1000 or s:sub(1, 1) == "<" then return nil, s end
        return s
    end
    local src, bad = fetchLib(LIB_URL)
    if not src then
        error(("[Scanner] Could not fetch rbimgui-2 source (got %s)")
            :format(bad and (#bad .. " bytes, starts with '" .. bad:sub(1, 1) .. "'") or "nil"))
    end
    local okLoad, lib = pcall(function() return loadstring(src)() end)
    if not okLoad or not lib then error("[Scanner] Lib load failed: " .. tostring(lib)) end
    ImGui = lib
end

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

-- Current menu zoom (1 = 100%). Used so window sizes stay in unscaled units.
local function getScale()
    local u = mainFrame and mainFrame:FindFirstChildOfClass("UIScale")
    return u and u.Scale or 1
end

-- ============================================================
-- Runtime flags
-- ============================================================
local running     = false
local scanGen     = 0
local currentMode = "Idle"
local killed      = false

-- ============================================================
-- Toast
-- ============================================================
local function toast(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification",
            { Title = title, Text = text, Duration = 4 })
    end)
end

-- ============================================================
-- Audio alert
-- ============================================================
local function playSound(id)
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. id
    s.Volume = 0.6
    s.Parent = SoundService
    pcall(function() SoundService:PlayLocalSound(s) end)
    pcall(function() s:Play() end)
    task.delay(6, function() pcall(function() s:Destroy() end) end)
end

local function playAlert()
    if killed then return end
    if not flag(audioSwitch, "audioEnabled") then return end
    local id = audioBox and tonumber(cleanAudioId(audioBox.Text)) or nil
    if not id or id <= 0 then return end
    playSound(id)
end

-- ============================================================
-- Webhook
-- ============================================================
local function deepLink(placeId, jobId)
    return ("https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s")
        :format(placeId, jobId)
end

local function sendWebhook(payload)
    if killed or not flag(webhookSwitch, "webhookEnabled") then return end
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

local headshotCache = {}
local function fetchHeadshotUrl(uid)
    if not uid then return nil end
    if headshotCache[uid] then return headshotCache[uid] end
    local body = httpRequest({
        Url = ("https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=150x150&format=Png&isCircular=false")
            :format(uid),
        Method = "GET",
    })
    if not body then return nil end
    local ok, d = pcall(function() return HttpService:JSONDecode(body) end)
    local url = ok and type(d) == "table" and d.data and d.data[1] and d.data[1].imageUrl
    if type(url) == "string" and url:sub(1, 4) == "http" then
        headshotCache[uid] = url
        return url
    end
end

local EVENT_STYLE = {
    online   = { title = "Player Online",            color = 0x5ADC82 },
    offline  = { title = "Player Offline",           color = 0xDC5A5A },
    subplace = { title = "Player Changed Subplace",  color = 0x5A82DC },
    server   = { title = "Player Changed Server",    color = 0xDCB45A },
}

local function placeLabel(r)
    if not r then return "?" end
    if r.placeName and r.placeName ~= "" then return r.placeName end
    if r.placeId then return places[r.placeId] or ("Place " .. tostring(r.placeId)) end
    return "?"
end

local function webhookEvent(name, result, prev, event, scoreStr)
    if killed or not flag(webhookSwitch, "webhookEnabled") then return end
    local style = EVENT_STYLE[event]
    if not style then return end

    local who = result.displayName and result.displayName ~= "" and result.displayName or name
    local desc
    if event == "online" then
        desc = ("**%s** is online"):format(who)
    elseif event == "offline" then
        desc = ("**%s** went offline"):format(name)
    elseif event == "subplace" then
        desc = ("**%s** moved: %s → %s"):format(who, placeLabel(prev), placeLabel(result))
    else
        desc = ("**%s** switched servers in %s"):format(who, placeLabel(result))
    end

    local fields = {}
    if event ~= "offline" then
        if event == "subplace" then
            table.insert(fields, { name = "From", value = placeLabel(prev), inline = true })
        end
        table.insert(fields, { name = "Place", value = placeLabel(result), inline = true })
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
        if result.at then
            table.insert(fields, {
                name = "Captured",
                value = ("<t:%d:R>"):format(result.at),
                inline = true,
            })
        end
        if result.placeId and result.jobId and result.jobId ~= "" then
            table.insert(fields, {
                name = "Join",
                value = ("[Click to join](%s)"):format(deepLink(result.placeId, result.jobId)),
            })
        end
    end

    local uid = tonumber(result.userId) or knownUserId(name)
    task.spawn(function()
        local thumb = fetchHeadshotUrl(uid)
        sendWebhook({
            username = "UniversalScanner",
            embeds = {{
                title = style.title, description = desc, color = style.color, fields = fields,
                thumbnail = thumb and { url = thumb } or nil,
                footer = { text = "UF Player Scanner" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }},
        })
    end)
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
local tabItems
do
    local tmp = scanTab.new("label", { text = "" })
    tabItems = tmp.self.Parent
    tmp.self:Destroy()
end

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
playersHeader.Text = "Players (▲▼ or drag ⋮ to reorder):"; playersHeader.Parent = tabItems

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

local dragState = { fromName = nil, toName = nil }
local function rowIndexOf(nm)
    for i, n in ipairs(names) do if n == nm then return i end end
end
local function clearDragHighlight()
    for _, r in pairs(playerRows) do
        if r.row and r.row.Parent then r.row.BackgroundTransparency = 1 end
    end
end

local refreshOne   -- forward declaration; assigned after notifyChange

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

local function relAge(at)
    if not at then return "" end
    local d = os.time() - at
    if d < 0 then d = 0 end
    if d < 60 then return ("%ds ago"):format(d)
    elseif d < 3600 then return ("%dm ago"):format(math.floor(d / 60))
    elseif d < 86400 then return ("%dh ago"):format(math.floor(d / 3600))
    else return ("%dd ago"):format(math.floor(d / 86400)) end
end
local function ageTag(r)
    if not r or not r.at then return "" end
    return "  ·  " .. relAge(r.at)
end

local function formatLabel(name, r)
    local s = r and r.status or "unknown"
    local char = statusChar(s)
    if s == "online" then
        local jobTag = ""
        if r.jobId and #r.jobId >= 6 then
            jobTag = "  ·  " .. string.upper(string.sub(r.jobId, 1, 6))
        end
        local score = scoreTag(r.jobId, r.playerCount, r.maxPlayers)
        local placeTag = ""
        if r.placeName and r.placeName ~= "" then
            placeTag = "  ·  " .. r.placeName
        elseif r.placeId then
            placeTag = "  ·  Place " .. tostring(r.placeId)
        end
        local base
        if r.exactMatch == false and r.displayName then
            base = ("%s %s → %s%s%s%s"):format(
                char, name, r.displayName, jobTag, score, placeTag)
        else
            base = ("%s %s%s%s%s"):format(char, name, jobTag, score, placeTag)
        end
        return base .. ageTag(r)
    elseif s == "offline" then
        local base
        if r.exactMatch == false and r.displayName then
            base = ("%s %s → %s"):format(char, name, r.displayName)
        else
            base = char .. " " .. (r.displayName or name)
        end
        return base .. ageTag(r)
    elseif s == "notfound" then
        return char .. " " .. name .. "  (not found)" .. ageTag(r)
    else
        return char .. " " .. name .. "  " .. (r and r.reason or "?") .. ageTag(r)
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

-- ============================================================
-- Expiry (per status) + staleness
-- ============================================================
local function expiryFor(r)
    local s = r and r.status
    if s == "online"   then return getNum("expireOnline")   end
    if s == "offline"  then return getNum("expireOffline")  end
    if s == "notfound" then return getNum("expireNotFound") end
    return getNum("expireUnknown")
end

local function isStale(name)
    local r = state.results[name]
    if not r or not r.at then return true end
    return (os.time() - r.at) >= expiryFor(r)
end

-- ============================================================
-- Reordering
-- ============================================================
local function applyRowOrder()
    for i, n in ipairs(names) do
        local r = playerRows[n]
        if r and r.row and r.row.Parent then r.row.LayoutOrder = 100 + i end
    end
end

local function moveName(name, newIdx)
    local fi = rowIndexOf(name)
    if not fi or #names < 2 then return end
    newIdx = math.clamp(newIdx, 1, #names)
    if newIdx == fi then return end
    table.remove(names, fi)
    table.insert(names, newIdx, name)
    saveNames(names)
    applyRowOrder()
    logLine(("Moved %s to position %d"):format(name, newIdx))
end

-- ============================================================
-- Avatars
-- ============================================================
local function avatarImage(uid)
    return ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(uid)
end

local resolving, lookupFailedAt = {}, {}
local function updateAvatar(name)
    local r = playerRows[name]
    if not r or not r.avatar or not r.avatar.Parent then return end
    local show = flag(avatarSwitch, "showAvatars")
    r.avatar.Visible = show
    local x = show and 38 or 16
    r.label.Position = UDim2.new(0, x, 0, 0)
    r.label.Size = UDim2.new(1, -(x + 106), 1, 0)
    if not show then return end

    local uid = knownUserId(name)
    if uid then
        local img = avatarImage(uid)
        if r.avatar.Image ~= img then r.avatar.Image = img end
        return
    end
    if resolving[name] then return end
    if lookupFailedAt[name] and (os.time() - lookupFailedAt[name]) < 300 then return end
    resolving[name] = true
    task.spawn(function()
        local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
        resolving[name] = nil
        if killed then return end
        id = ok and tonumber(id) or nil
        if id then
            state.userIds[name:lower()] = id
            saveState(state)
            updateAvatar(name)
        else
            lookupFailedAt[name] = os.time()
        end
    end)
end

local function buildRow(name)
    local row = Instance.new("Frame")
    row.Name = "Row_" .. name; row.LayoutOrder = 100
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1; row.Parent = tabItems

    -- drag grip
    local grip = Instance.new("TextButton")
    grip.Name = "Grip"
    grip.Size = UDim2.new(0, 14, 1, 0)
    grip.BackgroundTransparency = 1
    grip.Font = Enum.Font.Code
    grip.Text = "⋮"; grip.TextSize = 14
    grip.TextColor3 = COL.unknown
    grip.Parent = row
    grip.MouseButton1Down:Connect(function()
        if killed then return end
        dragState.fromName = name
        dragState.toName = nil
    end)

    -- avatar headshot
    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.new(0, 20, 0, 20)
    avatar.Position = UDim2.new(0, 16, 0, 2)
    avatar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    avatar.BorderSizePixel = 0
    avatar.Image = ""
    avatar.Parent = row
    Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Lbl"
    lbl.Size = UDim2.new(1, -144, 1, 0)
    lbl.Position = UDim2.new(0, 38, 0, 0)
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
    local function hoverIn()
        if killed then return end
        lbl.TextColor3 = Color3.new(1, 1, 1)
        if dragState.fromName and dragState.fromName ~= name then
            dragState.toName = name
            row.BackgroundColor3 = COL.btnPrimary
            row.BackgroundTransparency = 0.75
        end
    end
    local function hoverOut()
        if not killed then lbl.TextColor3 = colorForResult(state.results[name]) end
        if dragState.toName == name then
            dragState.toName = nil
            row.BackgroundTransparency = 1
        end
    end
    lbl.MouseEnter:Connect(hoverIn)
    lbl.MouseLeave:Connect(hoverOut)
    avatar.MouseEnter:Connect(function()
        if killed then return end
        if dragState.fromName and dragState.fromName ~= name then
            dragState.toName = name
            row.BackgroundColor3 = COL.btnPrimary
            row.BackgroundTransparency = 0.75
        end
    end)

    local function smallBtn(text, x, w, bg, fg, size)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, 18)
        b.Position = UDim2.new(1, x, 0, 3)
        b.BackgroundColor3 = bg
        b.BorderSizePixel = 0
        b.Font = Enum.Font.Code; b.TextSize = size or 11
        b.TextColor3 = fg
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Text = text; b.Parent = row
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
        return b
    end

    local upBtn   = smallBtn("▲", -102, 18, Color3.fromRGB(40, 45, 65), Color3.fromRGB(200, 210, 240), 10)
    local downBtn = smallBtn("▼", -82,  18, Color3.fromRGB(40, 45, 65), Color3.fromRGB(200, 210, 240), 10)
    local rbtn    = smallBtn("Scan", -60, 34, Color3.fromRGB(30, 50, 80), Color3.fromRGB(150, 200, 255), 11)
    local btn     = smallBtn("×", -24, 22, Color3.fromRGB(70, 30, 30), Color3.fromRGB(255, 150, 150), 12)

    upBtn.MouseButton1Click:Connect(function()
        if killed then return end
        local i = rowIndexOf(name); if i then moveName(name, i - 1) end
    end)
    downBtn.MouseButton1Click:Connect(function()
        if killed then return end
        local i = rowIndexOf(name); if i then moveName(name, i + 1) end
    end)
    rbtn.MouseButton1Click:Connect(function()
        if killed then return end
        if refreshOne then refreshOne(name, rbtn) end
    end)
    btn.MouseButton1Click:Connect(function()
        if killed then return end
        local removedIdx
        for j, n in ipairs(names) do
            if n == name then removedIdx = j; table.remove(names, j); break end
        end
        if not removedIdx then return end
        state.results[name] = nil
        saveNames(names); saveState(state)
        if playerRows[name] then
            pcall(function() playerRows[name].row:Destroy() end)
            playerRows[name] = nil
        end
        applyRowOrder()
        updateTabCanvas(); updateStatusLine()
        logLine("Removed " .. name)
    end)

    return { row = row, label = lbl, button = btn, refresh = rbtn, avatar = avatar }
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
        updateAvatar(name)
    end
    updateTabCanvas()
end

local function ensureRow(name)
    if playerRows[name] then return playerRows[name] end
    local r = buildRow(name)
    r.row.LayoutOrder = 100 + #names
    playerRows[name] = r
    updateAvatar(name)
    updateTabCanvas()
    return r
end

local function updatePlayerLabel(name, result)
    local r = playerRows[name]
    if not r or not r.label.Parent then return end
    r.label.Text = formatLabel(name, result)
    r.label.TextColor3 = colorForResult(result)
    updateAvatar(name)
end

-- keep relative ages moving; also apply avatar toggle changes
local lastAgeTick = 0
local avatarsShown = nil
RunService.Heartbeat:Connect(function()
    if killed then return end
    local now = tick()
    if now - lastAgeTick < 1 then return end
    lastAgeTick = now
    for name, r in pairs(playerRows) do
        if r.label and r.label.Parent then
            local t = formatLabel(name, state.results[name])
            if r.label.Text ~= t then r.label.Text = t end
        end
    end
    local want = flag(avatarSwitch, "showAvatars")
    if want ~= avatarsShown then
        avatarsShown = want
        for name in pairs(playerRows) do updateAvatar(name) end
    end
end)

function updateStatusLine(mode, extra)
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
        local staleCount = 0
        for _, n in ipairs(names) do
            if isStale(n) then staleCount = staleCount + 1 end
        end
        if staleCount > 0 then
            tail = ("%d/%d expired"):format(staleCount, #names)
        else
            tail = "all fresh"
        end
    end
    statusLbl.Text = ("%s  ●%d ○%d ?%d  ·  %s")
        :format(currentMode, online, offline, unknown, tail)
    local color = COL.idle
    if     currentMode == "Running"  then color = COL.running
    elseif currentMode == "Sleeping" then color = COL.sleeping
    elseif currentMode == "Stopped"  then color = COL.stopped
    elseif currentMode == "Error"    then color = COL.error end
    statusLbl.TextColor3 = color
end

-- ============================================================
-- Drag commit
-- ============================================================
local function commitDrag()
    local from, to = dragState.fromName, dragState.toName
    dragState.fromName, dragState.toName = nil, nil
    clearDragHighlight()
    if not from or not to or from == to then return end
    local ti = rowIndexOf(to)
    if not ti then return end
    moveName(from, ti)
    updateStatusLine()
end

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and dragState.fromName then
        commitDrag()
    end
end)

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
-- Notifications (online / offline / subplace / server change)
-- ============================================================
local function detectEvent(prev, result)
    local prevStatus = prev and prev.status or nil
    if result.status == "online" then
        if prevStatus ~= "online" then return "online" end
        if prev.placeId and result.placeId and prev.placeId ~= result.placeId then
            return "subplace"
        end
        if prev.jobId and prev.jobId ~= "" and result.jobId and result.jobId ~= ""
            and prev.jobId ~= result.jobId then
            return "server"
        end
    elseif result.status == "offline" and prevStatus == "online" then
        return "offline"
    end
    return nil
end

local function notifyChange(name, result, prev)
    if killed then return end
    local event = detectEvent(prev, result)
    if not event then return end

    local scoreStr = ""
    if result.status == "online" and result.jobId then
        local s = serverCache[result.jobId]
        if s and (os.time() - s.at) <= getNum("scoreTTL") then
            scoreStr = ("Q%d %d:%02d · %d-%d")
                :format(s.quarter, s.minutes, s.seconds, s.home, s.away)
        elseif result.playerCount and result.maxPlayers and tonumber(result.maxPlayers)
            and tonumber(result.maxPlayers) > 0 then
            scoreStr = ("%d/%d"):format(tonumber(result.playerCount), tonumber(result.maxPlayers))
        end
    end

    if flag(notifySwitch, "notify") then
        local who = result.exactMatch == false
            and ("'" .. name .. "' → '" .. (result.displayName or "?") .. "'")
            or name
        if event == "online" then
            local where = result.placeName and (" in " .. result.placeName) or ""
            logLine("ONLINE " .. who .. where)
            toast("Player Online", who .. where)
        elseif event == "offline" then
            logLine("OFFLINE " .. name)
            toast("Player Offline", name .. " went offline")
        elseif event == "subplace" then
            local msg = ("%s: %s → %s"):format(who, placeLabel(prev), placeLabel(result))
            logLine("SUBPLACE " .. msg)
            toast("Changed Subplace", msg)
        elseif event == "server" then
            local msg = ("%s switched servers in %s"):format(who, placeLabel(result))
            logLine("SERVER " .. msg)
            toast("Changed Server", msg)
        end
    end

    if event ~= "offline" then playAlert() end
    webhookEvent(name, result, prev, event, scoreStr)
end

-- ============================================================
-- Manual single-player scan
-- ============================================================
local refreshing = {}
refreshOne = function(name, btn)
    if killed or refreshing[name] then return end
    refreshing[name] = true
    if btn and btn.Parent then btn.Text = "…" end
    local prev = state.results[name]
    task.spawn(function()
        local result = scanWithTimeout(name)
        refreshing[name] = nil
        if btn and btn.Parent then btn.Text = "Scan" end
        if killed then return end
        if result.status == "error" then
            logLine(("Manual refresh failed for %s: %s"):format(name, result.reason or "?"))
            return
        end
        state.results[name] = result
        saveState(state)
        notifyChange(name, result, prev)
        updatePlayerLabel(name, result)
        updateStatusLine()
    end)
end

-- ============================================================
-- Scan loop — tick-based queue
--   Every tick: collect expired players, scan them one by one.
-- ============================================================
local function stopScan()
    running = false; scanGen = scanGen + 1
    updateStatusLine("Stopped")
end

local function alive(myGen)
    return running and scanGen == myGen and not killed
end

local function interruptibleSleep(seconds, myGen, tailLabel, mode)
    mode = mode or "Sleeping"
    local endAt = tick() + seconds
    while alive(myGen) do
        local left = endAt - tick()
        if left <= 0 then break end
        updateStatusLine(mode, ("%s in %ds"):format(tailLabel, math.ceil(left)))
        task.wait(math.min(0.5, left))
    end
    if alive(myGen) then currentMode = "Running" end
end

-- Minimum gap between consecutive scans.
local lastScanAt = 0
local function applyScanGap(myGen)
    local gap = getNum("passDelay")
    if gap <= 0 then return true end
    local remaining = gap - (tick() - lastScanAt)
    if remaining <= 0 then return true end
    interruptibleSleep(remaining, myGen, "next scan", "Running")
    return alive(myGen)
end

-- Pick the players that are most overdue for a lookup (never-checked first),
-- up to `limit`. Ties follow list order. Also returns how many are waiting.
local function nextBatch(limit)
    local now = os.time()
    local cands = {}
    for i, name in ipairs(names) do
        local r = state.results[name]
        local overdue
        if not r or not r.at then overdue = math.huge
        else overdue = (now - r.at) - expiryFor(r) end
        if overdue >= 0 then cands[#cands + 1] = { name = name, overdue = overdue, idx = i } end
    end
    table.sort(cands, function(a, b)
        if a.overdue ~= b.overdue then return a.overdue > b.overdue end
        return a.idx < b.idx
    end)
    local out = {}
    for i = 1, math.min(limit, #cands) do out[i] = cands[i].name end
    return out, #cands
end

local function scanLoop(myGen)
    while alive(myGen) do
        if #names == 0 then return end
        local tickStart = tick()

        -- Take the next few players off the queue (most overdue first).
        local queue, waiting = nextBatch(getNum("batchSize"))

        for qi, name in ipairs(queue) do
            if not alive(myGen) then break end
            -- skip if removed meanwhile, or refreshed manually meanwhile
            if rowIndexOf(name) and isStale(name) then
                if not applyScanGap(myGen) then break end
                updateStatusLine("Running", ("looking up %s (%d waiting)"):format(name, math.max(0, waiting - qi + 1)))

                local prev = state.results[name]
                local base = getNum("interval")
                local maxRetries = getNum("retries")

                local result, attempt = nil, 0
                while true do
                    result = scanWithTimeout(name)
                    if result.status ~= "error" then break end
                    attempt = attempt + 1
                    if attempt > maxRetries then break end
                    local waitS = math.min(base * (2 ^ attempt), getNum("maxBackoff"))
                    logLine(("Retry %d/%d for %s in %.0fs — %s")
                        :format(attempt, maxRetries, name, waitS, result.reason or "?"))
                    interruptibleSleep(waitS, myGen, "retrying " .. name)
                    if not alive(myGen) then break end
                end
                if not alive(myGen) then break end

                if result.status == "error" then
                    state.results[name] = {
                        status = "unknown", reason = result.reason, at = os.time(),
                    }
                    logLine("UNKNOWN " .. name .. " — " .. (result.reason or "?"))
                else
                    state.results[name] = result
                    if result.userId and result.userId > 0 then
                        state.userIds[name:lower()] = result.userId
                    end
                    notifyChange(name, result, prev)
                end
                updatePlayerLabel(name, state.results[name])
                saveState(state)
                lastScanAt = tick()

                local now = os.time()
                if flag(scoreSwitch, "showScores") and (now - lastServerFetch) >= getNum("scoreRefresh") then
                    lastServerFetch = now
                    task.spawn(fetchServerPage)
                end
            end
        end

        if not alive(myGen) then break end

        -- Wait out the rest of the tick before checking for expired players again.
        local remain = getNum("interval") - (tick() - tickStart)
        if remain > 0 then
            interruptibleSleep(remain, myGen, "next check", "Running")
        else
            task.wait(0.1)
        end
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
    state = { version = 3, results = {}, userIds = state.userIds or {} }
    saveState(state)
    for name in pairs(playerRows) do
        local r = playerRows[name]
        if r and r.label.Parent then
            r.label.Text = "? " .. name
            r.label.TextColor3 = COL.unknown
        end
    end
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

        local mine = findMainFrame(WIN_TITLE)
        if mine then mine:Destroy() end

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

-- ============================================================
-- SETTINGS TAB
-- Built and wired entirely inside do-blocks so the widget locals
-- are released afterwards (executors/Luau cap a function at 200 locals).
-- ============================================================
do
local settingsTab = window.new({ text = "Settings" })
local settingsItems
do
    local stmp = settingsTab.new("label", { text = "" })
    settingsItems = stmp.self.Parent
    stmp.self:Destroy()
end

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

local function hintLabel(text, h)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, h or 28)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code; l.TextSize = 10
    l.TextColor3 = COL.unknown
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
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

local function makeRow(h)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, h); row.BackgroundTransparency = 1
    row.Parent = settingsItems
    return row
end

local function makeInput(parent, placeholder, text, size)
    local box = Instance.new("TextBox")
    box.Size = size
    box.BackgroundColor3 = COL.bgInput
    box.BorderSizePixel = 0
    box.Font = Enum.Font.Code
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    box.Text = text or ""
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 12; box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false; box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
    Instance.new("UIPadding", box).PaddingLeft = UDim.new(0, 8)
    return box
end

-- Text row with optional trailing button -> returns box, button
local function makeTextRow(placeholder, defaultText, btnText)
    local row = makeRow(26)
    local box = makeInput(row, placeholder, defaultText,
        UDim2.new(1, btnText and -72 or 0, 1, 0))
    local btn
    if btnText then
        btn = makeSizedBtn(row, btnText, 0, 64, COL.btnMuted)
        btn.Position = UDim2.new(1, -64, 0, 0)
    end
    return box, btn
end

local function makeNumInput(key)
    local f = NUM_BY_KEY[key]
    local row = makeRow(26)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -86, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Code; lbl.TextSize = 12
    lbl.TextColor3 = COL.row
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = ("%s  [%d–%d]"):format(f.label, f.min, f.max)
    lbl.Parent = row
    local box = makeInput(row, tostring(f.def), tostring(cfg[key]), UDim2.new(0, 80, 1, 0))
    box.Position = UDim2.new(1, -80, 0, 0)
    box.TextXAlignment = Enum.TextXAlignment.Center
    -- tidy whatever was typed into a valid, in-range whole number
    box.FocusLost:Connect(function()
        box.Text = tostring(getNum(key))
    end)
    numBoxes[key] = box
end

local W = {}             -- widgets wired later
local cfgStatusLabel     -- created in the Config section
local function setStatus(text, color)
    cfgStatusLabel.Text = text
    cfgStatusLabel.TextColor3 = color
end

-- General toggles
sectionLabel("General")
notifySwitch = settingsTab.new("switch", { text = "Show in-game notifications", on = cfg.notify })
autoSwitch   = settingsTab.new("switch", { text = "Start automatically", on = cfg.autoStart })
scoreSwitch  = settingsTab.new("switch", { text = "Show game scores", on = cfg.showScores })
avatarSwitch = settingsTab.new("switch", { text = "Show player avatars", on = cfg.showAvatars })

sectionLabel("Appearance")
makeNumInput("uiScale")

sectionLabel("Checking")
makeNumInput("interval")
makeNumInput("batchSize")
makeNumInput("passDelay")
hintLabel("At each check, the players whose results are most out of date are looked up, one at a time, "
    .. "up to the limit above (default 1, to avoid overloading the game). If several are equally "
    .. "overdue, the higher one in your list goes first.", 52)

sectionLabel("How long each result stays current")
makeNumInput("expireOnline")
makeNumInput("expireOffline")
makeNumInput("expireNotFound")
makeNumInput("expireUnknown")
hintLabel("Once a result is older than its time here, the player is looked up again at the next check.", 28)

sectionLabel("Connection")
makeNumInput("timeout")
makeNumInput("retries")
makeNumInput("maxBackoff")

sectionLabel("Game scores")
makeNumInput("scoreRefresh")
makeNumInput("scoreTTL")

sectionLabel("Sound alert (player comes online or moves)")
audioSwitch = settingsTab.new("switch", { text = "Play a sound on changes", on = cfg.audioEnabled })
audioBox, W.audioTest = makeTextRow("Roblox audio ID (numbers only)", cfg.audioId, "Test")

sectionLabel("Discord webhook")
webhookSwitch = settingsTab.new("switch", { text = "Send a Discord message on changes", on = cfg.webhookEnabled })
webhookBox, W.webhookTest = makeTextRow("https://discord.com/api/webhooks/…", cfg.webhookUrl, "Test")

-- Config save / reload / defaults
sectionLabel("Save settings")
cfgStatusLabel = Instance.new("TextLabel")
cfgStatusLabel.Size = UDim2.new(1, 0, 0, 16)
cfgStatusLabel.BackgroundTransparency = 1
cfgStatusLabel.Font = Enum.Font.Code; cfgStatusLabel.TextSize = 11
cfgStatusLabel.TextColor3 = COL.idle
cfgStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
cfgStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
cfgStatusLabel.Text = "Ready"; cfgStatusLabel.Parent = settingsItems

do
    local saveRow = makeRow(28)
    local saveBtn    = makeSizedBtn(saveRow, "Save",    0,   70)
    local reloadBtn  = makeSizedBtn(saveRow, "Load saved",  74,  90)
    local defaultBtn = makeSizedBtn(saveRow, "Defaults",168, 80)

    local function currentUIAsConfig()
        local c = {
            notify    = notifySwitch.on,
            autoStart = autoSwitch.on,
            showScores = scoreSwitch.on,
            showAvatars = avatarSwitch.on,
            audioEnabled = audioSwitch.on,
            audioId = audioBox.Text,
            webhookEnabled = webhookSwitch.on,
            webhookUrl = webhookBox.Text,
            windowW   = mainFrame and math.floor(mainFrame.AbsoluteSize.X / getScale()) or cfg.windowW,
            windowH   = contentFrame and math.floor(contentFrame.AbsoluteSize.Y / getScale()) or cfg.windowH,
        }
        for _, f in ipairs(NUMS) do c[f.key] = getNum(f.key) end
        return c
    end

    local function applyConfigToUI(c)
        for _, f in ipairs(NUMS) do
            if numBoxes[f.key] then numBoxes[f.key].Text = tostring(c[f.key]) end
        end
        notifySwitch.set(c.notify); autoSwitch.set(c.autoStart)
        scoreSwitch.set(c.showScores); avatarSwitch.set(c.showAvatars)
        audioSwitch.set(c.audioEnabled); audioBox.Text = c.audioId
        webhookSwitch.set(c.webhookEnabled); webhookBox.Text = c.webhookUrl
    end

    saveBtn.MouseButton1Click:Connect(function()
        if killed then return end
        cfg = sanitizeConfig(currentUIAsConfig()); saveConfig(cfg)
        audioBox.Text = cfg.audioId
        webhookBox.Text = cfg.webhookUrl
        for _, f in ipairs(NUMS) do numBoxes[f.key].Text = tostring(cfg[f.key]) end
        setStatus("Saved  " .. timestamp(), COL.ok)
        logLine("Config saved")
    end)

    reloadBtn.MouseButton1Click:Connect(function()
        if killed then return end
        cfg = loadConfig()
        applyConfigToUI(cfg)
        setStatus("Reloaded", COL.ok)
    end)

    defaultBtn.MouseButton1Click:Connect(function()
        if killed then return end
        local d = sanitizeConfig(HARD_DEFAULTS)
        d.audioEnabled = false; d.audioId = ""
        d.webhookEnabled = false; d.webhookUrl = ""
        applyConfigToUI(d)
        setStatus("Defaults applied (not saved)", COL.warn)
    end)
end

-- Files & places
sectionLabel("Data & game places")
do
    local fileRow = makeRow(28)
    local refreshBtn    = makeSizedBtn(fileRow, "Reload name list", 0,   130)
    local resetStateBtn = makeSizedBtn(fileRow, "Clear results",   134, 100, COL.btnMuted)

    local placesRow = makeRow(28)
    local rescanBtn = makeSizedBtn(placesRow, "Update place list", 0, 130)
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

    local addPlaceRow = makeRow(26)
    local addPlaceBox = makeInput(addPlaceRow, "Place ID, or 'ID: Name'", "",
        UDim2.new(1, -144, 1, 0))
    local addPlaceBtn = makeSizedBtn(addPlaceRow, "Add", 0, 64)
    addPlaceBtn.Position = UDim2.new(1, -140, 0, 0)
    local removePlaceBtn = makeSizedBtn(addPlaceRow, "Remove", 0, 70, COL.btnStop)
    removePlaceBtn.Position = UDim2.new(1, -70, 0, 0)

    hintLabel("Files: UniversalScanner/ (config, names, state, places, log)", 16)

    local killRow = makeRow(34)
    local killFullBtn = makeSizedBtn(killRow, "CLOSE SCRIPT", 0, 220, COL.btnKill)

    -- ---- wiring ----
    killFullBtn.MouseButton1Click:Connect(killEverything)

    refreshBtn.MouseButton1Click:Connect(function()
        if killed then return end
        running = false; scanGen = scanGen + 1
        names = loadNames(); state = loadState(); pruneState(state, names)
        rebuildRows(); updateStatusLine("Stopped")
        setStatus(("Refreshed: %d player(s)"):format(#names), COL.ok)
        logLine(("Refresh: %d players"):format(#names))
    end)

    resetStateBtn.MouseButton1Click:Connect(function()
        if killed then return end
        resetScanState()
        setStatus("State cleared", COL.ok)
    end)

    rescanBtn.MouseButton1Click:Connect(function()
        if killed then return end
        setStatus("Rescanning places…", COL.warn)
        refreshPlaces(function(ok, data)
            if killed then return end
            if ok then
                placesLbl.Text = ("%d known"):format(placesCount())
                setStatus(("Places: %d"):format(placesCount()), COL.ok)
            else
                setStatus("Rescan failed: " .. tostring(data):sub(1, 80), COL.error)
            end
        end)
    end)

    addPlaceBtn.MouseButton1Click:Connect(function()
        if killed then return end
        local idStr, name = addPlaceBox.Text:match("^(%d+)%s*:?%s*(.-)$")
        local id = tonumber(idStr)
        if not id then setStatus("Place: invalid ID", COL.warn); return end
        if BLOCKED_PLACES[id] then
            setStatus("Blocked: " .. BLOCKED_PLACES[id], COL.error); return
        end
        if name == nil or name == "" then name = "Place " .. id end
        places[id] = name
        savePlaces()
        placesLbl.Text = ("%d known"):format(placesCount())
        setStatus(("Added place %d"):format(id), COL.ok)
        addPlaceBox.Text = ""
        logLine(("Manual place add: %d = %s"):format(id, name))
    end)

    removePlaceBtn.MouseButton1Click:Connect(function()
        if killed then return end
        local id = tonumber(addPlaceBox.Text:match("^%s*(%d+)"))
        if not id then setStatus("Place: enter an ID to remove", COL.warn); return end
        if not places[id] then
            setStatus(("Place %d not in list"):format(id), COL.warn); return
        end
        places[id] = nil
        savePlaces()
        placesLbl.Text = ("%d known"):format(placesCount())
        setStatus(("Removed place %d"):format(id), COL.ok)
        addPlaceBox.Text = ""
        logLine(("Manual place remove: %d"):format(id))
    end)
end

W.audioTest.MouseButton1Click:Connect(function()
    if killed then return end
    local id = tonumber(cleanAudioId(audioBox.Text))
    if not id or id <= 0 then setStatus("Audio: invalid ID", COL.warn); return end
    playSound(id)
    setStatus("Audio test: " .. id, COL.ok)
end)

W.webhookTest.MouseButton1Click:Connect(function()
    if killed then return end
    local url = webhookBox.Text
    if not url:match("^https://discord") then
        setStatus("Webhook: URL must start with https://discord", COL.warn)
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
        if res then setStatus("Webhook test sent", COL.ok)
        else setStatus("Webhook test failed", COL.error) end
    end)
end)
end -- settings do-block

-- ============================================================
-- Menu zoom (UIScale on the window, follows the "Menu size" setting live)
-- ============================================================
if mainFrame then
    local u = Instance.new("UIScale")
    u.Scale = getNum("uiScale") / 100
    u.Parent = mainFrame
    RunService.Heartbeat:Connect(function()
        if killed or not u.Parent then return end
        local want = getNum("uiScale") / 100
        if u.Scale ~= want then u.Scale = want end
    end)
end

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
        startW = mainFrame.AbsoluteSize.X / getScale()
        startH = contentFrame.AbsoluteSize.Y / getScale()
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging or killed then return end
        if not mainFrame.Parent or not contentFrame.Parent then
            dragging = false; return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local cur = UserInputService:GetMouseLocation()
        local sc = getScale()
        local dx, dy = (cur.X - startMouse.X) / sc, (cur.Y - startMouse.Y) / sc
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

if cfg.autoStart and #names > 0 then
    task.defer(startScan)
end

_G.Scanner = {
    stop = stopScan, start = startScan, reset = resetScanState,
    kill = killEverything,
    refreshOne = function(n) if refreshOne then refreshOne(n) end end,
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