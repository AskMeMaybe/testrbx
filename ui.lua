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
    -- Title = "THREEFASTER" → ini yang muncul saat diminimize
    -- Author = "NOTIF X8 | Player" → muncul di header bawah title
    -- Folder tidak diset → agar WindUI tidak load config lama (anti-AFK dsb)
    local Window = WindUI:CreateWindow({
        Title         = "THREEFASTER",
        Icon          = "fish",
        Author        = "NOTIF X8 | " .. localPlayer.Name,
        Size          = UDim2.fromOffset(580, 440),
        MinSize       = Vector2.new(480, 350),
        Transparent   = true,
        Theme         = "Dark",
        Resizable     = true,
        HideSearchBar = false,
    })

    -- ============================================================
    -- ── LUCK BOOST TRACKER ──────────────────────────────────────
    -- Membaca LuckData dari ReplicatedStorage Replion event
    -- ============================================================
    local luckBoostAmount   = 0
    local luckBoostExpireAt = 0
    local statusParagraph   = nil

    local function formatDuration(secs)
        if secs <= 0 then return "Habis" end
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
        elseif luckBoostAmount > 0 then
            boostLine = "● Luck Boost: Habis ✗"
        else
            boostLine = "● Luck Boost: Tidak aktif"
        end
        -- MIN_TIER dibaca via ctx getter agar selalu live (bukan snapshot)
        local liveTier = ctx.getMinTier and ctx.getMinTier() or ctx.MIN_TIER
        return "● Player: " .. localPlayer.Name
            .. "\n● Chat hook: aktif ✓"
            .. "\n● MIN_TIER: " .. tostring(liveTier)
            .. "\n● Server: " .. #Players:GetPlayers() .. " player"
            .. "\n" .. boostLine
    end

    -- Listen event LuckData
    task.spawn(function()
        local Event
        pcall(function()
            Event = game:GetService("ReplicatedStorage")
                .Packages._Index["ytrev_replion@2.0.0-rc.3"]
                .replion.Remotes.Update
        end)
        -- Fallback scan kalau path berubah
        if not Event then
            pcall(function()
                local idx = game:GetService("ReplicatedStorage").Packages._Index
                for _, pkg in ipairs(idx:GetChildren()) do
                    if pkg.Name:find("replion") then
                        local rem = pkg:FindFirstChild("Remotes", true)
                        if rem then
                            local upd = rem:FindFirstChild("Update")
                            if upd then Event = upd; break end
                        end
                    end
                end
            end)
        end
        if not Event then
            warn("[FishIt] LuckData event tidak ditemukan.")
            return
        end
        Event.OnClientEvent:Connect(function(_, dataKey, data)
            if dataKey == "LuckData" and type(data) == "table" then
                luckBoostAmount   = data.Amount or 0
                luckBoostExpireAt = (data.Started or 0) + (data.Remaining or 0)
                local sisa = math.max(0, luckBoostExpireAt - os.time())
                print(string.format("[FishIt] LuckBoost x%d | Sisa: %s", luckBoostAmount, formatDuration(sisa)))
                if statusParagraph and statusParagraph.SetDesc then
                    pcall(function() statusParagraph:SetDesc(buildStatusDesc()) end)
                end
            end
        end)
        print("[FishIt] LuckData event terhubung ✓")
    end)

    -- ============================================================
    -- TAB 1: Settings
    -- ============================================================
    local TabSettings = Window:Tab({ Title = "Settings", Icon = "settings" })

    -- Anti-AFK → Value pakai ctx.ANTI_AFK_ENABLED (false di main)
    TabSettings:Toggle({
        Title    = "Anti-AFK",
        Desc     = "Cegah kick AFK otomatis",
        Icon     = "shield-check",
        Value    = ctx.ANTI_AFK_ENABLED,   -- false by default dari main
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

    -- Status Server (dengan Luck Boost countdown)
    statusParagraph = TabSettings:Paragraph({
        Title = "Status Server",
        Desc  = buildStatusDesc(),
        Icon  = "activity",
    })

    -- Countdown realtime: expireAt dihitung SEKALI dari event,
    -- lalu setiap 1 detik hitung lokal: sisa = expireAt - os.time()
    -- Loop BERHENTI otomatis ketika boost sudah habis (hemat resource).
    task.spawn(function()
        local boostWasActive = false
        while true do
            task.wait(1)
            if luckBoostExpireAt <= 0 then
                -- Boost belum pernah masuk, idle saja
                task.wait(4)  -- cek lagi 5 detik kemudian
            else
                local remaining = luckBoostExpireAt - os.time()
                if remaining > 0 then
                    boostWasActive = true
                    -- Boost aktif: update countdown setiap detik
                    if statusParagraph and statusParagraph.SetDesc then
                        pcall(function() statusParagraph:SetDesc(buildStatusDesc()) end)
                    end
                elseif boostWasActive then
                    -- Baru saja habis: update sekali terakhir lalu stop
                    boostWasActive = false
                    if statusParagraph and statusParagraph.SetDesc then
                        pcall(function() statusParagraph:SetDesc(buildStatusDesc()) end)
                    end
                    print("[3xFaster] Luck Boost habis. Countdown loop idle.")
                    -- Reset, tunggu event boost baru
                    luckBoostExpireAt = 0
                    luckBoostAmount   = 0
                end
            end
        end
    end)

    -- Player List
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
                    Title    = "Focus Fish Ditambah",
                    Content  = name .. " ditambahkan ke daftar Focus",
                    Duration = 3,
                    Icon     = "fish",
                })
            end
        end,
    })

    TabFocus:Button({
        Title    = "Lihat Daftar Focus Fish",
        Desc     = "Tampilkan semua ikan dalam notifikasi",
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
        -- Format harga: 20000 → 20.000
        local priceStr = tostring(wPrice):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
        local label = wName .. " ($" .. priceStr .. ")"
        table.insert(weatherValues, label)
        weatherMap[label] = w
    end

    -- Multi-select dropdown, maksimum 3 cuaca
    local selectedWeathers = {}  -- { label1, label2, ... }

    local weatherDropdown = TabWeather:Dropdown({
        Title     = "Select Weather",
        Desc      = "Pilih cuaca (maks. 3) untuk dibeli atau di-auto",
        Icon      = "cloud-sun",
        Values    = weatherValues,
        Multi     = true,
        AllowNone = true,
        Callback  = function(selected)
            -- selected adalah table list dari pilihan aktif
            if type(selected) == "table" then
                -- Batasi maks 3
                if #selected > 3 then
                    WindUI:Notify({
                        Title    = "Maksimal 3 Cuaca!",
                        Content  = "Kamu hanya bisa memilih maksimal 3 cuaca sekaligus",
                        Duration = 3,
                        Icon     = "alert-triangle",
                    })
                    -- Potong ke 3 pertama
                    local trimmed = {}
                    for i = 1, 3 do trimmed[i] = selected[i] end
                    selected = trimmed
                end
                selectedWeathers = selected
                print("[FishIt] Weather dipilih: " .. table.concat(selectedWeathers, ", "))
            elseif type(selected) == "string" and selected ~= "" then
                selectedWeathers = { selected }
            else
                selectedWeathers = {}
            end
        end,
    })

    -- Toggle: Auto Buy Weather Events (untuk semua cuaca yang dipilih)
    TabWeather:Toggle({
        Title    = "Auto Buy Weather Events",
        Desc     = "Beli otomatis cuaca yang dipilih saat durasi habis",
        Icon     = "repeat",
        Value    = false,
        Callback = function(state)
            if #selectedWeathers == 0 then
                WindUI:Notify({
                    Title    = "Pilih Cuaca Dulu!",
                    Content  = "Silakan pilih cuaca dari dropdown sebelum mengaktifkan auto buy",
                    Duration = 4,
                    Icon     = "alert-triangle",
                })
                return
            end
            for _, label in ipairs(selectedWeathers) do
                local info = weatherMap[label]
                if info and ctx.setAutoWeather then
                    local wName = info.Name or info
                    ctx.setAutoWeather(wName, state)
                end
            end
            local names = {}
            for _, label in ipairs(selectedWeathers) do
                local info = weatherMap[label]
                if info then table.insert(names, info.Name or info) end
            end
            WindUI:Notify({
                Title    = state and "Auto Buy ON" or "Auto Buy OFF",
                Content  = (state and "Auto buy aktif: " or "Auto buy berhenti: ")
                        .. table.concat(names, ", "),
                Duration = 4,
                Icon     = state and "check-circle" or "x-circle",
            })
        end,
    })

    -- Tombol Buy Now (beli semua yang dipilih sekarang)
    TabWeather:Button({
        Title    = "Buy Now",
        Desc     = "Beli semua cuaca yang dipilih di dropdown sekarang",
        Icon     = "shopping-bag",
        Callback = function()
            if #selectedWeathers == 0 then
                WindUI:Notify({
                    Title    = "Pilih Cuaca Dulu!",
                    Content  = "Pilih cuaca dari dropdown terlebih dahulu",
                    Duration = 3,
                    Icon     = "alert-triangle",
                })
                return
            end
            local results = {}
            for _, label in ipairs(selectedWeathers) do
                local info = weatherMap[label]
                if info and ctx.buyWeatherOnce then
                    local wName = info.Name or info
                    local ok2 = ctx.buyWeatherOnce(wName)
                    table.insert(results, wName .. (ok2 and " ✓" or " ✗"))
                end
            end
            WindUI:Notify({
                Title    = "Hasil Buy Cuaca",
                Content  = table.concat(results, "\n"),
                Duration = 5,
                Icon     = "cloud-lightning",
            })
        end,
    })

    TabWeather:Paragraph({
        Title = "Info",
        Desc  = "● Pilih 1–3 cuaca dari dropdown\n"
             .. "● Toggle Auto Buy → beli ulang otomatis saat habis\n"
             .. "● Buy Now → beli semua pilihan sekarang",
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

    TabSettings:Select()

    print("[FishIt] WindUI (THREEFASTER NOTIF X8) berhasil dibangun")
end

return buildUI
