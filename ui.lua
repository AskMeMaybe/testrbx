-- ============================================================
-- fishit_ui.lua  —  UI MODULE (WindUI)
-- Menggunakan WindUI v1.6.53+
-- Tab: Settings / Focus / Weather / Config
-- Di-host di GitHub dan di-load oleh fishit_main.lua via loadstring
-- ============================================================
-- Wajib return function buildUI(ctx) agar bisa dipanggil dari main
-- ctx = {
--   localPlayer, Players, MIN_TIER, ANTI_AFK_ENABLED,
--   AFK_NOTIFY_ENABLED, AFK_CHECK_INTERVAL, AFK_TIMEOUT,
--   DC_NOTIFY_ENABLED, DC_REJOIN_TIMEOUT, COOLDOWN,
--   FOCUS_FISH, CRYSTALIZED_FISH, WEATHER_LIST, AUTO_WEATHER_ENABLED,
--   AUTO_SELL_ENABLED, AUTO_SELL_INTERVAL,
--   startAntiAfk, setMinTier, setCooldown, setAfkCheck, setAfkTimeout,
--   setDcTimeout, setAntiAfk, setAfkNotify, setDcNotify,
--   setAutoSell, setSellInterval, setAutoWeather, buyWeatherOnce,
-- }

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
        Title      = "FishIt Notifier",
        Icon       = "fish",
        Author     = "v6 | " .. localPlayer.Name,
        Folder     = "FishItNotifier",
        Size       = UDim2.fromOffset(560, 420),
        MinSize    = Vector2.new(480, 350),
        Transparent = true,
        Theme      = "Dark",
        Resizable  = true,
        HideSearchBar = false,
    })

    -- ╔══════════════════════════════════════════╗
    -- ║  TAB 1: Settings                         ║
    -- ╚══════════════════════════════════════════╝
    local TabSettings = Window:Tab({ Title = "Settings", Icon = "settings" })

    -- ── Features ────────────────────────────────
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

    -- ── Status ──────────────────────────────────
    TabSettings:Paragraph({
        Title = "Status Server",
        Desc  = "● Player: " .. localPlayer.Name
             .. "\n● Chat hook: aktif ✓"
             .. "\n● MIN_TIER: " .. tostring(ctx.MIN_TIER)
             .. "\n● Server: " .. #Players:GetPlayers() .. " player",
    })

    -- ── Player List ─────────────────────────────
    local plrList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(plrList, p.Name)
    end
    TabSettings:Paragraph({
        Title = "Player Di Server",
        Desc  = table.concat(plrList, " | "),
    })

    -- ╔══════════════════════════════════════════╗
    -- ║  TAB 2: Focus Fish                       ║
    -- ╚══════════════════════════════════════════╝
    local TabFocus = Window:Tab({ Title = "Focus", Icon = "target" })

    -- Input untuk tambah ikan
    local focusInput
    focusInput = TabFocus:Input({
        Title       = "Tambah Focus Fish",
        Desc        = "Ikan ini akan selalu mengirim notif tanpa peduli tier",
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

    -- Tombol refresh daftar
    TabFocus:Button({
        Title    = "Refresh Daftar Focus Fish",
        Desc     = "Klik untuk memperbarui tampilan daftar ikan fokus",
        Icon     = "refresh-cw",
        Callback = function()
            -- Re-build paragraph list
            local names = {}
            for fishName in pairs(FOCUS_FISH) do
                table.insert(names, "● " .. fishName)
            end
            if #names == 0 then
                table.insert(names, "(Kosong)")
            end
            table.sort(names)
            WindUI:Notify({
                Title    = "Focus Fish (" .. #names .. ")",
                Content  = table.concat(names, "\n"),
                Duration = 5,
                Icon     = "list",
            })
        end,
    })

    -- Tampilkan daftar Focus Fish
    do
        local names = {}
        for fishName in pairs(FOCUS_FISH) do
            table.insert(names, "● " .. fishName)
        end
        table.sort(names)
        if #names == 0 then names = { "(Kosong)" } end

        TabFocus:Paragraph({
            Title = "Daftar Focus Fish",
            Desc  = table.concat(names, "\n"),
            Icon  = "fish",
        })
    end

    -- Tombol hapus semua focus fish
    TabFocus:Button({
        Title    = "Hapus Semua Focus Fish",
        Desc     = "Kosongkan seluruh daftar focus fish",
        Icon     = "trash-2",
        Callback = function()
            for k in pairs(FOCUS_FISH) do
                FOCUS_FISH[k] = nil
            end
            WindUI:Notify({
                Title    = "Focus Fish Dikosongkan",
                Content  = "Semua focus fish telah dihapus",
                Duration = 3,
                Icon     = "trash-2",
            })
            print("[FishIt] Focus Fish dikosongkan")
        end,
    })

    -- ── Crystalized Fish Info ────────────────────
    TabFocus:Paragraph({
        Title = "Crystalized Fish (" .. #CRYSTALIZED_FISH .. ")",
        Desc  = table.concat(CRYSTALIZED_FISH, "\n● ", 1) and
                "● " .. table.concat(CRYSTALIZED_FISH, "\n● ") or "(Kosong)",
    })

    -- ╔══════════════════════════════════════════╗
    -- ║  TAB 3: Weather                          ║
    -- ╚══════════════════════════════════════════╝
    local TabWeather = Window:Tab({ Title = "Weather", Icon = "cloud" })

    TabWeather:Paragraph({
        Title = "Auto Buy Weather",
        Desc  = "AUTO = beli otomatis saat durasi cuaca habis\nBuy = beli sekali sekarang",
    })

    for _, weatherInfo in ipairs(WEATHER_LIST) do
        local weatherName  = weatherInfo.Name or weatherInfo
        local weatherPrice = weatherInfo.Price or 0
        local weatherDur   = weatherInfo.Duration or 900
        local weatherDesc  = weatherInfo.Desc or ""

        -- Toggle Auto
        TabWeather:Toggle({
            Title    = weatherName .. " [AUTO]",
            Desc     = tostring(weatherPrice) .. " coins | "
                    .. tostring(weatherDur / 60) .. " mnt | " .. weatherDesc,
            Icon     = "cloud-lightning",
            Value    = AUTO_WEATHER[weatherName] or false,
            Callback = function(state)
                if ctx.setAutoWeather then
                    ctx.setAutoWeather(weatherName, state)
                end
            end,
        })

        -- Tombol Buy Now
        TabWeather:Button({
            Title    = "Beli Sekarang: " .. weatherName,
            Desc     = "Klik untuk beli " .. weatherName .. " satu kali",
            Icon     = "shopping-bag",
            Callback = function()
                if ctx.buyWeatherOnce then
                    local result = ctx.buyWeatherOnce(weatherName)
                    WindUI:Notify({
                        Title    = result and "Berhasil Beli!" or "Gagal Beli",
                        Content  = result
                            and (weatherName .. " berhasil dibeli!")
                            or  (weatherName .. " gagal dibeli / masih aktif"),
                        Duration = 3,
                        Icon     = result and "check-circle" or "x-circle",
                    })
                end
            end,
        })
    end

    -- ╔══════════════════════════════════════════╗
    -- ║  TAB 4: Config                           ║
    -- ╚══════════════════════════════════════════╝
    local TabConfig = Window:Tab({ Title = "Config", Icon = "sliders-horizontal" })

    TabConfig:Paragraph({
        Title = "Edit Konfigurasi",
        Desc  = "Geser slider atau isi input lalu tekan Enter untuk apply",
    })

    -- ── MIN_TIER Slider ──────────────────────────
    TabConfig:Slider({
        Title    = "MIN_TIER",
        Desc     = "Tier minimum untuk notifikasi (4=Epic, 5=Legendary, 6=Mythic, 7=Secret, 8=Forgotten)",
        Icon     = "layers",
        Step     = 1,
        Value    = { Min = 4, Max = 8, Default = ctx.MIN_TIER },
        Callback = function(v) ctx.setMinTier(v) end,
    })

    -- ── Cooldown Slider ──────────────────────────
    TabConfig:Slider({
        Title    = "Cooldown (detik)",
        Desc     = "Jeda minimum antar notifikasi ikan",
        Icon     = "timer",
        Step     = 1,
        Value    = { Min = 0, Max = 30, Default = ctx.COOLDOWN },
        Callback = function(v) ctx.setCooldown(v) end,
    })

    -- ── AFK Check Interval ───────────────────────
    TabConfig:Slider({
        Title    = "AFK Check Interval (menit)",
        Desc     = "Seberapa sering sistem mengecek AFK",
        Icon     = "clock",
        Step     = 1,
        Value    = { Min = 1, Max = 60, Default = math.floor(ctx.AFK_CHECK_INTERVAL / 60) },
        Callback = function(v) ctx.setAfkCheck(v * 60) end,
    })

    -- ── AFK Timeout ───────────────────────────────
    TabConfig:Slider({
        Title    = "AFK Timeout (menit)",
        Desc     = "Berapa menit tidak aktif dianggap AFK",
        Icon     = "user-x",
        Step     = 1,
        Value    = { Min = 1, Max = 60, Default = math.floor(ctx.AFK_TIMEOUT / 60) },
        Callback = function(v) ctx.setAfkTimeout(v * 60) end,
    })

    -- ── DC Timeout ────────────────────────────────
    TabConfig:Slider({
        Title    = "DC Timeout (menit)",
        Desc     = "Berapa menit setelah keluar baru dikirim notif DC",
        Icon     = "wifi-off",
        Step     = 1,
        Value    = { Min = 1, Max = 30, Default = math.floor(ctx.DC_REJOIN_TIMEOUT / 60) },
        Callback = function(v) ctx.setDcTimeout(v * 60) end,
    })

    -- ── Auto Sell Interval ────────────────────────
    TabConfig:Slider({
        Title    = "Auto Sell Interval (detik)",
        Desc     = "Seberapa sering auto sell berjalan",
        Icon     = "repeat",
        Step     = 10,
        Value    = { Min = 60, Max = 3600, Default = ctx.AUTO_SELL_INTERVAL },
        Callback = function(v) ctx.setSellInterval(v) end,
    })

    -- ── Info Stats ────────────────────────────────
    local focusCount = 0
    for _ in pairs(FOCUS_FISH) do focusCount = focusCount + 1 end

    TabConfig:Paragraph({
        Title = "Statistik",
        Desc  = "● Focus Fish: " .. focusCount .. " ikan"
             .. "\n● Crystalized: " .. #CRYSTALIZED_FISH .. " ikan"
             .. "\n● VPS: aktif"
             .. "\n● MIN_TIER: " .. ctx.MIN_TIER
             .. "\n● Cooldown: " .. ctx.COOLDOWN .. " detik",
    })

    -- ── Debug / Manual Actions ─────────────────────
    TabConfig:Button({
        Title    = "Test Notifikasi",
        Desc     = "Kirim notif test ke UI",
        Icon     = "bell-ring",
        Callback = function()
            WindUI:Notify({
                Title    = "FishIt Test",
                Content  = "Sistem berjalan normal ✓",
                Duration = 4,
                Icon     = "check-circle",
            })
        end,
    })

    TabSettings:Select()

    print("[FishIt] WindUI berhasil dibangun")
end

return buildUI
