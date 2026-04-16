-- ═══════════════════════════════════════════════════════════════
-- Plaza Booth Seller Manager v2.0
-- Features:
--   ✅ Lihat semua inventory item kamu
--   ✅ List item ke Booth dengan harga custom
--   ✅ Lihat booth kamu sekarang (current listings)
--   ✅ Update harga (delete + re-list)
--   ✅ Hapus listing dari booth
--   ✅ RAP & ALP reference untuk pricing
--   ✅ Auto-price suggestion (% of RAP)
--   ✅ Batch list multiple items
--   ✅ Clear all booth
--   ✅ Drag, minimize, resize
--   ✅ Search/filter inventory
--   ✅ Category filter bar
--   ✅ Confirmation dialogs
--   ✅ Smooth animations
--   ✅ Double-click protection
--   ✅ Sort options (tier/RAP/name)
--   ✅ Quick price presets
--   ✅ Keyboard shortcuts (Esc/R)
--   ✅ Token balance display
--   ✅ Booth slot counter
--   ✅ Update race condition handling
-- ═══════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CoreGui            = game:GetService("CoreGui")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Safe require
local TradeData, Replion, ItemUtility
local requireOK = true
do
    local ok1, td = pcall(function() return require(ReplicatedStorage.Shared.Trading.TradeData) end)
    local ok2, rp = pcall(function() return require(ReplicatedStorage.Packages.Replion) end)
    local ok3, iu = pcall(function() return require(ReplicatedStorage.Shared.ItemUtility) end)
    if ok1 then TradeData = td end
    if ok2 then Replion = rp end
    if ok3 then ItemUtility = iu end
    if not (ok1 and ok2 and ok3) then
        requireOK = false
        warn("[SellerUI] Beberapa module gagal di-require. Pastikan script dijalankan di Plaza.")
    end
end

-- ==========================
-- CONFIG
-- ==========================
local SUPABASE_URL = "http://152.42.234.192"
local SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoicGxhemFfYXBpIiwiZXhwIjo5OTk5OTk5OTk5fQ.8SwQsK5VSm5HGopGN48ZufPK5Jbx-FrzjIlSUA4QwV8"
local ALP_CACHE_TTL        = 600
local LISTING_COOLDOWN     = 3
local DEFAULT_PRICE_PCT    = 90
local MAX_BOOTH_SLOTS      = 16

-- ==========================
-- EXECUTOR HTTP DETECTION
-- ==========================
local executor_request = (syn and syn.request)
    or (http and http.request)
    or http_request
    or (fluxus and fluxus.request)
    or request

-- ==========================
-- COLORS & THEME
-- ==========================
local COLORS = {
    bg           = Color3.fromRGB(18, 18, 24),
    bgSecondary  = Color3.fromRGB(26, 26, 34),
    topBar       = Color3.fromRGB(12, 12, 18),
    accent       = Color3.fromRGB(130, 88, 255),
    accentHover  = Color3.fromRGB(150, 110, 255),
    gold         = Color3.fromRGB(255, 215, 80),
    green        = Color3.fromRGB(40, 200, 100),
    greenHover   = Color3.fromRGB(60, 220, 120),
    red          = Color3.fromRGB(220, 60, 60),
    redHover     = Color3.fromRGB(240, 80, 80),
    orange       = Color3.fromRGB(255, 140, 40),
    cyan         = Color3.fromRGB(80, 200, 240),
    text         = Color3.fromRGB(230, 230, 240),
    textDim      = Color3.fromRGB(140, 140, 160),
    textMuted    = Color3.fromRGB(90, 90, 110),
    cardBg       = Color3.fromRGB(32, 32, 42),
    cardBgHover  = Color3.fromRGB(40, 40, 52),
    listedBg     = Color3.fromRGB(25, 40, 55),
    listedBorder = Color3.fromRGB(80, 160, 255),
    bubbleBg     = Color3.fromRGB(130, 88, 255),
    searchBg     = Color3.fromRGB(35, 35, 48),
    divider      = Color3.fromRGB(50, 50, 65),
    inputBg      = Color3.fromRGB(28, 28, 40),
    tabActive    = Color3.fromRGB(130, 88, 255),
    tabInactive  = Color3.fromRGB(40, 40, 55),
}

-- ==========================
-- HELPERS
-- ==========================
local function FormatNumber(n)
    if type(n) ~= "number" then return tostring(n or "?") end
    local neg = n < 0
    local formatted = tostring(math.floor(math.abs(n)))
    formatted = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if formatted:sub(1, 1) == "," then formatted = formatted:sub(2) end
    return neg and ("-" .. formatted) or formatted
end

local function FormatCompact(n)
    if type(n) ~= "number" then return "?" end
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(math.floor(n))
end

local function Tween(obj, props, duration, style, dir)
    local info = TweenInfo.new(duration or 0.25, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local tierNames = {[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Mythic",[7]="Secret"}
local tierColors = {
    [1] = Color3.fromRGB(160, 160, 170),
    [2] = Color3.fromRGB(80, 200, 80),
    [3] = Color3.fromRGB(80, 140, 255),
    [4] = Color3.fromRGB(180, 80, 255),
    [5] = Color3.fromRGB(255, 200, 50),
    [6] = Color3.fromRGB(255, 80, 80),
    [7] = Color3.fromRGB(255, 60, 200),
}

-- ==========================
-- CLEANUP OLD GUI
-- ==========================
local guiName = "PlazaSellerManagerGUI"
if CoreGui:FindFirstChild(guiName) then
    CoreGui[guiName]:Destroy()
end

local successCoreGui = pcall(function() local _ = CoreGui.Name end)
local TargetGuiParent = successCoreGui and CoreGui or LocalPlayer:WaitForChild("PlayerGui")

-- ==========================
-- RAP & ALP CACHE
-- ==========================
local rapCache = {}
local alpCache = {}

local function FetchRAPFromServer(itemType, itemId)
    local cacheKey = itemType .. "/" .. tostring(itemId)
    if rapCache[cacheKey] ~= nil then
        local cached = rapCache[cacheKey]
        return cached ~= false and cached or nil
    end
    if not TradeData or not TradeData.Remotes or not TradeData.Remotes.GetItemRAP then
        rapCache[cacheKey] = false
        return nil
    end
    local ok, rapValue, _ = pcall(function()
        return TradeData.Remotes.GetItemRAP:InvokeServer(itemType, itemId)
    end)
    if not ok then rapCache[cacheKey] = false; return nil end
    rapValue = tonumber(rapValue)
    if not rapValue or rapValue == -1 then rapCache[cacheKey] = false; return nil end
    rapCache[cacheKey] = rapValue
    return rapValue
end

local function GetAvgPrice(itemType, itemId)
    if not executor_request then return nil end
    if SUPABASE_URL == "" or SUPABASE_KEY == "" then return nil end
    local cacheKey = itemType .. "/" .. tostring(itemId)
    local cached = alpCache[cacheKey]
    if cached and (tick() - cached._time) < ALP_CACHE_TTL then return cached end
    local ok, result = pcall(function()
        return executor_request({
            Url = SUPABASE_URL .. "/rpc/get_avg_price",
            Method = "POST",
            Headers = {
                ["apikey"] = SUPABASE_KEY,
                ["Authorization"] = "Bearer " .. SUPABASE_KEY,
                ["Content-Type"] = "application/json",
            },
            Body = HttpService:JSONEncode({ p_item_type = itemType, p_item_id = tostring(itemId) })
        })
    end)
    if ok and result and result.StatusCode == 200 then
        local decOk, data = pcall(function() return HttpService:JSONDecode(result.Body) end)
        if decOk and data and data[1] then
            local entry = {
                avg = tonumber(data[1].avg_price) or 0,
                median = tonumber(data[1].median_price) or 0,
                count = tonumber(data[1].total_listings) or 0,
                min = tonumber(data[1].min_price) or 0,
                max = tonumber(data[1].max_price) or 0,
                _time = tick()
            }
            alpCache[cacheKey] = entry
            return entry
        end
    end
    return nil
end

-- ==========================
-- Replion Data Access
-- ==========================
local DataReplion = nil
local function GetData()
    if DataReplion then return DataReplion end
    local ok, d = pcall(function() return Replion.Client:WaitReplion("Data") end)
    if ok and d then DataReplion = d; return d end
    return nil
end

local function GetMyBoothListings()
    local saleListings = nil
    local ok = pcall(function() saleListings = Replion.Client:WaitReplion("SaleListings") end)
    if not ok or not saleListings then
        warn("[SellerUI] SaleListings Replion tidak tersedia")
        return {}
    end
    local allData = saleListings:Get({"Players"})
    if not allData then return {} end
    local myUserId = tostring(LocalPlayer.UserId)
    local myData = allData[myUserId]
    if not myData then return {} end
    return myData.Booth or {}
end

local function GetTokenBalance()
    local data = GetData()
    if not data then return 0 end
    local ok, tokens = pcall(function() return data:Get("Tokens") end)
    if ok and tokens then return tonumber(tokens) or 0 end
    -- Fallback paths
    local ok2, tokens2 = pcall(function() return data:Get("Currency.Tokens") end)
    if ok2 and tokens2 then return tonumber(tokens2) or 0 end
    local ok3, tokens3 = pcall(function() return data:Get("Stats.Tokens") end)
    if ok3 and tokens3 then return tonumber(tokens3) or 0 end
    return 0
end

-- ==========================
-- STATE
-- ==========================
local currentTab = "booth"
local currentCategory = nil
local currentSort = "tier_desc"  -- tier_desc, tier_asc, rap_desc, name_asc
local isLoading = false
local isDialogOpen = false  -- double-click protection
local boothEntries = {}
local inventoryEntries = {}
local allItemsCache = {}  -- cached full inventory for fast filtering
local cachedCategoryCounts = {}  -- cached category counts
local lastCategories = nil  -- category bar optimization

-- Forward declares
local LoadBoothListings, LoadInventory, BuildCategoryButtons, SetCategoryActive, FilterAndDisplayInventory

-- ==========================
-- CREATE GUI
-- ==========================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = guiName
ScreenGui.Parent = TargetGuiParent
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 998

-- ─── FLOATING BUBBLE ───
local Bubble = Instance.new("TextButton")
Bubble.Name = "MiniBubble"
Bubble.Size = UDim2.new(0, 50, 0, 50)
Bubble.Position = UDim2.new(1, -70, 0.5, 35)
Bubble.BackgroundColor3 = COLORS.bubbleBg
Bubble.Text = "💰"
Bubble.TextSize = 22
Bubble.Font = Enum.Font.GothamBold
Bubble.TextColor3 = Color3.new(1, 1, 1)
Bubble.AutoButtonColor = false
Bubble.Visible = false
Bubble.Parent = ScreenGui
Bubble.ZIndex = 100
Instance.new("UICorner", Bubble).CornerRadius = UDim.new(1, 0)
local BubbleStroke = Instance.new("UIStroke")
BubbleStroke.Thickness = 2
BubbleStroke.Color = COLORS.accentHover
BubbleStroke.Transparency = 0.3
BubbleStroke.Parent = Bubble

do
    local dragging, dragStart, startPos
    Bubble.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = Bubble.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Bubble.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- ─── MAIN FRAME ───
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 640, 0, 580)
MainFrame.Position = UDim2.new(0.5, -320, 0.5, -290)
MainFrame.BackgroundColor3 = COLORS.bg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)
local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1.5; MainStroke.Color = COLORS.divider; MainStroke.Transparency = 0.5; MainStroke.Parent = MainFrame

local Shadow = Instance.new("ImageLabel")
Shadow.Name = "Shadow"; Shadow.Size = UDim2.new(1, 30, 1, 30); Shadow.Position = UDim2.new(0, -15, 0, -15)
Shadow.BackgroundTransparency = 1; Shadow.Image = "rbxassetid://5554236805"; Shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
Shadow.ImageTransparency = 0.6; Shadow.ScaleType = Enum.ScaleType.Slice; Shadow.SliceCenter = Rect.new(23, 23, 277, 277)
Shadow.ZIndex = -1; Shadow.Parent = MainFrame

-- ─── TOP BAR ───
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"; TopBar.Size = UDim2.new(1, 0, 0, 44)
TopBar.BackgroundColor3 = COLORS.topBar; TopBar.BorderSizePixel = 0; TopBar.Parent = MainFrame
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 12)
local TopBarFix = Instance.new("Frame")
TopBarFix.Size = UDim2.new(1, 0, 0, 14); TopBarFix.Position = UDim2.new(0, 0, 1, -14)
TopBarFix.BackgroundColor3 = COLORS.topBar; TopBarFix.BorderSizePixel = 0; TopBarFix.Parent = TopBar

local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(1, 0, 0, 2); AccentLine.Position = UDim2.new(0, 0, 1, 0)
AccentLine.BackgroundColor3 = COLORS.accent; AccentLine.BorderSizePixel = 0; AccentLine.Parent = TopBar
local AccGrad = Instance.new("UIGradient")
AccGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, COLORS.accent),
    ColorSequenceKeypoint.new(0.5, COLORS.gold),
    ColorSequenceKeypoint.new(1, COLORS.accent),
})
AccGrad.Parent = AccentLine

-- Title
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 220, 1, 0); Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1; Title.Text = "💰 Booth Seller"
Title.TextColor3 = COLORS.gold; Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold; Title.TextSize = 16; Title.Parent = TopBar

local VersionTag = Instance.new("TextLabel")
VersionTag.Size = UDim2.new(0, 35, 0, 14); VersionTag.Position = UDim2.new(0, 155, 0.5, -7)
VersionTag.BackgroundColor3 = COLORS.accent; VersionTag.BackgroundTransparency = 0.7
VersionTag.Text = "v2.0"; VersionTag.TextColor3 = COLORS.accentHover
VersionTag.Font = Enum.Font.GothamBold; VersionTag.TextSize = 9; VersionTag.Parent = TopBar
Instance.new("UICorner", VersionTag).CornerRadius = UDim.new(0, 4)

-- Token balance display
local TokenDisplay = Instance.new("TextLabel")
TokenDisplay.Name = "TokenDisplay"
TokenDisplay.Size = UDim2.new(0, 130, 0, 22)
TokenDisplay.Position = UDim2.new(0, 200, 0.5, -11)
TokenDisplay.BackgroundColor3 = Color3.fromRGB(35, 35, 20)
TokenDisplay.BackgroundTransparency = 0.3
TokenDisplay.Text = "🪙 ---"
TokenDisplay.TextColor3 = COLORS.gold
TokenDisplay.Font = Enum.Font.GothamSemibold
TokenDisplay.TextSize = 11
TokenDisplay.Parent = TopBar
Instance.new("UICorner", TokenDisplay).CornerRadius = UDim.new(0, 6)

local function UpdateTokenDisplay()
    task.spawn(function()
        local bal = GetTokenBalance()
        if bal > 0 then
            TokenDisplay.Text = "🪙 " .. FormatNumber(bal) .. " T"
        else
            TokenDisplay.Text = "🪙 ---"
        end
    end)
end

-- ─── TOP BAR BUTTONS ───
local function CreateTopBtn(name, text, color, size, posX)
    local btn = Instance.new("TextButton")
    btn.Name = name; btn.Size = UDim2.new(0, size, 0, 28)
    btn.Position = UDim2.new(1, posX, 0.5, -14)
    btn.BackgroundColor3 = color; btn.Text = text
    btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 12
    btn.TextColor3 = Color3.new(1, 1, 1); btn.AutoButtonColor = false
    btn.BorderSizePixel = 0; btn.Parent = TopBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseEnter:Connect(function()
        Tween(btn, {BackgroundColor3 = Color3.new(math.min(color.R+0.08,1), math.min(color.G+0.08,1), math.min(color.B+0.08,1))}, 0.15)
    end)
    btn.MouseLeave:Connect(function() Tween(btn, {BackgroundColor3 = color}, 0.15) end)
    return btn
end

local CloseBtn    = CreateTopBtn("CloseBtn", "✕", COLORS.red, 30, -38)
local MinimizeBtn = CreateTopBtn("MinBtn", "─", COLORS.textMuted, 30, -72)
local RefreshBtn  = CreateTopBtn("RefreshBtn", "🔄", COLORS.accent, 30, -106)

-- ─── TAB BAR ───
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"; TabBar.Size = UDim2.new(1, -20, 0, 34)
TabBar.Position = UDim2.new(0, 10, 0, 50)
TabBar.BackgroundTransparency = 1; TabBar.Parent = MainFrame

local function CreateTabBtn(name, text, icon, posX, width)
    local btn = Instance.new("TextButton")
    btn.Name = name; btn.Size = UDim2.new(0, width, 0, 30)
    btn.Position = UDim2.new(0, posX, 0, 2)
    btn.BackgroundColor3 = COLORS.tabInactive; btn.Text = icon .. " " .. text
    btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 12
    btn.TextColor3 = COLORS.textDim; btn.AutoButtonColor = false
    btn.BorderSizePixel = 0; btn.Parent = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local TabBooth     = CreateTabBtn("TabBooth", "Booth Saya", "🏪", 0, 140)
local TabInventory = CreateTabBtn("TabInventory", "Inventory", "📦", 148, 130)
local ClearBoothBtn = CreateTopBtn("ClearBoothBtn", "🗑️ Clear", COLORS.red, 70, -180)

-- Booth slot counter
local SlotCounter = Instance.new("TextLabel")
SlotCounter.Name = "SlotCounter"
SlotCounter.Size = UDim2.new(0, 90, 0, 22)
SlotCounter.Position = UDim2.new(0, 285, 0, 6)
SlotCounter.BackgroundColor3 = COLORS.bgSecondary
SlotCounter.BackgroundTransparency = 0.3
SlotCounter.Text = "Slot: -/" .. MAX_BOOTH_SLOTS
SlotCounter.TextColor3 = COLORS.textDim
SlotCounter.Font = Enum.Font.GothamSemibold
SlotCounter.TextSize = 10
SlotCounter.Parent = TabBar
Instance.new("UICorner", SlotCounter).CornerRadius = UDim.new(0, 6)

-- Batch list button (inventory tab only)
local BatchListBtn = Instance.new("TextButton")
BatchListBtn.Name = "BatchListBtn"
BatchListBtn.Size = UDim2.new(0, 100, 0, 28)
BatchListBtn.Position = UDim2.new(0, 385, 0, 3)
BatchListBtn.BackgroundColor3 = COLORS.green
BatchListBtn.Text = "📦 List Semua"
BatchListBtn.Font = Enum.Font.GothamBold
BatchListBtn.TextSize = 10
BatchListBtn.TextColor3 = Color3.new(1, 1, 1)
BatchListBtn.AutoButtonColor = false
BatchListBtn.BorderSizePixel = 0
BatchListBtn.Visible = false
BatchListBtn.Parent = TabBar
Instance.new("UICorner", BatchListBtn).CornerRadius = UDim.new(0, 6)
BatchListBtn.MouseEnter:Connect(function() Tween(BatchListBtn, {BackgroundColor3 = COLORS.greenHover}, 0.15) end)
BatchListBtn.MouseLeave:Connect(function() Tween(BatchListBtn, {BackgroundColor3 = COLORS.green}, 0.15) end)

-- ─── SEARCH & SORT BAR ───
local SearchBar = Instance.new("Frame")
SearchBar.Name = "SearchBar"; SearchBar.Size = UDim2.new(1, -20, 0, 30)
SearchBar.Position = UDim2.new(0, 10, 0, 88)
SearchBar.BackgroundTransparency = 1; SearchBar.Parent = MainFrame

local SearchBox = Instance.new("TextBox")
SearchBox.Name = "SearchBox"; SearchBox.Size = UDim2.new(0, 200, 0, 28)
SearchBox.Position = UDim2.new(0, 0, 0, 1)
SearchBox.BackgroundColor3 = COLORS.searchBg; SearchBox.PlaceholderText = "🔍 Cari item..."
SearchBox.PlaceholderColor3 = COLORS.textMuted; SearchBox.Text = ""
SearchBox.TextColor3 = COLORS.text; SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 12; SearchBox.ClearTextOnFocus = false; SearchBox.BorderSizePixel = 0
SearchBox.Parent = SearchBar
Instance.new("UICorner", SearchBox).CornerRadius = UDim.new(0, 6)
local SPad = Instance.new("UIPadding"); SPad.PaddingLeft = UDim.new(0, 8); SPad.Parent = SearchBox

-- Sort buttons
local SortFrame = Instance.new("Frame")
SortFrame.Name = "SortFrame"
SortFrame.Size = UDim2.new(0, 200, 0, 28)
SortFrame.Position = UDim2.new(0, 208, 0, 1)
SortFrame.BackgroundTransparency = 1
SortFrame.Parent = SearchBar

local sortOptions = {
    {key = "tier_desc", text = "Tier ↓", width = 48},
    {key = "tier_asc",  text = "Tier ↑", width = 48},
    {key = "rap_desc",  text = "RAP ↓",  width = 48},
    {key = "name_asc",  text = "A-Z",    width = 36},
}

local sortButtons = {}
local sortX = 0
for _, opt in ipairs(sortOptions) do
    local btn = Instance.new("TextButton")
    btn.Name = "Sort_" .. opt.key
    btn.Size = UDim2.new(0, opt.width, 0, 22)
    btn.Position = UDim2.new(0, sortX, 0, 3)
    btn.BackgroundColor3 = (currentSort == opt.key) and COLORS.accent or COLORS.searchBg
    btn.Text = opt.text
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 9
    btn.TextColor3 = (currentSort == opt.key) and Color3.new(1,1,1) or COLORS.textDim
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = SortFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local sortKey = opt.key
    btn.MouseButton1Click:Connect(function()
        currentSort = sortKey
        for k, b in pairs(sortButtons) do
            b.BackgroundColor3 = (k == sortKey) and COLORS.accent or COLORS.searchBg
            b.TextColor3 = (k == sortKey) and Color3.new(1,1,1) or COLORS.textDim
        end
        if currentTab == "booth" then LoadBoothListings() else FilterAndDisplayInventory() end
    end)

    sortButtons[opt.key] = btn
    sortX = sortX + opt.width + 3
end

-- Price % input
local PricePctLabel = Instance.new("TextLabel")
PricePctLabel.Name = "PricePctLabel"
PricePctLabel.Size = UDim2.new(0, 55, 0, 28)
PricePctLabel.Position = UDim2.new(1, -120, 0, 1)
PricePctLabel.BackgroundTransparency = 1
PricePctLabel.Text = "Harga%:"
PricePctLabel.TextColor3 = COLORS.textDim
PricePctLabel.Font = Enum.Font.Gotham
PricePctLabel.TextSize = 10
PricePctLabel.TextXAlignment = Enum.TextXAlignment.Right
PricePctLabel.Parent = SearchBar

local PricePctBox = Instance.new("TextBox")
PricePctBox.Name = "PricePctBox"
PricePctBox.Size = UDim2.new(0, 40, 0, 24)
PricePctBox.Position = UDim2.new(1, -62, 0, 3)
PricePctBox.BackgroundColor3 = COLORS.searchBg
PricePctBox.Text = tostring(DEFAULT_PRICE_PCT)
PricePctBox.TextColor3 = COLORS.gold
PricePctBox.Font = Enum.Font.GothamSemibold
PricePctBox.TextSize = 11
PricePctBox.ClearTextOnFocus = true
PricePctBox.BorderSizePixel = 0
PricePctBox.Parent = SearchBar
Instance.new("UICorner", PricePctBox).CornerRadius = UDim.new(0, 6)

local PricePctSuffix = Instance.new("TextLabel")
PricePctSuffix.Size = UDim2.new(0, 16, 0, 28)
PricePctSuffix.Position = UDim2.new(1, -20, 0, 1)
PricePctSuffix.BackgroundTransparency = 1
PricePctSuffix.Text = "%"
PricePctSuffix.TextColor3 = COLORS.textDim
PricePctSuffix.Font = Enum.Font.GothamBold
PricePctSuffix.TextSize = 11
PricePctSuffix.Parent = SearchBar

-- ─── CATEGORY FILTER BAR ───
local CATEGORY_BAR_HEIGHT = 32

local CategoryBar = Instance.new("Frame")
CategoryBar.Name = "CategoryBar"
CategoryBar.Size = UDim2.new(1, -20, 0, CATEGORY_BAR_HEIGHT)
CategoryBar.Position = UDim2.new(0, 10, 0, 120)
CategoryBar.BackgroundTransparency = 1
CategoryBar.Visible = false
CategoryBar.Parent = MainFrame

local CategoryScroll = Instance.new("ScrollingFrame")
CategoryScroll.Name = "CatScroll"; CategoryScroll.Size = UDim2.new(1, 0, 1, 0)
CategoryScroll.BackgroundTransparency = 1; CategoryScroll.BorderSizePixel = 0
CategoryScroll.ScrollBarThickness = 0; CategoryScroll.ScrollingDirection = Enum.ScrollingDirection.X
CategoryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
CategoryScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
CategoryScroll.Parent = CategoryBar

local CatLayout = Instance.new("UIListLayout")
CatLayout.FillDirection = Enum.FillDirection.Horizontal
CatLayout.Padding = UDim.new(0, 5)
CatLayout.SortOrder = Enum.SortOrder.LayoutOrder
CatLayout.VerticalAlignment = Enum.VerticalAlignment.Center
CatLayout.Parent = CategoryScroll

local categoryIcons = {
    ["Fish"] = "🐟", ["Fishing Rods"] = "🎣", ["Boats"] = "🚤", ["Emotes"] = "💃",
    ["Enchant Stones"] = "💎", ["Hats"] = "🎩", ["Shoes"] = "👟", ["Shirts"] = "👕",
    ["Pants"] = "👖", ["Tools"] = "🔧", ["Accessories"] = "💍", ["Backpacks"] = "🎒",
    ["Furniture"] = "🪑", ["Toys"] = "🧸", ["Resources"] = "📦",
}

local categoryButtons = {}

SetCategoryActive = function(catName)
    currentCategory = catName
    for name, btn in pairs(categoryButtons) do
        if name == catName then
            btn.BackgroundColor3 = COLORS.accent
            btn.TextColor3 = Color3.new(1, 1, 1)
        else
            btn.BackgroundColor3 = COLORS.searchBg
            btn.TextColor3 = COLORS.textDim
        end
    end
end

BuildCategoryButtons = function(categories)
    -- Optimization: skip rebuild if categories haven't changed
    local catKey = ""
    local sorted = {}
    for cat, count in pairs(categories) do
        table.insert(sorted, {name = cat, count = count})
        catKey = catKey .. cat .. ":" .. count .. ";"
    end
    if catKey == lastCategories then return end
    lastCategories = catKey

    for _, child in ipairs(CategoryScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    categoryButtons = {}

    -- "All" button
    local allBtn = Instance.new("TextButton")
    allBtn.Name = "Cat_All"; allBtn.Size = UDim2.new(0, 60, 0, 24)
    allBtn.BackgroundColor3 = currentCategory == nil and COLORS.accent or COLORS.searchBg
    allBtn.Text = "📋 Semua"
    allBtn.Font = Enum.Font.GothamSemibold; allBtn.TextSize = 10
    allBtn.TextColor3 = currentCategory == nil and Color3.new(1,1,1) or COLORS.textDim
    allBtn.AutoButtonColor = false; allBtn.BorderSizePixel = 0
    allBtn.LayoutOrder = 0; allBtn.Parent = CategoryScroll
    Instance.new("UICorner", allBtn).CornerRadius = UDim.new(0, 12)
    categoryButtons["__ALL__"] = allBtn

    allBtn.MouseButton1Click:Connect(function()
        currentCategory = nil
        SetCategoryActive(nil)
        allBtn.BackgroundColor3 = COLORS.accent
        allBtn.TextColor3 = Color3.new(1, 1, 1)
        if FilterAndDisplayInventory then FilterAndDisplayInventory() end
    end)

    table.sort(sorted, function(a, b) return a.name < b.name end)

    for i, info in ipairs(sorted) do
        local icon = categoryIcons[info.name] or "📁"
        local displayText = icon .. " " .. info.name .. " (" .. info.count .. ")"
        local textWidth = math.max(#displayText * 6, 70)

        local btn = Instance.new("TextButton")
        btn.Name = "Cat_" .. info.name; btn.Size = UDim2.new(0, textWidth, 0, 24)
        btn.BackgroundColor3 = (currentCategory == info.name) and COLORS.accent or COLORS.searchBg
        btn.Text = displayText
        btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 9
        btn.TextColor3 = (currentCategory == info.name) and Color3.new(1,1,1) or COLORS.textDim
        btn.AutoButtonColor = false; btn.BorderSizePixel = 0
        btn.LayoutOrder = i; btn.Parent = CategoryScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
        categoryButtons[info.name] = btn

        btn.MouseEnter:Connect(function()
            if currentCategory ~= info.name then Tween(btn, {BackgroundColor3 = COLORS.cardBgHover}, 0.15) end
        end)
        btn.MouseLeave:Connect(function()
            if currentCategory ~= info.name then Tween(btn, {BackgroundColor3 = COLORS.searchBg}, 0.15) end
        end)

        local catName = info.name
        btn.MouseButton1Click:Connect(function()
            SetCategoryActive(catName)
            allBtn.BackgroundColor3 = COLORS.searchBg
            allBtn.TextColor3 = COLORS.textDim
            if FilterAndDisplayInventory then FilterAndDisplayInventory() end
        end)
    end
end

-- ─── SCROLL AREA ───
local SCROLL_Y_BOOTH = 122
local SCROLL_Y_INV   = 122 + CATEGORY_BAR_HEIGHT + 4

local Scroll = Instance.new("ScrollingFrame")
Scroll.Name = "ItemScroll"
Scroll.Size = UDim2.new(1, -20, 1, -160)
Scroll.Position = UDim2.new(0, 10, 0, SCROLL_Y_BOOTH)
Scroll.BackgroundTransparency = 1
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.ScrollBarThickness = 4
Scroll.ScrollBarImageColor3 = COLORS.accent
Scroll.BorderSizePixel = 0
Scroll.Parent = MainFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = Scroll
UIListLayout.Padding = UDim.new(0, 5)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ─── STATUS BAR ───
local StatusBar = Instance.new("Frame")
StatusBar.Name = "StatusBar"; StatusBar.Size = UDim2.new(1, 0, 0, 28)
StatusBar.Position = UDim2.new(0, 0, 1, -28)
StatusBar.BackgroundColor3 = COLORS.topBar; StatusBar.BorderSizePixel = 0; StatusBar.Parent = MainFrame
Instance.new("UICorner", StatusBar).CornerRadius = UDim.new(0, 8)
local StatusFix = Instance.new("Frame")
StatusFix.Size = UDim2.new(1, 0, 0, 10); StatusFix.Position = UDim2.new(0, 0, 0, 0)
StatusFix.BackgroundColor3 = COLORS.topBar; StatusFix.BorderSizePixel = 0; StatusFix.Parent = StatusBar

local StatusText = Instance.new("TextLabel")
StatusText.Name = "StatusText"; StatusText.Size = UDim2.new(0.65, 0, 1, 0)
StatusText.Position = UDim2.new(0, 12, 0, 0); StatusText.BackgroundTransparency = 1
StatusText.Text = "Ready"; StatusText.TextColor3 = COLORS.textDim
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Font = Enum.Font.Gotham; StatusText.TextSize = 11; StatusText.Parent = StatusBar

local StatsText = Instance.new("TextLabel")
StatsText.Name = "StatsText"; StatsText.Size = UDim2.new(0.35, -12, 1, 0)
StatsText.Position = UDim2.new(0.65, 0, 0, 0); StatsText.BackgroundTransparency = 1
StatsText.Text = ""; StatsText.TextColor3 = COLORS.textMuted
StatsText.TextXAlignment = Enum.TextXAlignment.Right
StatsText.Font = Enum.Font.Gotham; StatsText.TextSize = 10; StatsText.Parent = StatusBar

-- ─── RESIZE HANDLE ───
local MIN_WIDTH, MIN_HEIGHT = 500, 380
local MAX_WIDTH, MAX_HEIGHT = 950, 750

local ResizeHandle = Instance.new("TextButton")
ResizeHandle.Name = "ResizeHandle"; ResizeHandle.Size = UDim2.new(0, 22, 0, 22)
ResizeHandle.Position = UDim2.new(1, -22, 1, -22)
ResizeHandle.BackgroundColor3 = COLORS.divider; ResizeHandle.BackgroundTransparency = 0.5
ResizeHandle.Text = "⇲"; ResizeHandle.TextSize = 14; ResizeHandle.TextColor3 = COLORS.textMuted
ResizeHandle.Font = Enum.Font.GothamBold; ResizeHandle.AutoButtonColor = false
ResizeHandle.BorderSizePixel = 0; ResizeHandle.ZIndex = 10; ResizeHandle.Parent = MainFrame
Instance.new("UICorner", ResizeHandle).CornerRadius = UDim.new(0, 4)

ResizeHandle.MouseEnter:Connect(function() Tween(ResizeHandle, {BackgroundTransparency = 0, TextColor3 = COLORS.accent}, 0.15) end)
ResizeHandle.MouseLeave:Connect(function() Tween(ResizeHandle, {BackgroundTransparency = 0.5, TextColor3 = COLORS.textMuted}, 0.15) end)

do
    local resizing, resizeStart, startSize = false, nil, nil
    ResizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true; resizeStart = input.Position; startSize = MainFrame.AbsoluteSize
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then resizing = false end end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - resizeStart
            MainFrame.Size = UDim2.new(0, math.clamp(startSize.X + delta.X, MIN_WIDTH, MAX_WIDTH), 0, math.clamp(startSize.Y + delta.Y, MIN_HEIGHT, MAX_HEIGHT))
        end
    end)
end

-- ─── DRAG ───
do
    local dragging, dragInput, dragStart, startPos
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = MainFrame.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    TopBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- ─── MINIMIZE / RESTORE ───
local isMinimized = false
local lastFrameSize = UDim2.new(0, 640, 0, 580)

local function MinimizeToWindow()
    if isMinimized then return end
    isMinimized = true; lastFrameSize = MainFrame.Size
    Tween(MainFrame, {Size = UDim2.new(0, 0, 0, 0)}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.wait(0.3); MainFrame.Visible = false; Bubble.Visible = true
    Bubble.Size = UDim2.new(0, 0, 0, 0)
    Tween(Bubble, {Size = UDim2.new(0, 50, 0, 50)}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

local function RestoreFromBubble()
    if not isMinimized then return end
    isMinimized = false
    Tween(Bubble, {Size = UDim2.new(0, 0, 0, 0)}, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.wait(0.2); Bubble.Visible = false; MainFrame.Visible = true
    MainFrame.Size = UDim2.new(0, 0, 0, 0)
    Tween(MainFrame, {Size = lastFrameSize}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

Bubble.MouseButton1Click:Connect(RestoreFromBubble)
MinimizeBtn.MouseButton1Click:Connect(MinimizeToWindow)
CloseBtn.MouseButton1Click:Connect(function()
    Tween(MainFrame, {Size = UDim2.new(0, 0, 0, 0)}, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.wait(0.25); ScreenGui:Destroy()
end)

-- ==========================
-- LOADING/EMPTY STATES
-- ==========================
local function ShowLoading(show, msg)
    local existing = Scroll:FindFirstChild("LoadingFrame")
    if existing then existing:Destroy() end
    if not show then return end
    local lf = Instance.new("Frame"); lf.Name = "LoadingFrame"
    lf.Size = UDim2.new(1, 0, 0, 60); lf.BackgroundTransparency = 1; lf.LayoutOrder = -1; lf.Parent = Scroll
    local lt = Instance.new("TextLabel"); lt.Size = UDim2.new(1, 0, 1, 0); lt.BackgroundTransparency = 1
    lt.Text = msg or "⏳ Memuat data..."; lt.TextColor3 = COLORS.textDim
    lt.Font = Enum.Font.GothamSemibold; lt.TextSize = 14; lt.Parent = lf
end

local function ShowEmpty(msg)
    local ef = Instance.new("Frame"); ef.Name = "EmptyFrame"
    ef.Size = UDim2.new(1, 0, 0, 100); ef.BackgroundTransparency = 1; ef.LayoutOrder = 0; ef.Parent = Scroll
    local et = Instance.new("TextLabel"); et.Size = UDim2.new(1, 0, 1, 0); et.BackgroundTransparency = 1
    et.Text = msg or "📭 Tidak ada item."; et.TextColor3 = COLORS.textMuted
    et.Font = Enum.Font.Gotham; et.TextSize = 13; et.Parent = ef
end

local function ClearScroll()
    for _, child in ipairs(Scroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end

-- ==========================
-- CONFIRMATION DIALOG
-- ==========================
local function ShowConfirmDialog(title, message, onConfirm, onCancel)
    if isDialogOpen then return end
    isDialogOpen = true

    local overlay = Instance.new("Frame")
    overlay.Name = "ConfirmOverlay"; overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0); overlay.BackgroundTransparency = 0.5
    overlay.BorderSizePixel = 0; overlay.ZIndex = 50; overlay.Parent = MainFrame

    local dialog = Instance.new("Frame")
    dialog.Name = "DialogBox"; dialog.Size = UDim2.new(0, 320, 0, 170)
    dialog.Position = UDim2.new(0.5, -160, 0.5, -85)
    dialog.BackgroundColor3 = COLORS.bgSecondary; dialog.BorderSizePixel = 0
    dialog.ZIndex = 51; dialog.Parent = overlay
    Instance.new("UICorner", dialog).CornerRadius = UDim.new(0, 12)
    local ds = Instance.new("UIStroke"); ds.Thickness = 1.5; ds.Color = COLORS.accent; ds.Transparency = 0.3; ds.Parent = dialog

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 28); titleLabel.Position = UDim2.new(0, 10, 0, 12)
    titleLabel.BackgroundTransparency = 1; titleLabel.Text = title or "Konfirmasi"
    titleLabel.TextColor3 = COLORS.gold; titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 15; titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.ZIndex = 52; titleLabel.Parent = dialog

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, -20, 0, 1); divider.Position = UDim2.new(0, 10, 0, 44)
    divider.BackgroundColor3 = COLORS.divider; divider.BorderSizePixel = 0; divider.ZIndex = 52; divider.Parent = dialog

    local msgLabel = Instance.new("TextLabel")
    msgLabel.Size = UDim2.new(1, -24, 0, 55); msgLabel.Position = UDim2.new(0, 12, 0, 48)
    msgLabel.BackgroundTransparency = 1; msgLabel.Text = message or "Apakah kamu yakin?"
    msgLabel.TextColor3 = COLORS.text; msgLabel.Font = Enum.Font.Gotham; msgLabel.TextSize = 12
    msgLabel.TextWrapped = true; msgLabel.TextXAlignment = Enum.TextXAlignment.Center
    msgLabel.ZIndex = 52; msgLabel.Parent = dialog

    local btnYes = Instance.new("TextButton")
    btnYes.Size = UDim2.new(0, 120, 0, 34); btnYes.Position = UDim2.new(0.5, -130, 1, -50)
    btnYes.BackgroundColor3 = COLORS.green; btnYes.Text = "✅ Ya, Lanjut"
    btnYes.Font = Enum.Font.GothamBold; btnYes.TextSize = 12; btnYes.TextColor3 = Color3.new(1,1,1)
    btnYes.AutoButtonColor = false; btnYes.BorderSizePixel = 0; btnYes.ZIndex = 52; btnYes.Parent = dialog
    Instance.new("UICorner", btnYes).CornerRadius = UDim.new(0, 8)

    local btnNo = Instance.new("TextButton")
    btnNo.Size = UDim2.new(0, 120, 0, 34); btnNo.Position = UDim2.new(0.5, 10, 1, -50)
    btnNo.BackgroundColor3 = COLORS.textMuted; btnNo.Text = "❌ Batal"
    btnNo.Font = Enum.Font.GothamBold; btnNo.TextSize = 12; btnNo.TextColor3 = Color3.new(1,1,1)
    btnNo.AutoButtonColor = false; btnNo.BorderSizePixel = 0; btnNo.ZIndex = 52; btnNo.Parent = dialog
    Instance.new("UICorner", btnNo).CornerRadius = UDim.new(0, 8)

    btnYes.MouseEnter:Connect(function() Tween(btnYes, {BackgroundColor3 = COLORS.greenHover}, 0.15) end)
    btnYes.MouseLeave:Connect(function() Tween(btnYes, {BackgroundColor3 = COLORS.green}, 0.15) end)
    btnNo.MouseEnter:Connect(function() Tween(btnNo, {BackgroundColor3 = Color3.fromRGB(110,110,130)}, 0.15) end)
    btnNo.MouseLeave:Connect(function() Tween(btnNo, {BackgroundColor3 = COLORS.textMuted}, 0.15) end)

    -- Entrance animation
    dialog.Size = UDim2.new(0, 0, 0, 0); dialog.Position = UDim2.new(0.5, 0, 0.5, 0)
    overlay.BackgroundTransparency = 1
    Tween(overlay, {BackgroundTransparency = 0.5}, 0.2)
    Tween(dialog, {Size = UDim2.new(0, 320, 0, 170), Position = UDim2.new(0.5, -160, 0.5, -85)}, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    local function CloseDialog()
        Tween(dialog, {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        Tween(overlay, {BackgroundTransparency = 1}, 0.2)
        task.wait(0.2)
        if overlay and overlay.Parent then overlay:Destroy() end
        isDialogOpen = false
    end

    btnYes.MouseButton1Click:Connect(function()
        CloseDialog()
        if onConfirm then onConfirm() end
    end)
    btnNo.MouseButton1Click:Connect(function()
        CloseDialog()
        if onCancel then onCancel() end
    end)
    overlay.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local ap = dialog.AbsolutePosition; local as = dialog.AbsoluteSize; local mp = input.Position
            if mp.X < ap.X or mp.X > ap.X + as.X or mp.Y < ap.Y or mp.Y > ap.Y + as.Y then
                CloseDialog()
                if onCancel then onCancel() end
            end
        end
    end)
end

-- ==========================
-- SORT HELPER
-- ==========================
local function SortEntries(entries)
    table.sort(entries, function(a, b)
        if currentSort == "tier_desc" then
            if (a.ItemTier or 0) ~= (b.ItemTier or 0) then return (a.ItemTier or 0) > (b.ItemTier or 0) end
            return (a.ItemName or "") < (b.ItemName or "")
        elseif currentSort == "tier_asc" then
            if (a.ItemTier or 0) ~= (b.ItemTier or 0) then return (a.ItemTier or 0) < (b.ItemTier or 0) end
            return (a.ItemName or "") < (b.ItemName or "")
        elseif currentSort == "rap_desc" then
            if (a.RAP or 0) ~= (b.RAP or 0) then return (a.RAP or 0) > (b.RAP or 0) end
            return (a.ItemName or "") < (b.ItemName or "")
        elseif currentSort == "name_asc" then
            return (a.ItemName or "") < (b.ItemName or "")
        end
        return false
    end)
end

-- ==========================
-- BOOTH CARD
-- ==========================
local function CreateBoothCard(data, layoutOrder)
    local card = Instance.new("Frame")
    card.Name = "BoothCard_" .. layoutOrder
    card.Size = UDim2.new(1, -4, 0, 80)
    card.BackgroundColor3 = COLORS.listedBg
    card.BorderSizePixel = 0; card.LayoutOrder = layoutOrder
    card.Parent = Scroll; card.ClipsDescendants = true
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
    local cs = Instance.new("UIStroke"); cs.Thickness = 1; cs.Color = COLORS.listedBorder; cs.Transparency = 0.6; cs.Parent = card

    card.MouseEnter:Connect(function() Tween(card, {BackgroundColor3 = Color3.fromRGB(30, 48, 65)}, 0.15) end)
    card.MouseLeave:Connect(function() Tween(card, {BackgroundColor3 = COLORS.listedBg}, 0.15) end)

    -- Icon
    local RankLabel = Instance.new("TextLabel")
    RankLabel.Size = UDim2.new(0, 32, 0, 32); RankLabel.Position = UDim2.new(0, 8, 0.5, -16)
    RankLabel.BackgroundColor3 = COLORS.accent; RankLabel.BackgroundTransparency = 0.3
    RankLabel.Text = "🏪"; RankLabel.TextSize = 16; RankLabel.TextColor3 = Color3.new(1,1,1)
    RankLabel.Font = Enum.Font.GothamBold; RankLabel.Parent = card
    Instance.new("UICorner", RankLabel).CornerRadius = UDim.new(0, 6)

    -- Name
    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(0, 200, 0, 18); NameLabel.Position = UDim2.new(0, 48, 0, 8)
    NameLabel.BackgroundTransparency = 1; NameLabel.Text = data.ItemName or "Unknown"
    NameLabel.TextColor3 = tierColors[data.ItemTier] or COLORS.text
    NameLabel.TextXAlignment = Enum.TextXAlignment.Left
    NameLabel.Font = Enum.Font.GothamBold; NameLabel.TextSize = 14
    NameLabel.TextTruncate = Enum.TextTruncate.AtEnd; NameLabel.Parent = card

    -- Tier + Type
    local TierLabel = Instance.new("TextLabel")
    TierLabel.Size = UDim2.new(0, 200, 0, 14); TierLabel.Position = UDim2.new(0, 48, 0, 26)
    TierLabel.BackgroundTransparency = 1
    TierLabel.Text = (tierNames[data.ItemTier] or "?") .. " • " .. (data.ItemType or "?")
    TierLabel.TextColor3 = COLORS.textDim; TierLabel.TextXAlignment = Enum.TextXAlignment.Left
    TierLabel.Font = Enum.Font.Gotham; TierLabel.TextSize = 10; TierLabel.Parent = card

    -- RAP/ALP info
    local rapAlpParts = {}
    if data.RAP and data.RAP > 0 then
        local pct = math.floor((data.Price / data.RAP) * 100)
        table.insert(rapAlpParts, string.format("RAP: %s (%d%%)", FormatCompact(data.RAP), pct))
    else table.insert(rapAlpParts, "RAP: -") end
    if data.ALP and data.ALP.avg and data.ALP.avg > 0 then
        local alpPct = math.floor((data.Price / data.ALP.avg) * 100)
        table.insert(rapAlpParts, string.format("ALP: %s (%d%%)", FormatCompact(data.ALP.avg), alpPct))
    end

    local RapAlpLabel = Instance.new("TextLabel")
    RapAlpLabel.Size = UDim2.new(0, 300, 0, 14); RapAlpLabel.Position = UDim2.new(0, 48, 0, 44)
    RapAlpLabel.BackgroundTransparency = 1; RapAlpLabel.Text = table.concat(rapAlpParts, " │ ")
    RapAlpLabel.TextColor3 = COLORS.textDim; RapAlpLabel.TextXAlignment = Enum.TextXAlignment.Left
    RapAlpLabel.Font = Enum.Font.Gotham; RapAlpLabel.TextSize = 10; RapAlpLabel.Parent = card

    -- Current price
    local PriceLabel = Instance.new("TextLabel")
    PriceLabel.Size = UDim2.new(0, 90, 0, 20); PriceLabel.Position = UDim2.new(1, -270, 0, 8)
    PriceLabel.BackgroundTransparency = 1; PriceLabel.Text = FormatNumber(data.Price) .. " T"
    PriceLabel.TextColor3 = COLORS.gold; PriceLabel.TextXAlignment = Enum.TextXAlignment.Right
    PriceLabel.Font = Enum.Font.GothamBold; PriceLabel.TextSize = 14; PriceLabel.Parent = card

    -- New price input
    local PriceInput = Instance.new("TextBox")
    PriceInput.Size = UDim2.new(0, 70, 0, 24); PriceInput.Position = UDim2.new(1, -270, 0, 38)
    PriceInput.BackgroundColor3 = COLORS.inputBg; PriceInput.Text = tostring(data.Price)
    PriceInput.PlaceholderText = "Harga baru"; PriceInput.PlaceholderColor3 = COLORS.textMuted
    PriceInput.TextColor3 = COLORS.text; PriceInput.Font = Enum.Font.Gotham
    PriceInput.TextSize = 11; PriceInput.ClearTextOnFocus = true; PriceInput.BorderSizePixel = 0
    PriceInput.Parent = card
    Instance.new("UICorner", PriceInput).CornerRadius = UDim.new(0, 4)

    -- Update button
    local UpdateBtn = Instance.new("TextButton")
    UpdateBtn.Size = UDim2.new(0, 72, 0, 28); UpdateBtn.Position = UDim2.new(1, -170, 0.5, -14)
    UpdateBtn.BackgroundColor3 = COLORS.accent; UpdateBtn.Text = "📝 Update"
    UpdateBtn.Font = Enum.Font.GothamBold; UpdateBtn.TextSize = 11; UpdateBtn.TextColor3 = Color3.new(1,1,1)
    UpdateBtn.AutoButtonColor = false; UpdateBtn.BorderSizePixel = 0; UpdateBtn.Parent = card
    Instance.new("UICorner", UpdateBtn).CornerRadius = UDim.new(0, 6)
    UpdateBtn.MouseEnter:Connect(function() Tween(UpdateBtn, {BackgroundColor3 = COLORS.accentHover}, 0.15) end)
    UpdateBtn.MouseLeave:Connect(function() Tween(UpdateBtn, {BackgroundColor3 = COLORS.accent}, 0.15) end)

    UpdateBtn.MouseButton1Click:Connect(function()
        if isDialogOpen then return end
        local newPrice = tonumber(PriceInput.Text)
        if not newPrice or newPrice <= 0 then StatusText.Text = "❌ Harga tidak valid!"; return end

        ShowConfirmDialog(
            "📝 Update Harga",
            string.format("Update harga %s\ndari %s T → %s T?", data.ItemName or "item", FormatNumber(data.Price), FormatNumber(newPrice)),
            function()
                UpdateBtn.Text = "⏳..."
                StatusText.Text = "📝 Mengupdate harga " .. (data.ItemName or "item") .. "..."
                task.spawn(function()
                    local delOk, delErr = pcall(function()
                        return TradeData.Remotes.DeleteSaleListing:InvokeServer("Booth", data.ListingKey)
                    end)
                    if not delOk then
                        UpdateBtn.Text = "❌ Gagal"; StatusText.Text = "❌ Gagal hapus: " .. tostring(delErr)
                        task.wait(2); UpdateBtn.Text = "📝 Update"; return
                    end
                    task.wait(LISTING_COOLDOWN)
                    local listOk, listResult = pcall(function()
                        return TradeData.Remotes.CreateSaleListing:InvokeServer("Booth", data.ItemType, data.UUID, newPrice)
                    end)
                    if listOk then
                        UpdateBtn.Text = "✅ OK"; PriceLabel.Text = FormatNumber(newPrice) .. " T"
                        StatusText.Text = "✅ Harga " .. (data.ItemName or "item") .. " diupdate ke " .. FormatNumber(newPrice)
                        UpdateTokenDisplay()
                    else
                        local errStr = tostring(listResult):lower()
                        if errStr:find("not found") or errStr:find("invalid") or errStr:find("sold") then
                            UpdateBtn.Text = "⚠️ Terjual?"; StatusText.Text = "⚠️ Item mungkin sudah terjual saat proses update!"
                        else
                            UpdateBtn.Text = "❌ Gagal"; StatusText.Text = "❌ Gagal re-list: " .. tostring(listResult)
                        end
                    end
                    task.wait(2); UpdateBtn.Text = "📝 Update"
                end)
            end
        )
    end)

    -- Remove button
    local RemoveBtn = Instance.new("TextButton")
    RemoveBtn.Size = UDim2.new(0, 66, 0, 28); RemoveBtn.Position = UDim2.new(1, -88, 0.5, -14)
    RemoveBtn.BackgroundColor3 = COLORS.red; RemoveBtn.Text = "🗑️ Hapus"
    RemoveBtn.Font = Enum.Font.GothamBold; RemoveBtn.TextSize = 11; RemoveBtn.TextColor3 = Color3.new(1,1,1)
    RemoveBtn.AutoButtonColor = false; RemoveBtn.BorderSizePixel = 0; RemoveBtn.Parent = card
    Instance.new("UICorner", RemoveBtn).CornerRadius = UDim.new(0, 6)
    RemoveBtn.MouseEnter:Connect(function() Tween(RemoveBtn, {BackgroundColor3 = COLORS.redHover}, 0.15) end)
    RemoveBtn.MouseLeave:Connect(function() Tween(RemoveBtn, {BackgroundColor3 = COLORS.red}, 0.15) end)

    RemoveBtn.MouseButton1Click:Connect(function()
        if isDialogOpen then return end
        ShowConfirmDialog(
            "🗑️ Hapus Listing",
            string.format("Hapus %s (%s T) dari booth?\nItem akan kembali ke inventory.", data.ItemName or "item", FormatNumber(data.Price)),
            function()
                RemoveBtn.Text = "⏳..."
                task.spawn(function()
                    local ok, err = pcall(function() return TradeData.Remotes.DeleteSaleListing:InvokeServer("Booth", data.ListingKey) end)
                    if ok then
                        StatusText.Text = "✅ " .. (data.ItemName or "item") .. " dihapus dari booth"
                        Tween(card, {BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 0)}, 0.3)
                        task.wait(0.3); card:Destroy(); task.wait(0.05)
                        Scroll.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 10)
                        UpdateTokenDisplay()
                    else
                        RemoveBtn.Text = "❌"; StatusText.Text = "❌ Gagal hapus: " .. tostring(err)
                        task.wait(2); RemoveBtn.Text = "🗑️ Hapus"
                    end
                end)
            end
        )
    end)

    -- Entry animation
    card.Position = UDim2.new(0.3, 0, 0, 0); card.BackgroundTransparency = 0.5
    Tween(card, {Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0}, 0.3 + layoutOrder * 0.03)
    return card
end

-- ==========================
-- INVENTORY CARD
-- ==========================
local function CreateInventoryCard(data, layoutOrder)
    local isListed = data.IsListed

    local card = Instance.new("Frame")
    card.Name = "InvCard_" .. layoutOrder
    card.Size = UDim2.new(1, -4, 0, 72)
    card.BackgroundColor3 = isListed and Color3.fromRGB(35, 35, 28) or COLORS.cardBg
    card.BorderSizePixel = 0; card.LayoutOrder = layoutOrder
    card.Parent = Scroll; card.ClipsDescendants = true
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    if isListed then
        local ls = Instance.new("UIStroke"); ls.Thickness = 1; ls.Color = COLORS.orange; ls.Transparency = 0.5; ls.Parent = card
    end

    card.MouseEnter:Connect(function() Tween(card, {BackgroundColor3 = isListed and Color3.fromRGB(42, 42, 32) or COLORS.cardBgHover}, 0.15) end)
    card.MouseLeave:Connect(function() Tween(card, {BackgroundColor3 = isListed and Color3.fromRGB(35, 35, 28) or COLORS.cardBg}, 0.15) end)

    -- Icon
    local RankLabel = Instance.new("TextLabel")
    RankLabel.Size = UDim2.new(0, 28, 0, 28); RankLabel.Position = UDim2.new(0, 8, 0.5, -14)
    RankLabel.BackgroundColor3 = tierColors[data.ItemTier] or COLORS.bgSecondary; RankLabel.BackgroundTransparency = 0.4
    RankLabel.Text = isListed and "🏪" or "📦"; RankLabel.TextSize = 14
    RankLabel.TextColor3 = Color3.new(1,1,1); RankLabel.Font = Enum.Font.GothamBold; RankLabel.Parent = card
    Instance.new("UICorner", RankLabel).CornerRadius = UDim.new(0, 6)

    -- Name
    local NameLabel = Instance.new("TextLabel")
    NameLabel.Size = UDim2.new(0, 180, 0, 16); NameLabel.Position = UDim2.new(0, 42, 0, 6)
    NameLabel.BackgroundTransparency = 1; NameLabel.Text = data.ItemName or "Unknown"
    NameLabel.TextColor3 = tierColors[data.ItemTier] or COLORS.text
    NameLabel.TextXAlignment = Enum.TextXAlignment.Left
    NameLabel.Font = Enum.Font.GothamBold; NameLabel.TextSize = 12
    NameLabel.TextTruncate = Enum.TextTruncate.AtEnd; NameLabel.Parent = card

    -- Listed badge
    if isListed then
        local Badge = Instance.new("TextLabel")
        Badge.Size = UDim2.new(0, 42, 0, 12); Badge.Position = UDim2.new(0, 226, 0, 8)
        Badge.BackgroundColor3 = COLORS.orange; Badge.BackgroundTransparency = 0.3
        Badge.Text = "LISTED"; Badge.TextSize = 7; Badge.TextColor3 = Color3.new(1,1,1)
        Badge.Font = Enum.Font.GothamBold; Badge.Parent = card
        Instance.new("UICorner", Badge).CornerRadius = UDim.new(0, 3)
    end

    -- Info line
    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Size = UDim2.new(0, 220, 0, 12); InfoLabel.Position = UDim2.new(0, 42, 0, 23)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Text = (tierNames[data.ItemTier] or "?") .. " • " .. (data.ItemType or "?")
    InfoLabel.TextColor3 = COLORS.textDim; InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.Font = Enum.Font.Gotham; InfoLabel.TextSize = 9; InfoLabel.Parent = card

    -- RAP/ALP
    local rapAlpParts = {}
    if data.RAP and data.RAP > 0 then
        table.insert(rapAlpParts, "RAP: " .. FormatCompact(data.RAP))
    else table.insert(rapAlpParts, "RAP: -") end
    if data.ALP and data.ALP.avg and data.ALP.avg > 0 then
        table.insert(rapAlpParts, string.format("ALP: %s", FormatCompact(data.ALP.avg)))
    end

    local RapAlpLabel = Instance.new("TextLabel")
    RapAlpLabel.Size = UDim2.new(0, 220, 0, 12); RapAlpLabel.Position = UDim2.new(0, 42, 0, 40)
    RapAlpLabel.BackgroundTransparency = 1; RapAlpLabel.Text = table.concat(rapAlpParts, " │ ")
    RapAlpLabel.TextColor3 = COLORS.textMuted; RapAlpLabel.TextXAlignment = Enum.TextXAlignment.Left
    RapAlpLabel.Font = Enum.Font.Gotham; RapAlpLabel.TextSize = 9; RapAlpLabel.Parent = card

    -- Quick price presets
    local suggestedPrice = 1
    local pctVal = tonumber(PricePctBox.Text) or DEFAULT_PRICE_PCT
    local rapVal = data.RAP or 0
    local alpVal = (data.ALP and data.ALP.avg) or 0
    if rapVal > 0 then suggestedPrice = math.floor(rapVal * pctVal / 100)
    elseif alpVal > 0 then suggestedPrice = math.floor(alpVal * pctVal / 100) end
    if suggestedPrice < 1 then suggestedPrice = 1 end

    -- Price input
    local PriceInput = Instance.new("TextBox")
    PriceInput.Size = UDim2.new(0, 65, 0, 24); PriceInput.Position = UDim2.new(1, -280, 0, 5)
    PriceInput.BackgroundColor3 = COLORS.inputBg; PriceInput.Text = tostring(suggestedPrice)
    PriceInput.PlaceholderText = "Harga"; PriceInput.PlaceholderColor3 = COLORS.textMuted
    PriceInput.TextColor3 = COLORS.gold; PriceInput.Font = Enum.Font.GothamSemibold
    PriceInput.TextSize = 11; PriceInput.ClearTextOnFocus = true; PriceInput.BorderSizePixel = 0
    PriceInput.Parent = card
    Instance.new("UICorner", PriceInput).CornerRadius = UDim.new(0, 4)

    local TokenSuffix = Instance.new("TextLabel")
    TokenSuffix.Size = UDim2.new(0, 14, 0, 24); TokenSuffix.Position = UDim2.new(1, -213, 0, 5)
    TokenSuffix.BackgroundTransparency = 1; TokenSuffix.Text = "T"
    TokenSuffix.TextColor3 = COLORS.textDim; TokenSuffix.Font = Enum.Font.GothamBold
    TokenSuffix.TextSize = 10; TokenSuffix.Parent = card

    -- Quick price preset buttons
    local presetX = 0
    local presets = {}
    if rapVal > 0 then
        table.insert(presets, {label = "RAP", val = rapVal})
        table.insert(presets, {label = "90%", val = math.floor(rapVal * 0.9)})
        table.insert(presets, {label = "80%", val = math.floor(rapVal * 0.8)})
    end
    if alpVal > 0 then
        table.insert(presets, {label = "ALP", val = math.floor(alpVal)})
    end

    for pi, preset in ipairs(presets) do
        if pi > 4 then break end
        local pbtn = Instance.new("TextButton")
        pbtn.Size = UDim2.new(0, 28, 0, 14); pbtn.Position = UDim2.new(1, -280 + presetX, 0, 34)
        pbtn.BackgroundColor3 = COLORS.searchBg; pbtn.Text = preset.label
        pbtn.Font = Enum.Font.GothamSemibold; pbtn.TextSize = 7; pbtn.TextColor3 = COLORS.textDim
        pbtn.AutoButtonColor = false; pbtn.BorderSizePixel = 0; pbtn.Parent = card
        Instance.new("UICorner", pbtn).CornerRadius = UDim.new(0, 4)
        local pval = preset.val
        pbtn.MouseEnter:Connect(function() Tween(pbtn, {BackgroundColor3 = COLORS.accent, TextColor3 = Color3.new(1,1,1)}, 0.1) end)
        pbtn.MouseLeave:Connect(function() Tween(pbtn, {BackgroundColor3 = COLORS.searchBg, TextColor3 = COLORS.textDim}, 0.1) end)
        pbtn.MouseButton1Click:Connect(function()
            PriceInput.Text = tostring(math.max(1, pval))
        end)
        presetX = presetX + 31
    end

    -- List button
    local ListBtn = Instance.new("TextButton")
    ListBtn.Size = UDim2.new(0, 75, 0, 30); ListBtn.Position = UDim2.new(1, -125, 0.5, -15)
    ListBtn.BackgroundColor3 = isListed and COLORS.textMuted or COLORS.green
    ListBtn.Text = isListed and "✅ Listed" or "💰 List"
    ListBtn.Font = Enum.Font.GothamBold; ListBtn.TextSize = 11; ListBtn.TextColor3 = Color3.new(1,1,1)
    ListBtn.AutoButtonColor = false; ListBtn.BorderSizePixel = 0; ListBtn.Parent = card
    Instance.new("UICorner", ListBtn).CornerRadius = UDim.new(0, 6)

    if not isListed then
        ListBtn.MouseEnter:Connect(function() Tween(ListBtn, {BackgroundColor3 = COLORS.greenHover}, 0.15) end)
        ListBtn.MouseLeave:Connect(function() Tween(ListBtn, {BackgroundColor3 = COLORS.green}, 0.15) end)
    end

    ListBtn.MouseButton1Click:Connect(function()
        if isDialogOpen then return end
        if isListed then StatusText.Text = "ℹ️ Item sudah di-list! Gunakan tab Booth untuk manage."; return end
        local price = tonumber(PriceInput.Text)
        if not price or price <= 0 then StatusText.Text = "❌ Harga tidak valid!"; return end

        ShowConfirmDialog(
            "💰 List Item",
            string.format("List %s ke booth seharga %s T?", data.ItemName or "item", FormatNumber(price)),
            function()
                ListBtn.Text = "⏳..."; ListBtn.BackgroundColor3 = Color3.fromRGB(180, 150, 0)
                StatusText.Text = "💰 Listing " .. (data.ItemName or "item") .. "..."
                task.spawn(function()
                    local ok, result = pcall(function()
                        return TradeData.Remotes.CreateSaleListing:InvokeServer("Booth", data.ItemType, data.UUID, price)
                    end)
                    if ok then
                        ListBtn.Text = "✅ Listed"; ListBtn.BackgroundColor3 = COLORS.textMuted
                        StatusText.Text = "✅ " .. (data.ItemName or "item") .. " di-list seharga " .. FormatNumber(price) .. " T"
                        data.IsListed = true; isListed = true
                        card.BackgroundColor3 = Color3.fromRGB(35, 35, 28); RankLabel.Text = "🏪"
                        UpdateTokenDisplay()
                    else
                        ListBtn.Text = "❌ Gagal"; ListBtn.BackgroundColor3 = COLORS.red
                        StatusText.Text = "❌ Gagal list: " .. tostring(result)
                        task.wait(2); ListBtn.Text = "💰 List"; ListBtn.BackgroundColor3 = COLORS.green
                    end
                end)
            end
        )
    end)

    -- Store reference for batch listing
    card:SetAttribute("ItemUUID", data.UUID or "")
    card:SetAttribute("IsListed", isListed)

    -- Entry animation
    card.Position = UDim2.new(0.3, 0, 0, 0); card.BackgroundTransparency = 0.5
    Tween(card, {Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0}, 0.3 + layoutOrder * 0.02)
    return card
end

-- ==========================
-- TAB SWITCHING
-- ==========================
local function SetTabActive(tab)
    if tab == "booth" then
        TabBooth.BackgroundColor3 = COLORS.tabActive; TabBooth.TextColor3 = Color3.new(1,1,1)
        TabInventory.BackgroundColor3 = COLORS.tabInactive; TabInventory.TextColor3 = COLORS.textDim
        ClearBoothBtn.Visible = true; BatchListBtn.Visible = false
        PricePctLabel.Visible = false; PricePctBox.Visible = false; PricePctSuffix.Visible = false
        CategoryBar.Visible = false
        Scroll.Position = UDim2.new(0, 10, 0, SCROLL_Y_BOOTH)
        Scroll.Size = UDim2.new(1, -20, 1, -160)
    else
        TabInventory.BackgroundColor3 = COLORS.tabActive; TabInventory.TextColor3 = Color3.new(1,1,1)
        TabBooth.BackgroundColor3 = COLORS.tabInactive; TabBooth.TextColor3 = COLORS.textDim
        ClearBoothBtn.Visible = false; BatchListBtn.Visible = true
        PricePctLabel.Visible = true; PricePctBox.Visible = true; PricePctSuffix.Visible = true
        CategoryBar.Visible = true
        Scroll.Position = UDim2.new(0, 10, 0, SCROLL_Y_INV)
        Scroll.Size = UDim2.new(1, -20, 1, -160 - CATEGORY_BAR_HEIGHT - 4)
    end
    currentTab = tab
end

-- ==========================
-- LOAD BOOTH LISTINGS
-- ==========================
LoadBoothListings = function()
    if isLoading then return end
    if not requireOK then StatusText.Text = "⚠️ Modules tidak tersedia"; return end
    isLoading = true
    ClearScroll(); ShowLoading(true, "⏳ Memuat booth listings...")
    StatusText.Text = "🔄 Memuat booth..."

    task.spawn(function()
        local success, err = pcall(function()
            local boothListings = GetMyBoothListings()
            if not boothListings or not next(boothListings) then
                ShowLoading(false)
                ShowEmpty("📭 Booth kamu kosong! Buka tab Inventory untuk list item.")
                StatusText.Text = "✅ Booth kosong"
                StatsText.Text = "0 listings"
                SlotCounter.Text = "Slot: 0/" .. MAX_BOOTH_SLOTS
                SlotCounter.TextColor3 = COLORS.green
                isLoading = false; return
            end

            local entries = {}
            local itemDefCache = {}
            for listingKey, listingData in pairs(boothListings) do
                if not listingData.Item then continue end
                local cacheKey = tostring(listingData.ItemType or "") .. "_" .. tostring(listingData.Item.Id or "")
                local itemDef = itemDefCache[cacheKey]
                if itemDef == nil then
                    local defOk, defVal = pcall(function() return ItemUtility.GetItemDataFromItemType(listingData.ItemType, listingData.Item.Id) end)
                    itemDef = defOk and defVal or false; itemDefCache[cacheKey] = itemDef
                end
                if itemDef == false then itemDef = nil end
                local itemName = itemDef and itemDef.Data and itemDef.Data.Name or tostring(listingData.Item.Id)
                local itemTier = itemDef and itemDef.Data and itemDef.Data.Tier or 0
                local itemIdStr = itemDef and itemDef.Data and tostring(itemDef.Data.Id) or tostring(listingData.Item.Id)
                table.insert(entries, {
                    ListingKey = listingKey, ItemName = itemName, ItemType = listingData.ItemType,
                    ItemTier = itemTier, ItemIdStr = itemIdStr, Price = listingData.Price or 0,
                    UUID = listingData.Item.UUID, RAP = nil, ALP = nil,
                })
            end

            -- Update slot counter
            local slotCount = #entries
            SlotCounter.Text = "Slot: " .. slotCount .. "/" .. MAX_BOOTH_SLOTS
            SlotCounter.TextColor3 = slotCount >= MAX_BOOTH_SLOTS and COLORS.red or (slotCount >= MAX_BOOTH_SLOTS - 2 and COLORS.orange or COLORS.green)

            StatusText.Text = string.format("📊 %d listings. Fetching RAP/ALP...", #entries)
            local done, total = 0, #entries
            for i, entry in ipairs(entries) do
                local idx = i
                task.spawn(function()
                    entries[idx].RAP = FetchRAPFromServer(entry.ItemType, entry.ItemIdStr) or 0
                    entries[idx].ALP = GetAvgPrice(entry.ItemType, entry.ItemIdStr)
                    done = done + 1
                end)
            end
            local t0 = tick()
            while done < total and (tick() - t0) < 8 do task.wait(0.05) end

            -- Sort
            SortEntries(entries)

            boothEntries = entries; ShowLoading(false); ClearScroll()
            if #entries == 0 then ShowEmpty("📭 Booth kosong!")
            else for i, entry in ipairs(entries) do CreateBoothCard(entry, i) end end

            task.wait(0.05)
            Scroll.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 10)
            local totalValue = 0
            for _, e in ipairs(entries) do totalValue = totalValue + (e.Price or 0) end
            StatusText.Text = string.format("✅ %d listings loaded", #entries)
            StatsText.Text = string.format("%d items • Total: %sT", #entries, FormatCompact(totalValue))
        end)

        if not success then
            ShowLoading(false); ShowEmpty("⚠️ Error: " .. tostring(err))
            StatusText.Text = "❌ Error: " .. tostring(err):sub(1, 50)
        end
        isLoading = false
    end)
end

-- ==========================
-- FILTER & DISPLAY INVENTORY (lightweight, from cache)
-- ==========================
FilterAndDisplayInventory = function()
    if #allItemsCache == 0 then
        -- No cache yet, do a full load
        if LoadInventory then LoadInventory() end
        return
    end

    ClearScroll()
    local searchQuery = SearchBox.Text:lower()
    local entries = {}

    for _, item in ipairs(allItemsCache) do
        if currentCategory and item.ItemType ~= currentCategory then continue end
        if searchQuery ~= "" then
            local nm = item.ItemName:lower():find(searchQuery, 1, true)
            local tp = item.ItemType:lower():find(searchQuery, 1, true)
            local tr = (tierNames[item.ItemTier] or ""):lower():find(searchQuery, 1, true)
            if not (nm or tp or tr) then continue end
        end
        table.insert(entries, item)
    end

    -- Sort (listed first, then by currentSort)
    local listedEntries, unlistedEntries = {}, {}
    for _, e in ipairs(entries) do
        if e.IsListed then table.insert(listedEntries, e) else table.insert(unlistedEntries, e) end
    end
    SortEntries(listedEntries); SortEntries(unlistedEntries)
    entries = {}
    for _, e in ipairs(listedEntries) do table.insert(entries, e) end
    for _, e in ipairs(unlistedEntries) do table.insert(entries, e) end

    inventoryEntries = entries
    if #entries == 0 then
        ShowEmpty("📭 Tidak ada item" .. (searchQuery ~= "" and (" untuk '" .. searchQuery .. "'") or "") .. (currentCategory and (" di " .. currentCategory) or "") .. ".")
    else
        for i, entry in ipairs(entries) do CreateInventoryCard(entry, i) end
    end

    task.wait(0.05)
    Scroll.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 10)
    local listedCount = 0
    for _, e in ipairs(entries) do if e.IsListed then listedCount = listedCount + 1 end end
    StatusText.Text = string.format("✅ %d items", #entries)
    StatsText.Text = string.format("%d items • %d listed", #entries, listedCount)
end

-- ==========================
-- LOAD INVENTORY (heavy, fetches from Replion + RAP/ALP)
-- ==========================
LoadInventory = function()
    if isLoading then return end
    if not requireOK then StatusText.Text = "⚠️ Modules tidak tersedia"; return end
    isLoading = true
    ClearScroll(); ShowLoading(true, "⏳ Memuat inventory...")
    StatusText.Text = "🔄 Memuat inventory..."

    task.spawn(function()
        local success, err = pcall(function()
            local data = GetData()
            if not data then
                ShowLoading(false); ShowEmpty("⚠️ Gagal memuat Data Replion"); isLoading = false; return
            end

            local ok, inv = pcall(function() return data:GetExpect("Inventory") end)
            if not ok or not inv then inv = data:Get("Inventory") end
            if not inv then
                ShowLoading(false); ShowEmpty("⚠️ Gagal membaca inventory"); isLoading = false; return
            end

            local boothListings = GetMyBoothListings()
            local listedUUIDs = {}
            for _, listing in pairs(boothListings) do
                if listing.Item and listing.Item.UUID then listedUUIDs[listing.Item.UUID] = true end
            end

            local allItems = {}
            local categoryCounts = {}

            for cat, items in pairs(inv) do
                if type(items) == "table" then
                    for _, item in pairs(items) do
                        if type(item) == "table" and item.UUID then
                            local itemDef, name, itype, tier = nil, tostring(item.Id or "?"), cat, 0
                            local ok1, d1 = pcall(function() return ItemUtility.GetItemDataFromItemType(cat, item.Id) end)
                            if ok1 and d1 and d1.Data then
                                name = d1.Data.Name; itype = d1.Data.Type or cat; tier = d1.Data.Tier or 0; itemDef = d1
                            else
                                local ok2, d2 = pcall(function() return ItemUtility.GetItemDataFromItemType(item.Id) end)
                                if ok2 and d2 and d2.Data then
                                    name = d2.Data.Name; itype = d2.Data.Type or cat; tier = d2.Data.Tier or 0; itemDef = d2
                                end
                            end
                            local isListed = listedUUIDs[item.UUID] or false
                            local itemIdStr = itemDef and itemDef.Data and tostring(itemDef.Data.Id) or tostring(item.Id)
                            categoryCounts[itype] = (categoryCounts[itype] or 0) + 1
                            table.insert(allItems, {
                                UUID = item.UUID, ItemId = item.Id, ItemIdStr = itemIdStr,
                                ItemName = name, ItemType = itype, ItemTier = tier,
                                IsListed = isListed, RAP = nil, ALP = nil,
                            })
                        end
                    end
                end
            end

            -- Cache for fast filtering
            allItemsCache = allItems
            cachedCategoryCounts = categoryCounts
            BuildCategoryButtons(categoryCounts)

            -- Filter based on current category/search
            local searchQuery = SearchBox.Text:lower()
            local entries = {}
            for _, item in ipairs(allItems) do
                if currentCategory and item.ItemType ~= currentCategory then continue end
                if searchQuery ~= "" then
                    local nm = item.ItemName:lower():find(searchQuery, 1, true)
                    local tp = item.ItemType:lower():find(searchQuery, 1, true)
                    local tr = (tierNames[item.ItemTier] or ""):lower():find(searchQuery, 1, true)
                    if not (nm or tp or tr) then continue end
                end
                table.insert(entries, item)
            end

            StatusText.Text = string.format("📊 %d items. Fetching RAP/ALP...", #entries)
            -- Fetch RAP/ALP for ALL cached items (not just filtered), so switching category is instant
            local fetchLimit = math.min(#allItems, 80)
            local done = 0
            for i = 1, fetchLimit do
                local entry = allItems[i]; local idx = i
                task.spawn(function()
                    allItems[idx].RAP = FetchRAPFromServer(entry.ItemType, entry.ItemIdStr) or 0
                    allItems[idx].ALP = GetAvgPrice(entry.ItemType, entry.ItemIdStr)
                    done = done + 1
                end)
            end
            local t0 = tick()
            while done < fetchLimit and (tick() - t0) < 12 do task.wait(0.05) end

            -- Re-filter after RAP/ALP loaded (entries may reference same objects)
            entries = {}
            for _, item in ipairs(allItems) do
                if currentCategory and item.ItemType ~= currentCategory then continue end
                if searchQuery ~= "" then
                    local nm = item.ItemName:lower():find(searchQuery, 1, true)
                    local tp = item.ItemType:lower():find(searchQuery, 1, true)
                    local tr = (tierNames[item.ItemTier] or ""):lower():find(searchQuery, 1, true)
                    if not (nm or tp or tr) then continue end
                end
                table.insert(entries, item)
            end

            -- Sort (listed first, then by currentSort)
            local listedEntries, unlistedEntries = {}, {}
            for _, e in ipairs(entries) do
                if e.IsListed then table.insert(listedEntries, e) else table.insert(unlistedEntries, e) end
            end
            SortEntries(listedEntries); SortEntries(unlistedEntries)
            entries = {}
            for _, e in ipairs(listedEntries) do table.insert(entries, e) end
            for _, e in ipairs(unlistedEntries) do table.insert(entries, e) end

            inventoryEntries = entries; ShowLoading(false); ClearScroll()
            if #entries == 0 then
                ShowEmpty("📭 Tidak ada item" .. (searchQuery ~= "" and (" untuk '" .. searchQuery .. "'") or "") .. (currentCategory and (" di " .. currentCategory) or "") .. ".")
            else
                for i, entry in ipairs(entries) do CreateInventoryCard(entry, i) end
            end

            task.wait(0.05)
            Scroll.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 10)
            local listedCount = 0
            for _, e in ipairs(entries) do if e.IsListed then listedCount = listedCount + 1 end end
            StatusText.Text = string.format("✅ %d items loaded", #entries)
            StatsText.Text = string.format("%d items • %d listed", #entries, listedCount)
        end)

        if not success then
            ShowLoading(false); ShowEmpty("⚠️ Error: " .. tostring(err))
            StatusText.Text = "❌ Error: " .. tostring(err):sub(1, 50)
        end
        isLoading = false
    end)
end

-- ==========================
-- BATCH LIST ALL
-- ==========================
BatchListBtn.MouseButton1Click:Connect(function()
    if isLoading or isDialogOpen then return end

    -- Count unlisted items visible
    local unlistedCount = 0
    for _, e in ipairs(inventoryEntries) do
        if not e.IsListed then unlistedCount = unlistedCount + 1 end
    end

    if unlistedCount == 0 then
        StatusText.Text = "ℹ️ Tidak ada item unlisted untuk di-list."
        return
    end

    local pctVal = tonumber(PricePctBox.Text) or DEFAULT_PRICE_PCT

    ShowConfirmDialog(
        "📦 Batch List",
        string.format("List %d item yang belum di-list\ndengan harga %d%% RAP/ALP?\n\nDelay: %ds per item.", unlistedCount, pctVal, LISTING_COOLDOWN),
        function()
            isLoading = true
            BatchListBtn.Text = "⏳..."
            StatusText.Text = "📦 Batch listing..."

            task.spawn(function()
                local listed, failed = 0, 0
                for i, entry in ipairs(inventoryEntries) do
                    if entry.IsListed then continue end

                    local price = 1
                    local rapV = entry.RAP or 0
                    local alpV = (entry.ALP and entry.ALP.avg) or 0
                    if rapV > 0 then price = math.floor(rapV * pctVal / 100)
                    elseif alpV > 0 then price = math.floor(alpV * pctVal / 100) end
                    if price < 1 then price = 1 end

                    StatusText.Text = string.format("📦 Listing %d/%d: %s (%sT)...", listed + failed + 1, unlistedCount, entry.ItemName or "?", FormatCompact(price))

                    local ok = pcall(function()
                        return TradeData.Remotes.CreateSaleListing:InvokeServer("Booth", entry.ItemType, entry.UUID, price)
                    end)

                    if ok then
                        listed = listed + 1
                        entry.IsListed = true
                    else
                        failed = failed + 1
                    end

                    task.wait(LISTING_COOLDOWN)
                end

                StatusText.Text = string.format("✅ Batch done: %d listed, %d gagal", listed, failed)
                BatchListBtn.Text = "📦 List Semua"
                isLoading = false
                UpdateTokenDisplay()

                task.wait(1)
                LoadInventory()
            end)
        end
    )
end)

-- ==========================
-- CLEAR ALL BOOTH
-- ==========================
ClearBoothBtn.MouseButton1Click:Connect(function()
    if isLoading or isDialogOpen then return end

    ShowConfirmDialog(
        "🗑️ Clear All Booth",
        "Hapus SEMUA listing dari booth kamu?\nSemua item akan kembali ke inventory.",
        function()
            isLoading = true
            ClearBoothBtn.Text = "⏳..."
            StatusText.Text = "🗑️ Menghapus semua listing..."

            task.spawn(function()
                local ls = GetMyBoothListings()
                if not ls or not next(ls) then
                    StatusText.Text = "ℹ️ Booth sudah kosong"
                    ClearBoothBtn.Text = "🗑️ Clear"
                    isLoading = false; return
                end

                local keys = {}
                for k in pairs(ls) do table.insert(keys, k) end

                for i, k in ipairs(keys) do
                    StatusText.Text = string.format("🗑️ Menghapus %d/%d...", i, #keys)
                    local ok, e = pcall(function() return TradeData.Remotes.DeleteSaleListing:InvokeServer("Booth", k) end)
                    if not ok then warn("[SellerUI] Delete error:", e) end
                    if i < #keys then task.wait(LISTING_COOLDOWN) end
                end

                StatusText.Text = string.format("✅ %d listing dihapus!", #keys)
                ClearBoothBtn.Text = "🗑️ Clear"
                isLoading = false
                UpdateTokenDisplay()

                task.wait(1)
                LoadBoothListings()
            end)
        end
    )
end)

-- ==========================
-- TAB CLICK HANDLERS
-- ==========================
TabBooth.MouseButton1Click:Connect(function()
    if currentTab == "booth" then return end
    SetTabActive("booth"); LoadBoothListings()
end)

TabInventory.MouseButton1Click:Connect(function()
    if currentTab == "inventory" then return end
    SetTabActive("inventory"); LoadInventory()
end)

-- ==========================
-- REFRESH
-- ==========================
RefreshBtn.MouseButton1Click:Connect(function()
    rapCache = {}; alpCache = {}; lastCategories = nil; allItemsCache = {}
    UpdateTokenDisplay()
    if currentTab == "booth" then LoadBoothListings() else LoadInventory() end
end)

-- ==========================
-- SEARCH DEBOUNCE
-- ==========================
local searchDebounce = nil
SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    if currentTab ~= "inventory" then return end
    if searchDebounce then task.cancel(searchDebounce) end
    searchDebounce = task.delay(0.3, function()
        FilterAndDisplayInventory(); searchDebounce = nil
    end)
end)

-- ==========================
-- KEYBOARD SHORTCUTS
-- ==========================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if isDialogOpen then return end

    if input.KeyCode == Enum.KeyCode.Escape then
        if not isMinimized and MainFrame.Visible then
            MinimizeToWindow()
        end
    elseif input.KeyCode == Enum.KeyCode.R then
        -- Only refresh if not typing in a TextBox
        local focused = UserInputService:GetFocusedTextBox()
        if not focused then
            rapCache = {}; alpCache = {}; lastCategories = nil; allItemsCache = {}
            UpdateTokenDisplay()
            if currentTab == "booth" then LoadBoothListings() else LoadInventory() end
        end
    end
end)

-- ==========================
-- INITIAL LOAD
-- ==========================
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.BackgroundTransparency = 1
Tween(MainFrame, {Size = UDim2.new(0, 640, 0, 580), BackgroundTransparency = 0}, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
task.wait(0.5)

SetTabActive("booth")
LoadBoothListings()
UpdateTokenDisplay()

print("[SellerUI] Plaza Booth Seller Manager v2.0 loaded! 💰")
print("[SellerUI] Shortcuts: Esc=Minimize, R=Refresh")
 
