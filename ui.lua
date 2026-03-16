-- ============================================================
-- fishit_ui.lua  —  UI MODULE
-- Sidebar style, draggable, minimize ke bubble, resize handle
-- Tab: Settings / Focus / Config
-- Di-host di GitHub dan di-load oleh fishit_main.lua via loadstring
-- ============================================================
-- Wajib return function buildUI(ctx) agar bisa dipanggil dari main
-- ctx = {
--   localPlayer, Players, MIN_TIER, ANTI_AFK_ENABLED,
--   AFK_NOTIFY_ENABLED, AFK_CHECK_INTERVAL, AFK_TIMEOUT,
--   DC_NOTIFY_ENABLED, DC_REJOIN_TIMEOUT, COOLDOWN,
--   FOCUS_FISH, CRYSTALIZED_FISH, startAntiAfk,
--   setMinTier, setCooldown, setAfkCheck, setAfkTimeout, setDcTimeout,
--   setAntiAfk, setAfkNotify, setDcNotify,
-- }

local function buildUI(ctx)
    local cg    = game:GetService("CoreGui")
    local UIS   = game:GetService("UserInputService")
    local TweenS = game:GetService("TweenService")

    local localPlayer       = ctx.localPlayer
    local Players           = ctx.Players
    local FOCUS_FISH        = ctx.FOCUS_FISH
    local CRYSTALIZED_FISH  = ctx.CRYSTALIZED_FISH

    if cg:FindFirstChild("FishItUI") then cg.FishItUI:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "FishItUI"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 9999
    sg.IgnoreGuiInset = true
    pcall(function()
        if gethui then sg.Parent = gethui()
        elseif syn and syn.protect_gui then syn.protect_gui(sg); sg.Parent = cg
        else sg.Parent = cg end
    end)
    if not sg.Parent then sg.Parent = cg end

    -- ── Ukuran & posisi (bottom-right) ──────────────────────
    local W, H   = 400, 280
    local PADDING = 12

    -- Bubble (icon minimal, bottom-right)
    local bubble = Instance.new("TextButton")
    bubble.Name = "Bubble"
    bubble.Size = UDim2.new(0, 48, 0, 48)
    bubble.Position = UDim2.new(1, -(48 + PADDING), 1, -(48 + PADDING))
    bubble.BackgroundColor3 = Color3.fromRGB(10, 90, 190)
    bubble.BorderSizePixel = 0
    bubble.Text = "F"
    bubble.TextSize = 20
    bubble.Font = Enum.Font.GothamBold
    bubble.TextColor3 = Color3.new(1, 1, 1)
    bubble.Visible = false
    bubble.ZIndex = 10
    bubble.Parent = sg
    Instance.new("UICorner", bubble).CornerRadius = UDim.new(1, 0)

    -- ── Panel utama ─────────────────────────────────────────
    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.new(0, W, 0, H)
    panel.Position = UDim2.new(1, -(W + PADDING), 1, -(H + PADDING))
    panel.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Parent = sg
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
    local panelStroke = Instance.new("UIStroke", panel)
    panelStroke.Color = Color3.fromRGB(255, 255, 255)
    panelStroke.Transparency = 0.85
    panelStroke.Thickness = 1

    -- ── Title bar ───────────────────────────────────────────
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = Color3.fromRGB(10, 90, 190)
    titleBar.BorderSizePixel = 0
    titleBar.ZIndex = 3
    titleBar.Parent = panel
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -80, 1, 0)
    titleLbl.Position = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "FishIt Notifier v6"
    titleLbl.TextColor3 = Color3.new(1, 1, 1)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.ZIndex = 4
    titleLbl.Parent = titleBar

    -- Tombol title bar (close / minimize)
    local function makeTitleBtn(icon, xOff, color, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 26, 0, 26)
        btn.Position = UDim2.new(1, xOff, 0.5, -13)
        btn.BackgroundColor3 = color
        btn.BorderSizePixel = 0
        btn.Text = icon
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 13
        btn.ZIndex = 5
        btn.Parent = titleBar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    makeTitleBtn("X",   -34, Color3.fromRGB(200, 50, 50),  function() sg:Destroy() end)
    makeTitleBtn("[ ]", -68, Color3.fromRGB(60, 130, 220), function()
        panel.Visible = false
        bubble.Visible = true
    end)

    -- Bubble: tap = restore, drag = pindah posisi
    do
        local bdrag, bdragStart, bstartPos = false, nil, nil
        local bdragged = false
        local function isPress(t)
            return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
        end
        local function isMove(t)
            return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
        end
        bubble.InputBegan:Connect(function(inp)
            if isPress(inp.UserInputType) then
                bdrag = true; bdragged = false
                bdragStart = inp.Position; bstartPos = bubble.Position
            end
        end)
        UIS.InputChanged:Connect(function(inp)
            if bdrag and isMove(inp.UserInputType) then
                local delta = inp.Position - bdragStart
                if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 then
                    bdragged = true
                    bubble.Position = UDim2.new(
                        bstartPos.X.Scale, bstartPos.X.Offset + delta.X,
                        bstartPos.Y.Scale, bstartPos.Y.Offset + delta.Y
                    )
                end
            end
        end)
        UIS.InputEnded:Connect(function(inp)
            if isPress(inp.UserInputType) and bdrag then
                bdrag = false
                if not bdragged then
                    bubble.Visible = false
                    panel.Visible = true
                end
            end
        end)
    end

    -- Drag titleBar
    do
        local dragging, dragStart, startPos = false, nil, nil
        local function isPress(t)
            return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
        end
        local function isMove(t)
            return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
        end
        titleBar.InputBegan:Connect(function(inp)
            if isPress(inp.UserInputType) then
                dragging = true; dragStart = inp.Position; startPos = panel.Position
            end
        end)
        UIS.InputChanged:Connect(function(inp)
            if dragging and isMove(inp.UserInputType) then
                local delta = inp.Position - dragStart
                panel.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)
        UIS.InputEnded:Connect(function(inp)
            if isPress(inp.UserInputType) then dragging = false end
        end)
    end

    -- Resize handle (pojok kanan bawah)
    local resizeHandle = Instance.new("TextButton")
    resizeHandle.Size = UDim2.new(0, 18, 0, 18)
    resizeHandle.Position = UDim2.new(1, -18, 1, -18)
    resizeHandle.BackgroundColor3 = Color3.fromRGB(80, 130, 220)
    resizeHandle.BorderSizePixel = 0
    resizeHandle.Text = ""
    resizeHandle.ZIndex = 6
    resizeHandle.Parent = panel
    Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 3)
    do
        local resizing, resizeStart, startSize = false, nil, nil
        local function isPress(t)
            return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
        end
        local function isMove(t)
            return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
        end
        resizeHandle.InputBegan:Connect(function(inp)
            if isPress(inp.UserInputType) then
                resizing = true; resizeStart = inp.Position; startSize = panel.AbsoluteSize
            end
        end)
        UIS.InputChanged:Connect(function(inp)
            if resizing and isMove(inp.UserInputType) then
                local delta = inp.Position - resizeStart
                local nw = math.max(320, startSize.X + delta.X)
                local nh = math.max(200, startSize.Y + delta.Y)
                panel.Size = UDim2.new(0, nw, 0, nh)
            end
        end)
        UIS.InputEnded:Connect(function(inp)
            if isPress(inp.UserInputType) then resizing = false end
        end)
    end

    -- ── Layout: Sidebar + Content ────────────────────────────
    local SIDEBAR_W = 90

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -36)
    sidebar.Position = UDim2.new(0, 0, 0, 36)
    sidebar.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
    sidebar.BorderSizePixel = 0
    sidebar.ZIndex = 2
    sidebar.Parent = panel

    local sideLayout = Instance.new("UIListLayout", sidebar)
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sideLayout.Padding = UDim.new(0, 2)
    local sidePad = Instance.new("UIPadding", sidebar)
    sidePad.PaddingTop = UDim.new(0, 8)
    sidePad.PaddingLeft = UDim.new(0, 6)
    sidePad.PaddingRight = UDim.new(0, 6)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -SIDEBAR_W, 1, -36)
    content.Position = UDim2.new(0, SIDEBAR_W, 0, 36)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = true
    content.Parent = panel

    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(0, 1, 1, -36)
    sep.Position = UDim2.new(0, SIDEBAR_W, 0, 36)
    sep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    sep.BackgroundTransparency = 0.85
    sep.BorderSizePixel = 0
    sep.Parent = panel

    -- ── Tab system ───────────────────────────────────────────
    local TABS = { "Settings", "Focus", "Config" }
    local tabFrames = {}
    local tabBtns   = {}
    local activeTab = nil

    local function switchTab(name)
        activeTab = name
        for n, f in pairs(tabFrames) do f.Visible = (n == name) end
        for n, b in pairs(tabBtns) do
            local on = (n == name)
            b.BackgroundTransparency = on and 0.7 or 1
            b.TextColor3 = on and Color3.fromRGB(80, 180, 255)
                or Color3.fromRGB(160, 160, 160)
        end
    end

    for i, name in ipairs(TABS) do
        local btn = Instance.new("TextButton")
        btn.LayoutOrder = i
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
        btn.BackgroundTransparency = 1
        btn.BorderSizePixel = 0
        btn.Text = name
        btn.TextColor3 = Color3.fromRGB(160, 160, 160)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.ZIndex = 3
        btn.Parent = sidebar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        tabBtns[name] = btn

        local page = Instance.new("ScrollingFrame")
        page.Name = name
        page.Size = UDim2.new(1, -8, 1, -8)
        page.Position = UDim2.new(0, 4, 0, 4)
        page.BackgroundTransparency = 1
        page.Visible = false
        page.ScrollBarThickness = 3
        page.ScrollBarImageColor3 = Color3.fromRGB(80, 180, 255)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.Parent = content
        tabFrames[name] = page

        local pageLayout = Instance.new("UIListLayout", page)
        pageLayout.Padding = UDim.new(0, 6)
        pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
        local pagePad = Instance.new("UIPadding", page)
        pagePad.PaddingTop = UDim.new(0, 4)
        pagePad.PaddingLeft = UDim.new(0, 2)
        pagePad.PaddingRight = UDim.new(0, 2)

        btn.MouseButton1Click:Connect(function() switchTab(name) end)
    end

    -- ── Helper: Section label ────────────────────────────────
    local function addSection(page, text)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 18)
        lbl.BackgroundTransparency = 1
        lbl.Text = text:upper()
        lbl.TextColor3 = Color3.fromRGB(80, 180, 255)
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = page
    end

    -- ── Helper: Toggle row ───────────────────────────────────
    local function addToggle(page, label, initVal, onChange)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(32, 32, 46)
        row.BorderSizePixel = 0
        row.Parent = page
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.7, 0, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local toggle = Instance.new("TextButton")
        toggle.Size = UDim2.new(0, 44, 0, 20)
        toggle.Position = UDim2.new(1, -50, 0.5, -10)
        toggle.BorderSizePixel = 0
        toggle.Font = Enum.Font.GothamBold
        toggle.TextSize = 9
        toggle.TextColor3 = Color3.new(1, 1, 1)
        toggle.AutoButtonColor = false
        toggle.Parent = row
        Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)

        local state = initVal
        local function refresh()
            toggle.Text = state and "ON" or "OFF"
            toggle.BackgroundColor3 = state
                and Color3.fromRGB(40, 180, 80)
                or  Color3.fromRGB(160, 50, 50)
        end
        refresh()
        toggle.MouseButton1Click:Connect(function()
            state = not state; refresh(); onChange(state)
        end)
    end

    -- ── TAB: Settings ────────────────────────────────────────
    local pg = tabFrames["Settings"]
    addSection(pg, "Features")
    addToggle(pg, "Anti-AFK", ctx.ANTI_AFK_ENABLED, function(v)
        ctx.setAntiAfk(v)
    end)
    addToggle(pg, "AFK Notify", ctx.AFK_NOTIFY_ENABLED, function(v)
        ctx.setAfkNotify(v)
    end)
    addToggle(pg, "DC Notify", ctx.DC_NOTIFY_ENABLED, function(v)
        ctx.setDcNotify(v)
    end)
    addSection(pg, "Status")
    local function sLbl(parent, text, color)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 16); l.BackgroundTransparency = 1
        l.Text = text; l.TextColor3 = color or Color3.fromRGB(200, 200, 200)
        l.Font = Enum.Font.Gotham; l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = parent
    end
    sLbl(pg, "● Player: " .. localPlayer.Name,          Color3.fromRGB(200, 200, 200))
    sLbl(pg, "● Chat hook: aktif ✓",                    Color3.fromRGB(100, 200, 100))
    sLbl(pg, "● MIN_TIER: " .. ctx.MIN_TIER,            Color3.fromRGB(150, 200, 255))
    sLbl(pg, "● Server: " .. #Players:GetPlayers() .. " player", Color3.fromRGB(200, 180, 100))

    -- ── TAB: Focus Fish ──────────────────────────────────────
    local pg2 = tabFrames["Focus"]
    addSection(pg2, "Focus Fish (selalu notif)")

    local focusList = Instance.new("Frame")
    focusList.Name = "FocusList"; focusList.Size = UDim2.new(1, 0, 0, 0)
    focusList.AutomaticSize = Enum.AutomaticSize.Y; focusList.BackgroundTransparency = 1
    focusList.Parent = pg2
    local flLayout = Instance.new("UIListLayout", focusList); flLayout.Padding = UDim.new(0, 3)

    local function refreshFocusList()
        for _, c in ipairs(focusList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
        for fishName in pairs(FOCUS_FISH) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 26); row.BackgroundColor3 = Color3.fromRGB(32, 32, 46)
            row.BorderSizePixel = 0; row.Parent = focusList
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
            local nl = Instance.new("TextLabel"); nl.Size = UDim2.new(1, -30, 1, 0)
            nl.Position = UDim2.new(0, 8, 0, 0); nl.BackgroundTransparency = 1
            nl.Text = fishName; nl.TextColor3 = Color3.fromRGB(220, 220, 220)
            nl.Font = Enum.Font.Gotham; nl.TextSize = 11
            nl.TextXAlignment = Enum.TextXAlignment.Left; nl.Parent = row
            local db = Instance.new("TextButton"); db.Size = UDim2.new(0, 22, 0, 22)
            db.Position = UDim2.new(1, -25, 0.5, -11); db.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
            db.BorderSizePixel = 0; db.Text = "X"; db.TextColor3 = Color3.new(1, 1, 1)
            db.Font = Enum.Font.GothamBold; db.TextSize = 10; db.Parent = row
            Instance.new("UICorner", db).CornerRadius = UDim.new(0, 4)
            db.MouseButton1Click:Connect(function()
                FOCUS_FISH[fishName] = nil; refreshFocusList()
            end)
        end
    end
    refreshFocusList()

    addSection(pg2, "Tambah Manual")
    local iRow = Instance.new("Frame"); iRow.Size = UDim2.new(1, 0, 0, 30)
    iRow.BackgroundTransparency = 1; iRow.Parent = pg2
    local il = Instance.new("UIListLayout", iRow)
    il.FillDirection = Enum.FillDirection.Horizontal; il.Padding = UDim.new(0, 4)

    local fishInput = Instance.new("TextBox"); fishInput.Size = UDim2.new(0.72, 0, 1, 0)
    fishInput.BackgroundColor3 = Color3.fromRGB(32, 32, 46); fishInput.BorderSizePixel = 0
    fishInput.Text = ""; fishInput.PlaceholderText = "nama ikan..."
    fishInput.TextColor3 = Color3.fromRGB(220, 220, 220); fishInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    fishInput.Font = Enum.Font.Gotham; fishInput.TextSize = 11; fishInput.ClearTextOnFocus = false
    fishInput.Parent = iRow
    Instance.new("UICorner", fishInput).CornerRadius = UDim.new(0, 5)

    local addBtn = Instance.new("TextButton"); addBtn.Size = UDim2.new(0.25, 0, 1, 0)
    addBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80); addBtn.BorderSizePixel = 0
    addBtn.Text = "+ Add"; addBtn.TextColor3 = Color3.new(1, 1, 1)
    addBtn.Font = Enum.Font.GothamBold; addBtn.TextSize = 11; addBtn.Parent = iRow
    Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 5)
    addBtn.MouseButton1Click:Connect(function()
        local name = fishInput.Text:match("^%s*(.-)%s*$")
        if name and name ~= "" then
            FOCUS_FISH[name] = true; fishInput.Text = ""
            refreshFocusList(); print("[FishIt] FOCUS_FISH tambah: " .. name)
        end
    end)

    -- ── TAB: Config (EDITABLE) ───────────────────────────────
    local pg3 = tabFrames["Config"]
    addSection(pg3, "Edit Konfigurasi")

    local function cRowEdit(parent, label, initVal, unit, onApply)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(32, 32, 46)
        row.BorderSizePixel = 0; row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        local k = Instance.new("TextLabel")
        k.Size = UDim2.new(0.45, 0, 1, 0); k.Position = UDim2.new(0, 8, 0, 0)
        k.BackgroundTransparency = 1; k.Text = label
        k.TextColor3 = Color3.fromRGB(180, 180, 180)
        k.Font = Enum.Font.Gotham; k.TextSize = 11
        k.TextXAlignment = Enum.TextXAlignment.Left; k.Parent = row

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0.32, 0, 0, 24); box.Position = UDim2.new(0.45, 0, 0.5, -12)
        box.BackgroundColor3 = Color3.fromRGB(20, 20, 30); box.BorderSizePixel = 0
        box.Text = tostring(initVal); box.TextColor3 = Color3.fromRGB(80, 180, 255)
        box.Font = Enum.Font.GothamBold; box.TextSize = 11
        box.ClearTextOnFocus = false; box.Parent = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)

        local unitLbl = Instance.new("TextLabel")
        unitLbl.Size = UDim2.new(0.1, 0, 1, 0); unitLbl.Position = UDim2.new(0.77, 0, 0, 0)
        unitLbl.BackgroundTransparency = 1; unitLbl.Text = unit or ""
        unitLbl.TextColor3 = Color3.fromRGB(120, 120, 120)
        unitLbl.Font = Enum.Font.Gotham; unitLbl.TextSize = 10
        unitLbl.TextXAlignment = Enum.TextXAlignment.Left; unitLbl.Parent = row

        local applyBtn = Instance.new("TextButton")
        applyBtn.Size = UDim2.new(0, 36, 0, 24); applyBtn.Position = UDim2.new(1, -42, 0.5, -12)
        applyBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 70); applyBtn.BorderSizePixel = 0
        applyBtn.Text = "OK"; applyBtn.TextColor3 = Color3.new(1, 1, 1)
        applyBtn.Font = Enum.Font.GothamBold; applyBtn.TextSize = 10; applyBtn.Parent = row
        Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 4)

        local function tryApply()
            local n = tonumber(box.Text)
            if n and n > 0 then
                onApply(n)
                applyBtn.BackgroundColor3 = Color3.fromRGB(40, 200, 70)
                task.delay(0.8, function()
                    if applyBtn and applyBtn.Parent then
                        applyBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 70)
                    end
                end)
                print("[FishIt] Config " .. label .. " = " .. n .. (unit or ""))
            else
                applyBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
                task.delay(0.8, function()
                    if applyBtn and applyBtn.Parent then
                        applyBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 70)
                    end
                end)
            end
        end
        applyBtn.MouseButton1Click:Connect(tryApply)
        box.FocusLost:Connect(function(enter) if enter then tryApply() end end)
    end

    local function cRowInfo(parent, label, value)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 24)
        row.BackgroundColor3 = Color3.fromRGB(26, 26, 38)
        row.BorderSizePixel = 0; row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
        local k = Instance.new("TextLabel"); k.Size = UDim2.new(0.6, 0, 1, 0); k.Position = UDim2.new(0, 8, 0, 0)
        k.BackgroundTransparency = 1; k.Text = label; k.TextColor3 = Color3.fromRGB(160, 160, 160)
        k.Font = Enum.Font.Gotham; k.TextSize = 11; k.TextXAlignment = Enum.TextXAlignment.Left; k.Parent = row
        local v = Instance.new("TextLabel"); v.Size = UDim2.new(0.4, -8, 1, 0); v.Position = UDim2.new(0.6, 0, 0, 0)
        v.BackgroundTransparency = 1; v.Text = value; v.TextColor3 = Color3.fromRGB(80, 180, 255)
        v.Font = Enum.Font.GothamBold; v.TextSize = 11; v.TextXAlignment = Enum.TextXAlignment.Right; v.Parent = row
    end

    cRowEdit(pg3, "MIN_TIER",   ctx.MIN_TIER,                "",    function(n) ctx.setMinTier(math.floor(n))  end)
    cRowEdit(pg3, "Cooldown",   ctx.COOLDOWN,                "s",   function(n) ctx.setCooldown(n)             end)
    cRowEdit(pg3, "AFK Check",  ctx.AFK_CHECK_INTERVAL / 60, "mnt", function(n) ctx.setAfkCheck(n * 60)        end)
    cRowEdit(pg3, "AFK Timeout",ctx.AFK_TIMEOUT / 60,        "mnt", function(n) ctx.setAfkTimeout(n * 60)      end)
    cRowEdit(pg3, "DC Timeout", ctx.DC_REJOIN_TIMEOUT / 60,  "mnt", function(n) ctx.setDcTimeout(n * 60)       end)

    addSection(pg3, "Info")
    cRowInfo(pg3, "Focus Fish",  (function() local c = 0; for _ in pairs(FOCUS_FISH) do c = c + 1 end; return c end)() .. " ikan")
    cRowInfo(pg3, "Crystalized", #CRYSTALIZED_FISH .. " ikan")

    addSection(pg3, "Player Di Server")
    local plrs = Players:GetPlayers()
    cRowInfo(pg3, "Total", #plrs .. " orang")
    for _, p in ipairs(plrs) do cRowInfo(pg3, p.Name, "tracked") end

    switchTab("Settings")
end

return buildUI
