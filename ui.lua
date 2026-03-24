-- ============================================================
-- fishit_main.lua  —  MAIN ENTRY POINT
-- Load data ikan + UI dari GitHub raw URL
-- Jalankan file INI saja di executor
-- ============================================================

-- ============================================================
-- !! GANTI URL INI dengan raw GitHub URL file kamu !!
-- Contoh format raw GitHub URL:
--   https://raw.githubusercontent.com/<user>/<repo>/<branch>/fishit_data.lua
--   https://raw.githubusercontent.com/<user>/<repo>/<branch>/fishit_ui.lua
-- ============================================================
local DATA_URL = "https://raw.githubusercontent.com/AskMeMaybe/testrbx/refs/heads/main/data.lua"
local UI_URL   = "https://raw.githubusercontent.com/AskMeMaybe/testrbx/refs/heads/main/ui.lua"

-- ============================================================
-- KONFIGURASI (bisa diubah lewat UI juga)
-- ============================================================
local VPS_URL  = "http://152.42.234.192:3422/notify"
local COOLDOWN = 1

-- Auto Weather
local AUTO_WEATHER_ENABLED = {}    -- { ["Storm"]=true, ... }
local AUTO_WEATHER_RUNNING = false

-- Auto Sell
local AUTO_SELL_ENABLED  = false
local AUTO_SELL_INTERVAL = 600     -- dalam detik (default 10 menit)
local AUTO_SELL_RUNNING  = false

-- Tier minimum untuk notif (warna chat = tier sesungguhnya)
-- 8=FORGOTTEN, 7=SECRET, 6=MYTHIC, 5=LEGENDARY, 4=EPIC
local MIN_TIER = 7

local ANTI_AFK_ENABLED   = false
local AFK_NOTIFY_ENABLED = true
local AFK_CHECK_INTERVAL = 8 * 60
local AFK_TIMEOUT        = 15 * 60
local DC_NOTIFY_ENABLED  = true
local DC_REJOIN_TIMEOUT  = 5 * 60

-- ============================================================
-- LOAD DATA dari GitHub
-- ============================================================
print("[FishIt] Mengunduh data ikan dari GitHub...")
local dataOk, DATA = pcall(function()
    return loadstring(game:HttpGet(DATA_URL))()
end)
if not dataOk or not DATA then
    warn("[FishIt] GAGAL load data ikan! Cek URL DATA_URL.")
    warn(tostring(DATA))
    return
end
print("[FishIt] Data ikan berhasil dimuat.")

local SecretFishData   = DATA.SecretFishData
local TIER_NAMES       = DATA.TIER_NAMES
local RGB_RARITY       = DATA.RGB_RARITY
local FOCUS_FISH       = DATA.FOCUS_FISH       -- table by reference (UI bisa edit ini)
local CRYSTALIZED_FISH = DATA.CRYSTALIZED_FISH
local WEATHER_LIST     = DATA.WEATHER_LIST or {}
local MUTATIONS        = DATA.MUTATIONS or {}

-- ============================================================
-- SERVICES
-- ============================================================
local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================
local function stripRichText(t) return t:gsub("<.->", "") end

local function extractPlayer(text)
    local clean = stripRichText(text)
    return clean:match("^%[Server%]:%s*(.-)%s*obtained")
        or clean:match("^(.-)%s*obtained")
        or "Unknown"
end

local function detectFishAndWeight(text)
    local clean = stripRichText(text)
    local openParen = clean:match("^.*()%(")
    local fish, weight
    if openParen then
        local fishPart   = clean:sub(1, openParen - 1)
        local weightPart = clean:sub(openParen + 1)
        fish   = fishPart:match("obtained%s+a[n]?%s+(.+)")
                 or fishPart:match("obtained%s+(.+)")
        weight = weightPart:match("^(.-)%)")
    else
        fish   = clean:match("obtained%s+a[n]?%s+(.+)")
                 or clean:match("obtained%s+(.+)")
        weight = "-"
    end
    if fish then
        fish = fish:gsub("%s*with a 1 in.*$", "")
        fish = fish:gsub("%s+$", "")
    end
    return (fish or "Unknown Fish"), (weight or "-")
end

local function detectChance(text)
    return text:match("1 in ([%dKMB%.]+)") or "?"
end

local function getTierFromColor(rawMsg)
    local r, g, b = rawMsg:match("rgb%((%d+),%s*(%d+),%s*(%d+)%)")
    if not r then return nil end
    local key = r .. "," .. g .. "," .. b
    return RGB_RARITY[key] or nil
end

-- ============================================================
-- SEND TO VPS
-- ============================================================
local lastNotif = 0

local function sendToVPS(eventType, data)
    data.event = eventType
    local req = request or (syn and syn.request) or http_request
    if not req then warn("[FishIt] request() tidak tersedia"); return end
    task.spawn(function()
        local ok, err = pcall(function()
            req({
                Url     = VPS_URL,
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = HttpService:JSONEncode(data),
            })
            print(("[FishIt] [%s] → VPS"):format(eventType))
        end)
        if not ok then
            warn(("[FishIt] [%s] Error: %s"):format(eventType, tostring(err)))
        end
    end)
end

-- ============================================================
-- STATE
-- ============================================================
local playerActivity = {}
local afkNotifSent   = {}
local dcPending      = {}   -- guard: cegah duplicate DC timer per player

for _, p in ipairs(Players:GetPlayers()) do
    playerActivity[p.Name] = tick()
end

Players.PlayerAdded:Connect(function(p)
    playerActivity[p.Name] = tick()
    afkNotifSent[p.Name]   = false
    print("[FishIt] Player JOIN: " .. p.Name)
end)

Players.PlayerRemoving:Connect(function(p)
    local name = p.Name
    playerActivity[name] = nil
    afkNotifSent[name]   = nil
    print("[FishIt] Player LEAVE: " .. name)

    if DC_NOTIFY_ENABLED then
        -- Guard: batalkan jika DC timer untuk player ini sudah berjalan
        if dcPending[name] then
            print("[FishIt] DC timer untuk " .. name .. " sudah aktif, diabaikan")
            return
        end
        dcPending[name] = true
        task.delay(DC_REJOIN_TIMEOUT, function()
            dcPending[name] = nil  -- hapus guard setelah selesai
            if not DC_NOTIFY_ENABLED then return end
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl.Name == name then return end
            end
            sendToVPS("dc", {
                player  = name,
                minutes = math.floor(DC_REJOIN_TIMEOUT / 60),
                message = name .. " belum kembali setelah " .. math.floor(DC_REJOIN_TIMEOUT / 60) .. " menit",
            })
        end)
    end
end)

-- ============================================================
-- FITUR 1: PARSE CHAT & KIRIM NOTIF
-- ============================================================
local function OnNewMessage(rawMsg)
    if not rawMsg or not rawMsg:find("obtained") then return end

    local player           = extractPlayer(rawMsg)
    local fishName, weight = detectFishAndWeight(rawMsg)
    local chance           = detectChance(rawMsg)
    local tierNum          = getTierFromColor(rawMsg)
    local tierName         = tierNum and (TIER_NAMES[tierNum] or "UNKNOWN") or "UNKNOWN"

    local assetId          = SecretFishData[fishName]
    local baseFishName     = fishName

    if not assetId then
        local currentName = fishName
        local changed = true
        while changed and not assetId do
            changed = false
            for _, mut in ipairs(MUTATIONS) do
                if currentName:sub(1, #mut + 1):lower() == mut:lower() .. " " then
                    currentName = currentName:sub(#mut + 2)
                    changed = true
                    break
                end
            end
            if SecretFishData[currentName] then
                assetId = SecretFishData[currentName]
                baseFishName = currentName
            end
        end
    end

    local lowerFish        = fishName:lower()

    if player ~= "Unknown" then
        playerActivity[player] = tick()
        afkNotifSent[player]   = false
    end

    print(("[FishIt] %s | %s | %s | 1 in %s"):format(player, fishName, tierName, chance))

    -- Cek Crystalized
    if lowerFish:find("crystalized") then
        for _, allowed in ipairs(CRYSTALIZED_FISH) do
            if lowerFish:find(allowed:lower()) then
                sendToVPS("caught", {
                    fish    = fishName,
                    player  = player,
                    weight  = weight,
                    chance  = chance,
                    tier    = "CRYSTALIZED",
                    assetId = assetId and tostring(assetId) or nil,
                })
                return
            end
        end
        return
    end

    -- Cek FOCUS_FISH
    for focusFish in pairs(FOCUS_FISH) do
        if lowerFish:find(focusFish:lower()) then
            sendToVPS("caught", {
                fish    = fishName,
                player  = player,
                weight  = weight,
                chance  = chance,
                tier    = tierName,
                assetId = assetId and tostring(assetId) or nil,
            })
            return
        end
    end

    -- Filter tier minimum
    if not tierNum or tierNum < MIN_TIER then return end

    -- Cooldown
    local now = tick()
    if now - lastNotif < COOLDOWN then return end
    lastNotif = now

    sendToVPS("caught", {
        fish    = fishName,
        player  = player,
        weight  = weight,
        chance  = chance,
        tier    = tierName,
        assetId = assetId and tostring(assetId) or nil,
    })
end

-- ============================================================
-- FITUR 2: HOOK CHAT
-- ============================================================
local function HookChat()
    local tcs = game:GetService("TextChatService")
    local ok = pcall(function()
        tcs.OnIncomingMessage = function(msg)
            if msg and msg.Text then
                OnNewMessage(msg.Text)
            end
        end
    end)
    if ok then
        print("[FishIt] Chat hook: OnIncomingMessage aktif")
    else
        pcall(function()
            local evFolder = game:GetService("ReplicatedStorage")
                :FindFirstChild("DefaultChatSystemChatEvents")
            if evFolder then
                local ev = evFolder:FindFirstChild("OnMessageDoneFiltering")
                if ev then
                    ev.OnClientEvent:Connect(function(d)
                        if d and d.MessageType == "System" then
                            OnNewMessage(d.Message or "")
                        end
                    end)
                    print("[FishIt] Chat hook: Legacy fallback aktif")
                end
            end
        end)
    end
end

-- ============================================================
-- FITUR 3: ANTI-AFK
-- ============================================================
local function startAntiAfk()
    if not ANTI_AFK_ENABLED then return end
    if getconnections then
        for _, c in pairs(getconnections(localPlayer.Idled)) do
            if c["Disable"] then c["Disable"](c)
            elseif c["Disconnect"] then c["Disconnect"](c) end
        end
        print("[FishIt] Anti-AFK aktif")
    end
end

-- Track input lokal agar localPlayer tidak false positive AFK
do
    local UIS2 = game:GetService("UserInputService")
    UIS2.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch
            or inp.KeyCode == Enum.KeyCode.E
            or inp.KeyCode == Enum.KeyCode.F
        then
            playerActivity[localPlayer.Name] = tick()
            afkNotifSent[localPlayer.Name]   = false
        end
    end)
end

-- ============================================================
-- FITUR 4: AFK MONITOR
-- ============================================================
local function startAfkMonitor()
    task.spawn(function()
        while true do
            task.wait(AFK_CHECK_INTERVAL)
            if AFK_NOTIFY_ENABLED then
                local now = tick()
                for _, p in ipairs(Players:GetPlayers()) do
                    local lastActive = playerActivity[p.Name]
                    if lastActive then
                        local idleSec = now - lastActive
                        if idleSec >= AFK_TIMEOUT and not afkNotifSent[p.Name] then
                            afkNotifSent[p.Name] = true
                            local idleMin = math.floor(idleSec / 60)
                            print("[FishIt] AFK: " .. p.Name .. " tidak mancing " .. idleMin .. " menit")
                            sendToVPS("afk", {
                                player  = p.Name,
                                idleMin = idleMin,
                                message = p.Name .. " tidak memancing selama " .. idleMin .. " menit!",
                            })
                        elseif idleSec < AFK_TIMEOUT then
                            afkNotifSent[p.Name] = false
                        end
                    end
                end
            end
        end
    end)
    print("[FishIt] AFK Monitor aktif")
end

-- ============================================================
-- FITUR 4b: ACTIVITY TRACKER
-- ============================================================
local function startActivityTracker()
    local rs = game:GetService("ReplicatedStorage")
    local connected = {}

    local function hookEvent(event, key)
        if connected[key] then return end
        connected[key] = true
        event.OnClientEvent:Connect(function(arg1, ...)
            if type(arg1) == "string" and arg1:find("obtained") then
                local stripped = arg1:gsub("<[^>]+>", "")
                local playerName = stripped:match("%[Server%]:%s*(.-)%s+obtained")
                if playerName then
                    playerActivity[playerName] = tick()
                    afkNotifSent[playerName]   = false
                end
            elseif typeof(arg1) == "Instance" and arg1:IsA("Player") then
                playerActivity[arg1.Name] = tick()
                afkNotifSent[arg1.Name]   = false
            end
        end)
        print("[FishIt] ActivityTracker: hooked " .. key)
    end

    local function scanPackages()
        local packagesFolder = rs:FindFirstChild("Packages")
        if not packagesFolder then return 0 end
        local indexFolder = packagesFolder:FindFirstChild("_Index")
        if not indexFolder then return 0 end
        local n = 0
        for _, pkg in ipairs(indexFolder:GetChildren()) do
            if pkg.Name:find("sleitnick_net") then
                local netFolder = pkg:FindFirstChild("net")
                if netFolder then
                    for _, child in ipairs(netFolder:GetChildren()) do
                        if child.Name:sub(1, 3) == "RE/" and child:IsA("RemoteEvent") then
                            local key = pkg.Name .. "/" .. child.Name
                            hookEvent(child, key)
                            n = n + 1
                        end
                    end
                end
            end
        end
        return n
    end

    local found = scanPackages()
    if found > 0 then
        print("[FishIt] ActivityTracker: " .. found .. " event ter-hook")
    else
        print("[FishIt] ActivityTracker: event tidak ditemukan, hanya track via chat broadcast")
    end

    task.spawn(function()
        while true do task.wait(60); scanPackages() end
    end)
end

-- ============================================================
-- FITUR 5: DC MONITOR
-- ============================================================
local function startDcMonitor()
    print("[FishIt] DC Monitor aktif (via PlayerRemoving listener)")
end

-- ============================================================
-- FITUR 6: AUTO BUY WEATHER
-- Menggunakan getupvalue dari WeatherMachineController
-- UV 14 = PurchaseWeatherEvent (RemoteFunction)
-- UV 1  = Replion<Events> (untuk cek cuaca aktif)
-- Track durasi: beli sekali, tunggu habis, baru beli lagi
-- ============================================================
local weatherRemote    = nil
local weatherReplion   = nil
local weatherBuyTime   = {}  -- { ["Storm"] = tick() saat beli }

-- Durasi default per cuaca (dari game data)
local WEATHER_DURATIONS = {}
for _, w in ipairs(WEATHER_LIST) do
    if type(w) == "table" and w.Name then
        WEATHER_DURATIONS[w.Name] = w.Duration or 900
    end
end

local function initWeatherRemote()
    if weatherRemote then return true end
    local ok, wmc = pcall(require, RS.Controllers.WeatherMachineController)
    if not ok or not wmc then
        warn("[FishIt] WeatherMachineController tidak ditemukan")
        return false
    end
    -- UV 14 = PurchaseWeatherEvent RemoteFunction
    local ok2, remote = pcall(getupvalue, wmc.Start, 14)
    if ok2 and remote and typeof(remote) == "Instance" and remote:IsA("RemoteFunction") then
        weatherRemote = remote
        print("[FishIt] Weather remote ditemukan: " .. remote.Name)
    else
        -- Fallback: scan semua upvalues
        for i = 1, 30 do
            local s, v = pcall(getupvalue, wmc.Start, i)
            if not s then break end
            if typeof(v) == "Instance" and v:IsA("RemoteFunction") then
                weatherRemote = v
                print("[FishIt] Weather remote via scan UV" .. i .. ": " .. v.Name)
                break
            end
        end
    end
    -- UV 1 = Replion<Events>
    local ok3, rep = pcall(getupvalue, wmc.Start, 1)
    if ok3 and rep and type(rep) == "table" and rep.Find then
        weatherReplion = rep
        print("[FishIt] Weather Replion ditemukan")
    end
    return weatherRemote ~= nil
end

local function isWeatherStillActive(weatherName)
    -- Cek apakah cuaca masih aktif berdasarkan waktu beli + durasi
    local buyTime = weatherBuyTime[weatherName]
    if not buyTime then return false end
    local duration = WEATHER_DURATIONS[weatherName] or 900
    local elapsed = tick() - buyTime
    local remaining = duration - elapsed
    if remaining > 0 then
        return true, remaining
    end
    return false, 0
end

local function buyWeather(weatherName)
    if not initWeatherRemote() then
        warn("[FishIt] Weather remote belum siap!")
        return false
    end
    -- Cek masih aktif berdasarkan timer
    local active, remaining = isWeatherStillActive(weatherName)
    if active then
        print(("[FishIt] %s masih aktif (sisa %d detik)"):format(weatherName, math.floor(remaining)))
        return false
    end
    -- Cek via Replion juga
    if weatherReplion then
        if weatherReplion:Find("Events", weatherName) then
            print("[FishIt] " .. weatherName .. " sudah aktif sebagai event")
            weatherBuyTime[weatherName] = tick() -- sync timer
            return false
        end
        if weatherReplion:Find("WeatherMachine", weatherName) then
            print("[FishIt] " .. weatherName .. " sudah ada di Weather Machine")
            weatherBuyTime[weatherName] = tick() -- sync timer
            return false
        end
    end
    local ok, result = pcall(function()
        return weatherRemote:InvokeServer(weatherName)
    end)
    if ok and result then
        weatherBuyTime[weatherName] = tick() -- catat waktu beli
        local dur = WEATHER_DURATIONS[weatherName] or 900
        print(("[FishIt] Berhasil beli %s! Durasi %d menit, beli lagi jam %s"):format(
            weatherName, dur / 60,
            os.date("%H:%M:%S", os.time() + dur)
        ))
        return true
    else
        warn("[FishIt] Gagal beli cuaca: " .. weatherName)
        return false
    end
end

local function startAutoWeatherLoop()
    if AUTO_WEATHER_RUNNING then return end
    AUTO_WEATHER_RUNNING = true
    task.spawn(function()
        while AUTO_WEATHER_RUNNING do
            for name, enabled in pairs(AUTO_WEATHER_ENABLED) do
                if enabled then
                    local active, remaining = isWeatherStillActive(name)
                    if not active then
                        -- Cuaca habis, beli lagi
                        print("[FishIt] " .. name .. " habis, membeli ulang...")
                        buyWeather(name)
                        task.wait(2) -- delay antar pembelian
                    end
                end
            end
            task.wait(10) -- cek setiap 10 detik (BUKAN beli setiap 10 detik)
        end
    end)
    print("[FishIt] Auto Weather loop aktif (tracking durasi)")
end

local function stopAutoWeatherLoop()
    AUTO_WEATHER_RUNNING = false
    print("[FishIt] Auto Weather loop dihentikan")
end

-- ============================================================
-- FITUR 7: AUTO SELL
-- ============================================================
local sellAllRemote = nil

local function getupval(fn, i)
    if debug and debug.getupvalue then return debug.getupvalue(fn, i) end
    if getupvalue then return getupvalue(fn, i) end
    return nil
end

local function scanFunctionForRemote(fn, label)
    if not fn then return nil end
    for i = 1, 40 do
        local ok, val = pcall(getupval, fn, i)
        if not ok then break end
        
        if typeof(val) == "Instance" and val:IsA("RemoteFunction") then
            print("[FishIt] Sell remote ditemukan di " .. label .. " -> upvalue " .. i)
            return val
        end
        if type(val) == "userdata" and pcall(function() return val.InvokeServer end) then
            print("[FishIt] Sell remote/wrapper ditemukan di " .. label .. " -> upvalue " .. i)
            return val
        end
        
        if type(val) == "function" then
            for j = 1, 40 do
                local ok2, val2 = pcall(getupval, val, j)
                if not ok2 then break end
                
                if typeof(val2) == "Instance" and val2:IsA("RemoteFunction") then
                    print("[FishIt] Sell remote ditemukan di " .. label .. " -> nested [" .. i .. "." .. j .. "]")
                    return val2
                end
                if type(val2) == "userdata" and pcall(function() return val2.InvokeServer end) then
                    print("[FishIt] Sell remote/wrapper ditemukan di " .. label .. " -> nested [" .. i .. "." .. j .. "]")
                    return val2
                end
            end
        end
    end
    return nil
end

local function initSellRemote()
    if sellAllRemote then return true end
    local ok, vendorController = pcall(require, RS.Controllers.VendorController)
    if not ok or not vendorController then
        warn("[FishIt] VendorController tidak ditemukan")
        return false
    end
    
    sellAllRemote = scanFunctionForRemote(vendorController.SellAllItems, "SellAllItems")
    if not sellAllRemote then
        sellAllRemote = scanFunctionForRemote(vendorController.SellItem, "SellItem")
    end
    
    return sellAllRemote ~= nil
end

local function performAutoSell()
    if not initSellRemote() then return end
    print("[FishIt] Mencoba Auto Sell All...")
    local ok, result = pcall(function()
        return sellAllRemote:InvokeServer()
    end)
    if ok and result then
        print("[FishIt] ✅ Berhasil AUTO SELL ALL IKAN!")
    else
        warn("[FishIt] ❌ Auto Sell gagal atau inventory kosong.")
    end
end

local function startAutoSellLoop()
    if AUTO_SELL_RUNNING then return end
    AUTO_SELL_RUNNING = true
    task.spawn(function()
        while AUTO_SELL_RUNNING do
            -- Tunggu delay
            local timer = AUTO_SELL_INTERVAL
            while timer > 0 and AUTO_SELL_RUNNING do
                task.wait(1)
                timer = timer - 1
            end
            if AUTO_SELL_RUNNING and AUTO_SELL_ENABLED then
                performAutoSell()
            end
        end
    end)
    print("[FishIt] Auto Sell loop aktif (interval " .. AUTO_SELL_INTERVAL .. " detik)")
end

local function stopAutoSellLoop()
    AUTO_SELL_RUNNING = false
    print("[FishIt] Auto Sell loop dihentikan")
end

-- ============================================================
-- LOAD UI dari GitHub (cache-bust)
-- ============================================================
print("[FishIt] Mengunduh UI dari GitHub...")
local uiOk, buildUI = pcall(function()
    local uiCode = game:HttpGet(UI_URL .. "?t=" .. tostring(tick()))
    return loadstring(uiCode)()
end)
if not uiOk or not buildUI then
    warn("[FishIt] GAGAL load UI! Cek URL UI_URL.")
    warn(tostring(buildUI))
    -- Script tetap jalan tanpa UI
    buildUI = function() warn("[FishIt] UI tidak tersedia") end
end
print("[FishIt] UI berhasil dimuat.")

-- ============================================================
-- STARTUP
-- ============================================================
local function Startup()
    sendToVPS("startup", {
        player  = localPlayer.Name,
        message = "THREEFASTER NOTIF X8 aktif - " .. localPlayer.Name,
    })
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title    = "THREEFASTER NOTIF X8",
            Text     = "Chat hook aktif! | Player: " .. localPlayer.Name,
            Duration = 5,
        })
    end)
    local focusCount = 0
    for _ in pairs(FOCUS_FISH) do focusCount = focusCount + 1 end
    print("--------------------------------------------")
    print("[3xFaster] THREEFASTER NOTIF X8 | Player: " .. localPlayer.Name)
    print("[3xFaster] MIN_TIER : " .. MIN_TIER .. " (warna chat)")
    print("[3xFaster] VPS      : " .. VPS_URL)
    print("[3xFaster] FOCUS    : " .. focusCount .. " ikan")
    print("[3xFaster] CRYSTALIZED: " .. #CRYSTALIZED_FISH .. " ikan")
    local plrs = Players:GetPlayers()
    print("[3xFaster] Monitoring " .. #plrs .. " player di server:")
    for _, p in ipairs(plrs) do print("  + " .. p.Name) end
    print("--------------------------------------------")
end

-- ============================================================
-- INIT
-- ============================================================
if not game:IsLoaded() then game.Loaded:Wait() end

Startup()

-- Bangun UI dengan context (semua setter agar UI bisa ubah config)
local uiBuildOk, uiBuildErr = pcall(buildUI, {
    localPlayer       = localPlayer,
    Players           = Players,
    FOCUS_FISH        = FOCUS_FISH,
    CRYSTALIZED_FISH  = CRYSTALIZED_FISH,

    -- Nilai awal untuk ditampilkan di UI
    MIN_TIER          = MIN_TIER,
    ANTI_AFK_ENABLED  = ANTI_AFK_ENABLED,
    AFK_NOTIFY_ENABLED= AFK_NOTIFY_ENABLED,
    AFK_CHECK_INTERVAL= AFK_CHECK_INTERVAL,
    AFK_TIMEOUT       = AFK_TIMEOUT,
    DC_NOTIFY_ENABLED = DC_NOTIFY_ENABLED,
    DC_REJOIN_TIMEOUT = DC_REJOIN_TIMEOUT,
    COOLDOWN          = COOLDOWN,
    
    -- Auto Sell
    AUTO_SELL_ENABLED = AUTO_SELL_ENABLED,
    AUTO_SELL_INTERVAL= AUTO_SELL_INTERVAL,

    -- Weather data
    WEATHER_LIST       = WEATHER_LIST,
    AUTO_WEATHER_ENABLED = AUTO_WEATHER_ENABLED,

    -- Getter live (untuk status UI yang realtime)
    getMinTier    = function() return MIN_TIER end,

    -- Setter agar UI bisa ubah variabel di main
    setMinTier    = function(v) MIN_TIER          = v end,
    setCooldown   = function(v) COOLDOWN          = v end,
    setAfkCheck   = function(v) AFK_CHECK_INTERVAL= v end,
    setAfkTimeout = function(v) AFK_TIMEOUT       = v end,
    setDcTimeout  = function(v) DC_REJOIN_TIMEOUT = v end,
    setAntiAfk    = function(v) ANTI_AFK_ENABLED  = v; if v then startAntiAfk() end end,
    setAfkNotify  = function(v) AFK_NOTIFY_ENABLED= v end,
    setDcNotify   = function(v) DC_NOTIFY_ENABLED = v end,

    -- Auto Sell controls
    setAutoSell   = function(v) 
        AUTO_SELL_ENABLED = v 
        if v then startAutoSellLoop() else stopAutoSellLoop() end
    end,
    setSellInterval = function(v) AUTO_SELL_INTERVAL = v end,

    -- Weather controls
    setAutoWeather = function(name, enabled)
        AUTO_WEATHER_ENABLED[name] = enabled
        -- Mulai loop kalau ada yang aktif
        local anyActive = false
        for _, v in pairs(AUTO_WEATHER_ENABLED) do
            if v then anyActive = true; break end
        end
        if anyActive then startAutoWeatherLoop() else stopAutoWeatherLoop() end
    end,
    buyWeatherOnce = function(name) return buyWeather(name) end,
})
if not uiBuildOk then
    warn("[FishIt] UI BUILD ERROR: " .. tostring(uiBuildErr))
end

HookChat()
startAntiAfk()
startActivityTracker()
startAfkMonitor()
startDcMonitor()
