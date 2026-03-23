-- ============================================================
-- fishit_ui.lua  —  UI MODULE (WindUI)
-- Menggunakan WindUI v1.6.53+
-- Tab: Settings / Focus / Weather / Config
-- Di-host di GitHub dan di-load oleh fishit_main.lua via loadstring
-- ============================================================

local function buildUI(ctx)
    -- ── Load WindUI ─────────────────────────────────────────
    local WindUI
    local ok, err = pcall(function()
        WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
    end)
    if not ok or not WindUI then
        warn("[FishIt] GAGAL load WindUI: " .. tostring(err))
        return
    end

    local localPlayer      = ctx.localPlayer
    local Players          = ctx.Players
    local FOCUS_FISH       = ctx.FOCUS_FISH
    local CRYSTALIZED_FISH = ctx.CRYSTALIZED_FISH
    local WEATHER_LIST     = ctx.WEATHER_LIST or {}
    local AUTO_WEATHER     = ctx.AUTO_WEATHER_ENABLED or {}

    -- ── Buat Window ─────────────────────────────────────────
    local Window = WindUI:CreateWindow({
        Title         = "THREEFASTER NOTIF",
        Icon          = "fish",
        Author        = "X8 | " .. localPlayer.Name,
        Folder        = "ThreefasterNotif",
        Size          = UDim2.fromOffset(580, 440),
        MinSize       = Vector2.new(480, 350),
        Transparent   = true,
        Theme         = "Dark",
        Resizable     = true,
        HideSearchBar = false,
    })

    -- ============================================================
    -- ── BOOST TRACKER (LuckData via ReplicatedStorage Event) ──
    -- ============================================================
    local luckBoostRemaining = 0   -- detik tersisa (realtime)
    local luckBoostAmount    = 0   -- multiplier (misal 8 = x8)
    local luckBoostExpireAt  = 0   -- os.time() saat boost habis
    local statusParagraph    = nil -- referensi paragraph untuk update

    local function formatDuration(secs)
        if secs <= 0 then return "Tidak aktif" end
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        local s = math.floor(secs % 60)
        if h > 0 then
            return string.format("%dj %02dm %02ds", h, m, s)
        else
            return string.format("%dm %02ds", m, s)
        end
    end

    local function buildStatusDesc()
        local remaining = math.max(0, luckBoostExpireAt - os.time())
        local boostLine
        if luckBoostAmount > 0 and remaining > 0 then
            boostLine = "● Luck Boost: x" .. luckBoostAmount .. " | Sisa: " .. formatDuration(remaining)
        elseif luckBoostAmount > 0 and remaining <= 0 then
            boostLine = "● Luck Boost: Habis ✗"
        else
            boostLine = "● Luck Boost: Tidak aktif"
        end

        local plrCount = #Players:GetPlayers()
        return "● Player: " .. localPlayer.Name
            .. "\n● Chat hook: aktif ✓"
            .. "\n● MIN_TIER: " .. tostring(ctx.MIN_TIER)
            .. "\n● Server: " .. plrCount .. " player"
            .. "\n" .. boostLine
    end

    -- ── Listen event LuckData dari ReplicatedStorage ─────────
    task.spawn(function()
        local ok2, Event = pcall(function()
            -- path sesuai cobalt dump
            return game:GetService("ReplicatedStorage")
                .Packages._Index["ytrev_replion@2.0.0-rc.3"]
                .replion.Remotes.Update
        end)
        if not ok2 or not Event then
            warn("[FishIt] LuckData event tidak ditemukan, coba scan manual...")
            -- Fallback: cari RemoteEvent bernama "Update" di dalam Replion
            pcall(function()
                local rs = game:GetService("ReplicatedStorage")
                for _, pkg in ipairs(rs.Packages._Index:GetChildren()) do
                    if pkg.Name:find("replion") then
                        local rem = pkg:FindFirstChild("Remotes", true)
                        if rem then
                            local upd = rem:FindFirstChild("Update")
                            if upd then Event = upd end
                        end
                    end
                end
            end)
        end

        if not Event then
            warn("[FishIt] LuckData event tidak bisa ditemukan.")
            return
        end

        Event.OnClientEvent:Connect(function(key, dataKey, data)
            -- key="\x11", dataKey="LuckData", data={Remaining,Started,Amount}
            if dataKey == "LuckData" and type(data) == "table" then
                luckBoostAmount   = data.Amount   or 0
                -- Remaining = total durasi dalam detik dari waktu Started
                local started     = data.Started  or 0
                local remaining   = data.Remaining or 0
                luckBoostExpireAt = started + remaining
                local sisa = math.max(0, luckBoostExpireAt - os.time())
                print(string.format("[FishIt] LuckBoost x%d | Sisa: %s", luckBoostAmount, formatDuration(sisa)))

                -- Update paragraph kalau sudah dibuat
                if statusParagraph and statusParagraph.SetDesc then
                    statusParagraph:SetDesc(buildStatusDesc())
                end
            end
        end)

        print("[FishIt] LuckData event terhubung ✓")
    end)

    -- ============================================================
    -- TAB 1: Settings
    -- ============================================================
    local TabSettings = Window:Tab({ Title = "Settings", Icon = "settings" })

    -- ── Toggles ──────────────────────────────────
    TabSettings:Toggle({
        Title    = "Anti-AFK",
        Desc     = "Cegah kick AFK otomatis",
        Icon     = "shield-check",
        Value    = ctx.ANTI_AFK_ENABLED,
        Callback = function(state) ctx.setAntiAfk(state) end,
    })

    TabSettings:Toggle({
        Title    = "AFK Notify",
        Desc     = "Kirim notif saat player AFK",
        Icon     = "bell",
        Value    = ctx.AFK_NOTIFY_ENABLED,
        Callback = function(state) ctx.setAfkNotify(state) end,
    })

    TabSettings:Toggle({
        Title    = "DC Notify",
        Desc     = "Kirim notif saat player disconnect",
        Icon     = "wifi-off",
        Value    = ctx.DC_NOTIFY_ENABLED,
        Callback = function(state) ctx.setDcNotify(state) end,
    })

    TabSettings:Toggle({
        Title    = "Auto Sell",
        Desc     = "Jual semua ikan otomatis",
        Icon     = "shopping-cart",
        Value    = ctx.AUTO_SELL_ENABLED,
        Callback = function(state) ctx.setAutoSell(state) end,
    })

    -- ── Status Server (dengan Luck Boost) ────────
    -- Simpan referensi agar bisa di-update realtime
    statusParagraph = TabSettings:Paragraph({
        Title = "Status Server",
        Desc  = buildStatusDesc(),
        Icon  = "activity",
    })

    -- ── Loop update status setiap 30 detik ───────
    task.spawn(function()
        while true do
            task.wait(30)
            if statusParagraph and statusParagraph.SetDesc then
                pcall(function()
                    statusParagraph:SetDesc(buildStatusDesc())
                end)
            end
        end
    end)

    -- ── Player List ──────────────────────────────
    local plrList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(plrList, p.Name)
    end
    TabSettings:Paragraph({
        Title = "Player Di Server",
        Desc  = #plrList > 0 and table.concat(plrList, " | ") or "(Kosong)",
        Icon  = "users",
    })

    -- ============================================================
    -- TAB 2: Focus Fish
    -- ============================================================
    local TabFocus = Window:Tab({ Title = "Focus", Icon = "target" })

    -- Input tambah ikan
    TabFocus:Input({
        Title       = "Tambah Focus Fish",
        Desc        = "Ikan ini selalu trigger notif tanpa peduli tier",
        Placeholder = "Nama ikan...",
        Icon        = "plus-circle",
        Callback    = function(name)
            name = name:match("^%s*(.-)%s*$")
            if name and name ~= "" then
                FOCUS_FISH[name] = true
                print("[FishIt] FOCUS_FISH tambah: " .. name)
                WindUI:Notify({
                    Title   = "Focus Fish Ditambah",
                    Content = name .. " ditambahkan ke daftar Focus",
                    Duration = 3,
                    Icon    = "fish",
                })
            end
        end,
    })

    -- Tombol lihat daftar
    TabFocus:Button({
        Title    = "Lihat Daftar Focus Fish",
        Desc     = "Tampilkan semua ikan yang di-focus",
        Icon     = "list",
        Callback = function()
            local names = {}
            for fishName in pairs(FOCUS_FISH) do
                table.insert(names, "● " .. fishName)
            end
            table.sort(names)
            WindUI:Notify({
                Title    = "Focus Fish (" .. #names .. ")",
                Content  = #names > 0 and table.concat(names, "\n") or "(Kosong)",
                Duration = 6,
                Icon     = "list",
            })
        end,
    })

    -- Daftar focus fish (statis saat build)
    do
        local names = {}
        for fishName in pairs(FOCUS_FISH) do
            table.insert(names, "● " .. fishName)
        end
        table.sort(names)
        TabFocus:Paragraph({
            Title = "Daftar Focus Fish (" .. #names .. ")",
            Desc  = #names > 0 and table.concat(names, "\n") or "(Kosong)",
            Icon  = "fish",
        })
    end

    -- Hapus semua
    TabFocus:Button({
        Title    = "Hapus Semua Focus Fish",
        Desc     = "Kosongkan seluruh daftar focus fish",
        Icon     = "trash-2",
        Callback = function()
            for k in pairs(FOCUS_FISH) do FOCUS_FISH[k] = nil end
            WindUI:Notify({
                Title    = "Focus Fish Dikosongkan",
                Content  = "Semua focus fish telah dihapus",
                Duration = 3,
                Icon     = "trash-2",
            })
            print("[FishIt] Focus Fish dikosongkan")
        end,
    })

    -- Crystalized Fish info
    TabFocus:Paragraph({
        Title = "Crystalized Fish (" .. #CRYSTALIZED_FISH .. ")",
        Desc  = #CRYSTALIZED_FISH > 0
            and "● " .. table.concat(CRYSTALIZED_FISH, "\n● ")
            or  "(Kosong)",
        Icon  = "sparkles",
    })

    -- ============================================================
    -- TAB 3: Weather
    -- ============================================================
    local TabWeather = Window:Tab({ Title = "Weather", Icon = "cloud" })

    -- Build dropdown values: "Cloudy ($20.000)"
    local weatherValues = {}
    local weatherMap    = {}  -- label → weatherInfo
    for _, w in ipairs(WEATHER_LIST) do
        local wName  = w.Name or w
        local wPrice = w.Price or 0
        -- Format harga pakai titik sebagai pemisah ribuan
        local priceStr = tostring(wPrice):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
        local label = wName .. " ($" .. priceStr .. ")"
        table.insert(weatherValues, label)
        weatherMap[label] = w
    end

    local selectedWeatherLabel = nil

    local weatherDropdown = TabWeather:Dropdown({
        Title     = "Select Weather",
        Desc      = "Pilih cuaca untuk dibeli atau di-auto",
        Icon      = "cloud-sun",
        Values    = weatherValues,
        AllowNone = true,
        Callback  = function(selected)
            selectedWeatherLabel = selected
        end,
    })

    -- Single toggle: Auto Buy Weather Events
    TabWeather:Toggle({
        Title    = "Auto Buy Weather Events",
        Desc     = "Beli otomatis cuaca yang dipilih saat durasi habis",
        Icon     = "repeat",
        Value    = false,
        Callback = function(state)
            if not selectedWeatherLabel or selectedWeatherLabel == "" then
                WindUI:Notify({
                    Title    = "Pilih Cuaca Dulu!",
                    Content  = "Silakan pilih cuaca dari dropdown sebelum mengaktifkan auto buy",
                    Duration = 4,
                    Icon     = "alert-triangle",
                })
                return
            end
            local info = weatherMap[selectedWeatherLabel]
            if info and ctx.setAutoWeather then
                local wName = info.Name or info
                ctx.setAutoWeather(wName, state)
                WindUI:Notify({
                    Title    = state and ("Auto Buy ON: " .. wName) or ("Auto Buy OFF: " .. wName),
                    Content  = state
                        and (wName .. " akan dibeli otomatis saat habis")
                        or  (wName .. " auto buy dihentikan"),
                    Duration = 3,
                    Icon     = state and "check-circle" or "x-circle",
                })
            end
        end,
    })

    -- Tombol Buy Now (beli cuaca yang dipilih di dropdown)
    TabWeather:Button({
        Title    = "Buy Now",
        Desc     = "Beli cuaca yang dipilih di dropdown sekali langsung",
        Icon     = "shopping-bag",
        Callback = function()
            if not selectedWeatherLabel or selectedWeatherLabel == "" then
                WindUI:Notify({
                    Title    = "Pilih Cuaca Dulu!",
                    Content  = "Pilih cuaca dari dropdown terlebih dahulu",
                    Duration = 3,
                    Icon     = "alert-triangle",
                })
                return
            end
            local info = weatherMap[selectedWeatherLabel]
            if info and ctx.buyWeatherOnce then
                local wName = info.Name or info
                local result = ctx.buyWeatherOnce(wName)
                WindUI:Notify({
                    Title    = result and "Berhasil Beli!" or "Gagal Beli",
                    Content  = result
                        and (wName .. " berhasil dibeli!")
                        or  (wName .. " gagal / masih aktif"),
                    Duration = 3,
                    Icon     = result and "check-circle" or "x-circle",
                })
            end
        end,
    })

    -- Info cuaca aktif (yang auto-nya ON)
    TabWeather:Paragraph({
        Title = "Info",
        Desc  = "Pilih cuaca dari dropdown, lalu toggle Auto Buy\n"
             .. "atau klik Buy Now untuk beli langsung.\n"
             .. "Auto Buy akan beli ulang saat durasi habis.",
        Icon  = "info",
    })

    -- ============================================================
    -- TAB 4: Config
    -- ============================================================
    local TabConfig = Window:Tab({ Title = "Config", Icon = "sliders-horizontal" })

    TabConfig:Paragraph({
        Title = "Edit Konfigurasi",
        Desc  = "Geser slider untuk mengubah nilai konfigurasi secara langsung",
        Icon  = "settings-2",
    })

    TabConfig:Slider({
        Title    = "MIN_TIER",
        Desc     = "4=Epic | 5=Legendary | 6=Mythic | 7=Secret | 8=Forgotten",
        Icon     = "layers",
        Step     = 1,
        Value    = { Min = 4, Max = 8, Default = ctx.MIN_TIER },
        Callback = function(v) ctx.setMinTier(v) end,
    })

    TabConfig:Slider({
        Title    = "Cooldown (detik)",
        Desc     = "Jeda minimum antar notifikasi ikan",
        Icon     = "timer",
        Step     = 1,
        Value    = { Min = 0, Max = 30, Default = ctx.COOLDOWN },
        Callback = function(v) ctx.setCooldown(v) end,
    })

    TabConfig:Slider({
        Title    = "AFK Check Interval (menit)",
        Desc     = "Seberapa sering sistem mengecek AFK",
        Icon     = "clock",
        Step     = 1,
        Value    = { Min = 1, Max = 60, Default = math.floor(ctx.AFK_CHECK_INTERVAL / 60) },
        Callback = function(v) ctx.setAfkCheck(v * 60) end,
    })

    TabConfig:Slider({
        Title    = "AFK Timeout (menit)",
        Desc     = "Berapa menit tidak aktif sebelum dianggap AFK",
        Icon     = "user-x",
        Step     = 1,
        Value    = { Min = 1, Max = 60, Default = math.floor(ctx.AFK_TIMEOUT / 60) },
        Callback = function(v) ctx.setAfkTimeout(v * 60) end,
    })

    TabConfig:Slider({
        Title    = "DC Timeout (menit)",
        Desc     = "Berapa menit setelah keluar baru notif DC dikirim",
        Icon     = "wifi-off",
        Step     = 1,
        Value    = { Min = 1, Max = 30, Default = math.floor(ctx.DC_REJOIN_TIMEOUT / 60) },
        Callback = function(v) ctx.setDcTimeout(v * 60) end,
    })

    TabConfig:Slider({
        Title    = "Auto Sell Interval (detik)",
        Desc     = "Seberapa sering auto sell berjalan",
        Icon     = "repeat",
        Step     = 10,
        Value    = { Min = 60, Max = 3600, Default = ctx.AUTO_SELL_INTERVAL },
        Callback = function(v) ctx.setSellInterval(v) end,
    })

    -- ── Statistik ────────────────────────────────
    local focusCount = 0
    for _ in pairs(FOCUS_FISH) do focusCount = focusCount + 1 end

    TabConfig:Paragraph({
        Title = "Statistik",
        Desc  = "● Focus Fish: " .. focusCount .. " ikan"
             .. "\n● Crystalized: " .. #CRYSTALIZED_FISH .. " ikan"
             .. "\n● VPS: aktif"
             .. "\n● MIN_TIER: " .. ctx.MIN_TIER
             .. "\n● Cooldown: " .. ctx.COOLDOWN .. " detik",
        Icon  = "bar-chart-2",
    })

    TabConfig:Button({
        Title    = "Test Notifikasi",
        Desc     = "Kirim notif test ke layar",
        Icon     = "bell-ring",
        Callback = function()
            WindUI:Notify({
                Title    = "THREEFASTER NOTIF X8",
                Content  = "Sistem berjalan normal ✓",
                Duration = 4,
                Icon     = "check-circle",
            })
        end,
    })

    -- ── Aktifkan tab Settings duluan ─────────────
    TabSettings:Select()

    print("[FishIt] WindUI (THREEFASTER NOTIF X8) berhasil dibangun")
end

return buildUI
