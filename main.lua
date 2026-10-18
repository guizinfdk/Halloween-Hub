-- Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Som de clique
local clickSound = Instance.new("Sound")
clickSound.Name = "ClickSound"
clickSound.SoundId = "rbxassetid://124993589864467"
clickSound.Volume = 0.4
clickSound.Parent = SoundService

local function playClick()
    local s = clickSound:Clone()
    s.Parent = SoundService
    s:Play()
    s.Ended:Connect(function() s:Destroy() end)
end

local function animatePress(btn)
    local originalSize = btn.Size
    local pressedSize = UDim2.new(originalSize.X.Scale, originalSize.X.Offset - 3, originalSize.Y.Scale, originalSize.Y.Offset - 3)
    TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = pressedSize}):Play()
    task.delay(0.08, function()
        TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = originalSize}):Play()
    end)
end

-- ==================== SPEED CORE (Aba 1) ====================
local Speed = { Active = false, Conn = nil, BV = nil, LastChar = nil, Value = 50, Min = 1, Max = 500 }

local function getRootAndHumanoid()
    local char = player.Character
    if not char or not char.Parent then return nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return nil, nil end
    if hum.Health <= 0 then return nil, nil end
    return root, hum
end

function Speed:Cleanup()
    if self.Conn then pcall(function() self.Conn:Disconnect() end); self.Conn = nil end
    if self.BV then pcall(function() self.BV:Destroy() end); self.BV = nil end
    self.LastChar = nil
end

function Speed:Attach()
    local root = getRootAndHumanoid()
    if not root then return false end
    if self.BV then pcall(function() self.BV:Destroy() end) end
    local bv = Instance.new("BodyVelocity")
    bv.Name = "SpeedBodyVelocity"
    bv.MaxForce = Vector3.new(1e5, 0, 1e5)
    bv.Velocity = Vector3.zero
    bv.P = 1250
    bv.Parent = root
    self.BV = bv
    self.LastChar = player.Character
    return true
end

function Speed:HeartbeatStep()
    if player.Character ~= self.LastChar then self:Attach() end
    local root, hum = getRootAndHumanoid()
    if not root or not hum then
        if self.BV and self.BV.Parent then self.BV.Velocity = Vector3.zero end
        return
    end
    if not self.BV or not self.BV.Parent then
        if not self:Attach() then return end
        root, hum = getRootAndHumanoid()
        if not root then return end
    end
    local dir = hum.MoveDirection
    if dir.Magnitude > 0.01 then self.BV.Velocity = dir * self.Value else self.BV.Velocity = Vector3.zero end
end

function Speed:Start()
    if self.Active then return end
    if not self:Attach() then return end
    self.Active = true
    self.Conn = RunService.Heartbeat:Connect(function()
        local ok, err = pcall(function() self:HeartbeatStep() end)
        if not ok then warn("[Speed]", err) end
    end)
end
function Speed:Stop() self.Active = false; self:Cleanup() end
function Speed:SetValue(v) self.Value = math.clamp(math.floor(tonumber(v) or 50), self.Min, self.Max) end

-- ==================== AUTO MONSTER BAT (Aba 2) ====================
local targetMonsterNames = {
    ["Hollow Bat"] = true, ["Scarecrow"] = true, ["Candy Corn"] = true,
    ["Chest Mimic"] = true, ["Pumpkin Golem"] = true, ["Soul Phantom"] = true
}

local isBatActive = false
local activeTool = nil
local targetMonster = nil
local orbitAngle = 0
local activationLoop = nil
local orbitConnection = nil
local unequipConnection = nil
local uiUpdateLoop = nil

local function findBestBatTool()
    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    local exactMatch = nil
    local partialMatch = nil

    local function searchContainer(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                local itemName = string.lower(item.Name)
                if itemName == "bat" then exactMatch = item; break
                elseif string.find(itemName, "bat", 1, true) then
                    if not partialMatch then partialMatch = item end
                end
            end
        end
    end

    searchContainer(backpack)
    if exactMatch then return exactMatch end
    if partialMatch then return partialMatch end
    searchContainer(character)
    if exactMatch then return exactMatch end
    return partialMatch
end

local function isToolEquipped(tool)
    return player.Character and tool.Parent == player.Character
end

local function onUnequipped()
    if not isBatActive or not activeTool then return end
    task.wait(0.1)
    if isBatActive and activeTool and not isToolEquipped(activeTool) then
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then pcall(function() humanoid:EquipTool(activeTool) end) end
    end
end

local function getMonstersFolder()
    local halloweenDim = workspace:FindFirstChild("HalloweenDimension")
    if not halloweenDim then return nil end
    return halloweenDim:FindFirstChild("Monsters")
end

local function isMonsterDead(monster)
    if not monster or not monster.Parent then return true end
    local hrp = monster:FindFirstChild("HumanoidRootPart")
    if not hrp then return true end
    local billboard = hrp:FindFirstChild("MonsterBillboard") or monster:FindFirstChild("MonsterBillboard", true)
    local health = billboard and billboard:FindFirstChild("Health")
    local textLabel = health and health:FindFirstChild("TextLabel")
    if textLabel then
        local numStr = string.match(textLabel.Text, "%d+")
        if numStr and tonumber(numStr) == 0 then return true end
    else
        local hum = monster:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return true end
    end
    return false
end

local function findNewTarget()
    local folder = getMonstersFolder()
    if not folder then return nil end
    for _, monster in ipairs(folder:GetChildren()) do
        if targetMonsterNames[monster.Name] and not isMonsterDead(monster) then
            local hrp = monster:FindFirstChild("HumanoidRootPart")
            if hrp then return monster end
        end
    end
    return nil
end

local function deactivateBat()
    isBatActive = false
    targetMonster = nil
    if activationLoop then task.cancel(activationLoop); activationLoop = nil end
    if orbitConnection then orbitConnection:Disconnect(); orbitConnection = nil end
    if unequipConnection then unequipConnection:Disconnect(); unequipConnection = nil end
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.PlatformStand = false end
    activeTool = nil
end

local function activateBat()
    local tool = findBestBatTool()
    if not tool then return false end
    activeTool = tool
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function() humanoid:EquipTool(tool) end)
        if unequipConnection then unequipConnection:Disconnect() end
        unequipConnection = tool.Unequipped:Connect(onUnequipped)
        isBatActive = true
        targetMonster = findNewTarget()
        if not activationLoop then
            activationLoop = task.spawn(function()
                while isBatActive do
                    task.wait(1)
                    if not isBatActive then break end
                    if activeTool and isToolEquipped(activeTool) then
                        pcall(function() activeTool:Activate() end)
                    end
                end
                activationLoop = nil
            end)
        end
        if not orbitConnection then
            orbitConnection = RunService.RenderStepped:Connect(function(dt)
                if not isBatActive then return end
                if targetMonster and isMonsterDead(targetMonster) then
                    targetMonster = findNewTarget()
                elseif not targetMonster then
                    targetMonster = findNewTarget()
                end
                if targetMonster then
                    local myChar = player.Character
                    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
                    local targetHRP = targetMonster:FindFirstChild("HumanoidRootPart")
                    local hum = myChar and myChar:FindFirstChildOfClass("Humanoid")
                    if myHRP and targetHRP then
                        if hum then hum.PlatformStand = true end
                        orbitAngle = orbitAngle + (dt * 4)
                        local offset = Vector3.new(math.cos(orbitAngle) * 6, 2, math.sin(orbitAngle) * 6)
                        myHRP.CFrame = CFrame.lookAt(targetHRP.Position + offset, targetHRP.Position)
                        myHRP.AssemblyLinearVelocity = Vector3.zero
                        myHRP.AssemblyAngularVelocity = Vector3.zero
                    end
                else
                    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                    if hum then hum.PlatformStand = false end
                end
            end)
        end
        return true
    end
    return false
end

-- ==================== MUSIC PLAYER (Aba 3) ====================
local TRACKS = {
    { Name = "Halloween (Spanish)", Id = "rbxassetid://105627064189291" },
    { Name = "Spooky Scary Skeletons", Id = "rbxassetid://107914377354444" },
    { Name = "Rat Race", Id = "rbxassetid://1845471460" },
    { Name = "Mina (1988)", Id = "rbxassetid://110261717120978" },
}

local BLUE_COLOR = Color3.fromRGB(0, 68, 255)
local RED_COLOR = Color3.fromRGB(255, 0, 0)
local GREEN_COLOR = Color3.fromRGB(0, 200, 100)
local BUTTON_COLOR = Color3.fromRGB(49, 56, 76)

local MUSIC_TRACKS_NAME = "MusicTracks"
local CUSTOM_FOLDER_NAME = "CustomMusicPlayer"

if not SoundService:FindFirstChild(MUSIC_TRACKS_NAME) then
    local folder = Instance.new("Folder"); folder.Name = MUSIC_TRACKS_NAME; folder.Parent = SoundService
end

local customFolder = SoundService:FindFirstChild(CUSTOM_FOLDER_NAME)
if not customFolder then
    customFolder = Instance.new("Folder"); customFolder.Name = CUSTOM_FOLDER_NAME; customFolder.Parent = SoundService
end
for _, child in ipairs(customFolder:GetChildren()) do child:Destroy() end

local musicSound = Instance.new("Sound")
musicSound.Name = "PlayerMusic"; musicSound.Looped = true; musicSound.Volume = 1; musicSound.Parent = customFolder

local mutedSounds = {}
local isMusicPlaying = false
local currentTrackIndex = 1

local function isInsideCustomFolder(snd)
    local p = snd.Parent
    while p and p ~= SoundService do
        if p == customFolder then return true end
        p = p.Parent
    end
    return false
end

local function muteSound(snd)
    if snd == musicSound or isInsideCustomFolder(snd) then return end
    if mutedSounds[snd] == nil then mutedSounds[snd] = snd.Volume; snd.Volume = 0 end
end

local function muteAllOthers()
    for _, d in ipairs(SoundService:GetDescendants()) do
        if d:IsA("Sound") then muteSound(d) end
    end
end

local function restoreAll()
    for snd, vol in pairs(mutedSounds) do
        if snd and snd.Parent then snd.Volume = vol end
    end
    mutedSounds = {}
end

SoundService.DescendantAdded:Connect(function(desc)
    if desc:IsA("Sound") and isMusicPlaying then
        task.delay(0.05, function() if isMusicPlaying and desc.Parent then muteSound(desc) end end)
    end
end)

local function playCurrentTrack()
    musicSound:Stop(); musicSound.SoundId = TRACKS[currentTrackIndex].Id; musicSound.Looped = true; musicSound.Volume = 1; musicSound:Play()
end

-- ==================== EGG FARM SYSTEM (Aba 4) ====================
local isEggFarming = false
local stopEggFarmFunc = nil
local PASSO_STUDS = 100
local INTERVALO_PASSO = 0.3
local DISTANCIA_CHEGADA = 4
local DROP_OFF = Vector3.new(-5810.43, -206.59, -7265.24)
local charEgg, humEgg, rootEgg

local function updateCharEgg(char)
    charEgg = char
    humEgg = char:WaitForChild("Humanoid")
    rootEgg = char:WaitForChild("HumanoidRootPart")
end
if player.Character then updateCharEgg(player.Character) end
player.CharacterAdded:Connect(function(char) task.wait(1); updateCharEgg(char); if isEggFarming and stopEggFarmFunc then stopEggFarmFunc() end end)

local worldEggsFolder = nil
local function getWorldEggs()
    if worldEggsFolder and worldEggsFolder.Parent then return worldEggsFolder end
    local direct = workspace:FindFirstChild("WorldEggs")
    if direct and direct:IsA("Folder") then worldEggsFolder = direct; return direct end
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Folder") and v.Name == "WorldEggs" then worldEggsFolder = v; return v end
    end
    return nil
end

local function getEggs()
    local worldEggs = getWorldEggs()
    if not worldEggs then return {} end
    local eggs = {}
    for _, v in ipairs(worldEggs:GetDescendants()) do
        if v:IsA("Model") and v.Name == "HalloweenEgg" then table.insert(eggs, v) end
    end
    return eggs
end

local function findPrompt(egg)
    local p = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
    if p then return p end
    local eggPos = egg:GetPivot().Position
    local best, bestDist = nil, 60
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") then
            local par = v.Parent
            local pos
            if par and par:IsA("BasePart") then pos = par.Position
            elseif par and par:IsA("Attachment") then pos = par.WorldPosition end
            if pos then
                local d = (pos - eggPos).Magnitude
                if d < bestDist then best, bestDist = v, d end
            end
        end
    end
    return best
end

local function getPromptPos(prompt)
    if not prompt then return nil end
    local par = prompt.Parent
    if par and par:IsA("BasePart") then return par.Position end
    if par and par:IsA("Attachment") then return par.WorldPosition end
    if par and par:IsA("Model") and par.PrimaryPart then return par.PrimaryPart.Position end
    return nil
end

local teleportCancelled = false
local function stopTeleport() teleportCancelled = true end

local function teleportTo(targetPos, ignoreY, onProgress)
    if not rootEgg or not humEgg then return false end
    teleportCancelled = false
    local ws0 = humEgg.WalkSpeed
    local jp0 = humEgg.JumpPower
    humEgg.WalkSpeed = 500
    humEgg.JumpPower = 120

    local target = targetPos
    if ignoreY then target = Vector3.new(target.X, rootEgg.Position.Y, target.Z) end

    local dist0 = (target - rootEgg.Position).Magnitude
    local passos = math.ceil(dist0 / PASSO_STUDS)
    local timeout = math.max(20, passos * (INTERVALO_PASSO + 0.15) + 10)
    local startTime = tick()
    local success = false

    if dist0 <= DISTANCIA_CHEGADA then
        rootEgg.CFrame = CFrame.new(target) * (rootEgg.CFrame - rootEgg.Position)
        humEgg.WalkSpeed = ws0; humEgg.JumpPower = jp0; return true
    end

    if onProgress then onProgress(dist0) end

    while true do
        if teleportCancelled or not rootEgg or not rootEgg.Parent or (tick() - startTime) > timeout then break end
        local cur = rootEgg.Position
        local delta = target - cur
        if ignoreY then delta = Vector3.new(delta.X, 0, delta.Z) end
        local dist = delta.Magnitude

        if dist <= DISTANCIA_CHEGADA then
            rootEgg.CFrame = CFrame.new(target) * (rootEgg.CFrame - rootEgg.Position)
            success = true; break
        end

        local passo = math.min(PASSO_STUDS, dist)
        local dir = delta.Unit
        local nova = cur + dir * passo
        rootEgg.CFrame = CFrame.lookAt(nova, nova + dir)

        if onProgress then onProgress((target - rootEgg.Position).Magnitude) end
        task.wait(INTERVALO_PASSO)
    end

    humEgg.WalkSpeed = ws0; humEgg.JumpPower = jp0
    return success
end

local function holdPrompt(prompt)
    if not prompt or not prompt.Enabled then return false end
    local holdCFrame = rootEgg.CFrame
    local lockConn = RunService.Heartbeat:Connect(function()
        if rootEgg then
            rootEgg.CFrame = holdCFrame
            rootEgg.AssemblyLinearVelocity = Vector3.zero
        end
    end)
    task.wait(0.1)
    prompt:InputHoldBegin()
    local holdDur = prompt.HoldDuration
    if holdDur <= 0 then holdDur = 0.5 end
    task.wait(holdDur + 0.5)
    prompt:InputHoldEnd()
    lockConn:Disconnect()
    return true
end

-- ============ GUI ROOT ============
local gui = Instance.new("ScreenGui")
gui.Name = "RidePLGui"
gui.Enabled = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- ============ DESIGN TOKENS ============
local C = {
    BgPrimary   = Color3.fromRGB(18, 22, 34),
    BgSecondary = Color3.fromRGB(24, 30, 46),
    BgCard      = Color3.fromRGB(32, 40, 60),
    BgCardHover = Color3.fromRGB(42, 52, 76),
    InputBg     = Color3.fromRGB(12, 16, 26),
    Accent      = Color3.fromRGB(255, 149, 0),
    AccentHot   = Color3.fromRGB(255, 187, 60),
    AccentDark  = Color3.fromRGB(198, 88, 0),
    Success     = Color3.fromRGB(0, 216, 120),
    SuccessDk   = Color3.fromRGB(0, 150, 80),
    Danger      = Color3.fromRGB(255, 61, 61),
    DangerDk    = Color3.fromRGB(180, 30, 30),
    Text        = Color3.fromRGB(245, 245, 250),
    TextDim     = Color3.fromRGB(160, 170, 190),
    TextMuted   = Color3.fromRGB(110, 120, 140),
    Border      = Color3.fromRGB(55, 68, 95),
}

local function corner(inst, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst
    return c
end
local function strokeOn(inst, color, thick, transp)
    local s = Instance.new("UIStroke", inst)
    s.Color = color or C.Border
    s.Thickness = thick or 1
    s.Transparency = transp or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    return s
end
local function grad(inst, seq, rot)
    local g = Instance.new("UIGradient", inst)
    g.Color = seq; g.Rotation = rot or 90
    return g
end

-- ============ PANEL ============
local panel = Instance.new("Frame")
panel.Name = "MainPanel"
panel.Size = UDim2.new(0, 260, 0, 270)
panel.Position = UDim2.new(0, 100, 0, 100)
panel.BackgroundColor3 = C.BgPrimary
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 14)
grad(panel, ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 34, 52)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(16, 20, 32)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 28, 44)),
}, 135)
strokeOn(panel, C.Accent, 1.5, 0.2)

-- ============ TITLE BAR ============
local titleBar = Instance.new("TextButton")
titleBar.Size = UDim2.new(1, 0, 0, 42)
titleBar.BackgroundTransparency = 1
titleBar.Text = ""
titleBar.AutoButtonColor = false
titleBar.ZIndex = 3
titleBar.Parent = panel

local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, -30, 0, 2)
accentLine.Position = UDim2.new(0.5, 0, 1, -1)
accentLine.AnchorPoint = Vector2.new(0.5, 1)
accentLine.BackgroundColor3 = C.Accent
accentLine.BorderSizePixel = 0
accentLine.ZIndex = 3
accentLine.Parent = titleBar
corner(accentLine, 1)
local alGrad = grad(accentLine, ColorSequence.new(C.Accent), 0)
alGrad.Transparency = NumberSequence.new{
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.5, 0),
    NumberSequenceKeypoint.new(1, 1),
}

local iconBadge = Instance.new("Frame")
iconBadge.Size = UDim2.new(0, 26, 0, 26)
iconBadge.Position = UDim2.new(0, 10, 0.5, -13)
iconBadge.BackgroundColor3 = C.Accent
iconBadge.BorderSizePixel = 0
iconBadge.ZIndex = 3
iconBadge.Parent = titleBar
corner(iconBadge, 8)
grad(iconBadge, ColorSequence.new{
    ColorSequenceKeypoint.new(0, C.AccentHot),
    ColorSequenceKeypoint.new(1, C.AccentDark),
}, 135)
strokeOn(iconBadge, Color3.fromRGB(255, 220, 140), 1, 0.4)

local titleImage = Instance.new("ImageLabel")
titleImage.Size = UDim2.new(1, -6, 1, -6)
titleImage.Position = UDim2.new(0.5, 0, 0.5, 0)
titleImage.AnchorPoint = Vector2.new(0.5, 0.5)
titleImage.BackgroundTransparency = 1
titleImage.Image = "rbxassetid://7643482836"
titleImage.ZIndex = 4
titleImage.Parent = iconBadge

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 150, 0, 16)
title.Position = UDim2.new(0, 42, 0.5, -10)
title.BackgroundTransparency = 1
title.Text = "HALLOWEEN"
title.Font = Enum.Font.GothamBlack
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 3
title.Parent = titleBar
grad(title, ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 100)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 130, 0)),
}, 0)

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(0, 150, 0, 10)
subtitle.Position = UDim2.new(0, 42, 0.5, 5)
subtitle.BackgroundTransparency = 1
subtitle.Text = "PREMIUM HUB"
subtitle.Font = Enum.Font.GothamBold
subtitle.TextColor3 = C.TextMuted
subtitle.TextSize = 7
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 3
subtitle.Parent = titleBar

local function makeWinBtn(xOff, glyph, hoverBg)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 22, 0, 22)
    btn.Position = UDim2.new(1, xOff, 0.5, -11)
    btn.BackgroundColor3 = Color3.fromRGB(42, 52, 74)
    btn.BorderSizePixel = 0
    btn.Text = glyph
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = C.TextDim
    btn.TextSize = 10
    btn.AutoButtonColor = false
    btn.ZIndex = 3
    btn.Parent = titleBar
    corner(btn, 6)
    local st = strokeOn(btn, C.Border, 1, 0.5)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = hoverBg, TextColor3 = Color3.fromRGB(255,255,255)}):Play()
        TweenService:Create(st, TweenInfo.new(0.15), {Transparency = 0}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(42,52,74), TextColor3 = C.TextDim}):Play()
        TweenService:Create(st, TweenInfo.new(0.15), {Transparency = 0.5}):Play()
    end)
    return btn
end

local minBtn = makeWinBtn(-54, "—", Color3.fromRGB(60, 72, 100))
local closeBtn = makeWinBtn(-28, "✕", C.Danger)

-- ============ SIDEBAR ============
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 36, 1, -52)
sidebar.Position = UDim2.new(0, 8, 0, 46)
sidebar.BackgroundTransparency = 1
sidebar.ZIndex = 2
sidebar.Parent = panel
local sidebarLayout = Instance.new("UIListLayout", sidebar)
sidebarLayout.Padding = UDim.new(0, 6)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- ============ CONTENT ============
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -54, 1, -56)
content.Position = UDim2.new(0, 46, 0, 46)
content.BackgroundColor3 = C.BgSecondary
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.ZIndex = 2
content.Parent = panel
corner(content, 10)
strokeOn(content, C.Border, 1, 0.5)
grad(content, ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 36, 54)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 25, 38)),
}, 135)

-- ============ TAB SYSTEM ============
local tabButtons, contentFrames, currentTab = {}, {}, 1
local tabData = {
    {name = "Tab1", imageId = "117771874883744"},
    {name = "Tab2", imageId = "104110978212953"},
    {name = "Tab3", imageId = "125224435578433"},
    {name = "Tab4", imageId = "124388109032424"},
    {name = "Tab5", imageId = "117142137219942"},
}

for i, data in ipairs(tabData) do
    local isFirst = (i == 1)
    local tabBtn = Instance.new("ImageButton")
    tabBtn.Size = UDim2.new(0, 36, 0, 36)
    tabBtn.BackgroundColor3 = isFirst and C.Accent or C.BgCard
    tabBtn.BorderSizePixel = 0
    tabBtn.AutoButtonColor = false
    tabBtn.Image = "rbxthumb://type=Asset&id=" .. data.imageId .. "&w=150&h=150"
    tabBtn.ImageColor3 = Color3.fromRGB(255, 255, 255)
    tabBtn.LayoutOrder = i
    tabBtn.ZIndex = 3
    tabBtn.Parent = sidebar
    corner(tabBtn, 9)

    local ip = Instance.new("UIPadding", tabBtn)
    ip.PaddingTop = UDim.new(0, 6); ip.PaddingBottom = UDim.new(0, 6)
    ip.PaddingLeft = UDim.new(0, 6); ip.PaddingRight = UDim.new(0, 6)

    local tbs = strokeOn(tabBtn, isFirst and C.AccentHot or C.Border, isFirst and 2 or 1, isFirst and 0 or 0.4)

    tabBtn.MouseEnter:Connect(function()
        if currentTab ~= i then
            TweenService:Create(tabBtn, TweenInfo.new(0.15), {BackgroundColor3 = C.BgCardHover}):Play()
        end
    end)
    tabBtn.MouseLeave:Connect(function()
        if currentTab ~= i then
            TweenService:Create(tabBtn, TweenInfo.new(0.15), {BackgroundColor3 = C.BgCard}):Play()
        end
    end)

    local cFrame = Instance.new("Frame")
    cFrame.Size = UDim2.new(1, 0, 1, 0)
    cFrame.BackgroundTransparency = 1
    cFrame.Visible = isFirst
    cFrame.ZIndex = 2
    cFrame.Parent = content

    tabButtons[i] = tabBtn; contentFrames[i] = cFrame

    if i == 1 then
        -- ============ ABA 1: SPEED ============
        local iconFrame = Instance.new("Frame")
        iconFrame.Size = UDim2.new(0, 36, 0, 36)
        iconFrame.Position = UDim2.new(0.5, 0, 0, 15)
        iconFrame.AnchorPoint = Vector2.new(0.5, 0)
        iconFrame.BackgroundColor3 = C.Accent
        iconFrame.BorderSizePixel = 0
        iconFrame.ZIndex = 3
        iconFrame.Parent = cFrame
        corner(iconFrame, 10)
        grad(iconFrame, ColorSequence.new{
            ColorSequenceKeypoint.new(0, C.AccentHot),
            ColorSequenceKeypoint.new(1, C.AccentDark),
        }, 135)
        strokeOn(iconFrame, Color3.fromRGB(255, 220, 140), 1, 0.35)

        local iconLbl = Instance.new("TextLabel")
        iconLbl.Size = UDim2.new(1, 0, 1, 0)
        iconLbl.BackgroundTransparency = 1
        iconLbl.Text = "⚡"
        iconLbl.Font = Enum.Font.GothamBold
        iconLbl.TextColor3 = Color3.fromRGB(255,255,255)
        iconLbl.TextSize = 18
        iconLbl.ZIndex = 4
        iconLbl.Parent = iconFrame

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1, 0, 0, 14); titleLbl.Position = UDim2.new(0, 0, 0, 60)
        titleLbl.BackgroundTransparency = 1; titleLbl.Text = "SPEED BOOST"
        titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextColor3 = C.Text; titleLbl.TextSize = 11; titleLbl.ZIndex = 3; titleLbl.Parent = cFrame

        local subLbl = Instance.new("TextLabel")
        subLbl.Size = UDim2.new(1, 0, 0, 12); subLbl.Position = UDim2.new(0, 0, 0, 74)
        subLbl.BackgroundTransparency = 1; subLbl.Text = "Set your speed"
        subLbl.Font = Enum.Font.Gotham; subLbl.TextColor3 = C.TextMuted; subLbl.TextSize = 9; subLbl.ZIndex = 3; subLbl.Parent = cFrame

        local inputBox = Instance.new("Frame")
        inputBox.Size = UDim2.new(0, 130, 0, 32); inputBox.Position = UDim2.new(0.5, 0, 0, 98); inputBox.AnchorPoint = Vector2.new(0.5, 0)
        inputBox.BackgroundColor3 = C.InputBg; inputBox.BorderSizePixel = 0; inputBox.ZIndex = 3; inputBox.Parent = cFrame
        corner(inputBox, 8)
        local ibStroke = strokeOn(inputBox, C.Border, 1.5, 0.2)

        local prefixLbl = Instance.new("TextLabel")
        prefixLbl.Size = UDim2.new(0, 24, 1, 0); prefixLbl.Position = UDim2.new(0, 6, 0, 0)
        prefixLbl.BackgroundTransparency = 1; prefixLbl.Text = "⚡"
        prefixLbl.Font = Enum.Font.GothamBold; prefixLbl.TextColor3 = C.Accent; prefixLbl.TextSize = 13; prefixLbl.ZIndex = 4; prefixLbl.Parent = inputBox

        local speedBox = Instance.new("TextBox")
        speedBox.Size = UDim2.new(1, -32, 1, 0); speedBox.Position = UDim2.new(0, 28, 0, 0)
        speedBox.BackgroundTransparency = 1; speedBox.Text = tostring(Speed.Value)
        speedBox.PlaceholderText = "1-500"; speedBox.PlaceholderColor3 = C.TextMuted
        speedBox.Font = Enum.Font.GothamBold; speedBox.TextColor3 = C.Text; speedBox.TextSize = 14
        speedBox.TextXAlignment = Enum.TextXAlignment.Left; speedBox.ClearTextOnFocus = false
        speedBox.ZIndex = 4; speedBox.Parent = inputBox

        local speedBtn = Instance.new("TextButton")
        speedBtn.Size = UDim2.new(0, 140, 0, 34); speedBtn.Position = UDim2.new(0.5, 0, 0, 142); speedBtn.AnchorPoint = Vector2.new(0.5, 0)
        speedBtn.BackgroundColor3 = C.BgCard; speedBtn.BorderSizePixel = 0
        speedBtn.Text = "OFF"; speedBtn.Font = Enum.Font.GothamBlack
        speedBtn.TextColor3 = C.Text; speedBtn.TextSize = 13
        speedBtn.AutoButtonColor = false; speedBtn.ZIndex = 3; speedBtn.Parent = cFrame
        corner(speedBtn, 9)
        local sbst = strokeOn(speedBtn, C.Border, 1.5, 0.3)

        local function refreshSpeedUI()
            if Speed.Active then
                speedBtn.Text = "ON"
                TweenService:Create(speedBtn, TweenInfo.new(0.2), {BackgroundColor3 = C.Success, TextColor3 = Color3.fromRGB(10, 25, 15)}):Play()
                TweenService:Create(sbst, TweenInfo.new(0.2), {Color = C.Success, Thickness = 2, Transparency = 0}):Play()
            else
                speedBtn.Text = "OFF"
                TweenService:Create(speedBtn, TweenInfo.new(0.2), {BackgroundColor3 = C.BgCard, TextColor3 = C.Text}):Play()
                TweenService:Create(sbst, TweenInfo.new(0.2), {Color = C.Border, Thickness = 1.5, Transparency = 0.3}):Play()
            end
            speedBox.Text = tostring(Speed.Value)
        end

        speedBtn.MouseButton1Click:Connect(function()
            playClick(); animatePress(speedBtn)
            if Speed.Active then Speed:Stop() else Speed:Start() end
            refreshSpeedUI()
        end)
        speedBtn.MouseEnter:Connect(function() TweenService:Create(sbst, TweenInfo.new(0.15), {Thickness = 2.5}):Play() end)
        speedBtn.MouseLeave:Connect(function() if not Speed.Active then TweenService:Create(sbst, TweenInfo.new(0.15), {Thickness = 1.5}):Play() end end)

        speedBox.Focused:Connect(function()
            playClick()
            TweenService:Create(ibStroke, TweenInfo.new(0.15), {Color = C.Accent, Thickness = 2}):Play()
            TweenService:Create(inputBox, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(20, 25, 38)}):Play()
        end)
        speedBox.FocusLost:Connect(function()
            TweenService:Create(ibStroke, TweenInfo.new(0.15), {Color = C.Border, Thickness = 1.5}):Play()
            TweenService:Create(inputBox, TweenInfo.new(0.15), {BackgroundColor3 = C.InputBg}):Play()
            local n = tonumber(string.match(speedBox.Text, "%-?%d+") or "")
            if n then Speed:SetValue(n) end
            speedBox.Text = tostring(Speed.Value)
        end)
        refreshSpeedUI()

    elseif i == 2 then
        -- ============ ABA 2: AUTO MONSTER BAT ============
        local scrollFrame = Instance.new("ScrollingFrame")
        scrollFrame.Size = UDim2.new(1, -8, 1, -40); scrollFrame.Position = UDim2.new(0, 4, 0, 4)
        scrollFrame.BackgroundColor3 = C.InputBg; scrollFrame.BorderSizePixel = 0
        scrollFrame.ScrollBarThickness = 2; scrollFrame.ScrollBarImageColor3 = C.Accent
        scrollFrame.ZIndex = 3; scrollFrame.Parent = cFrame
        corner(scrollFrame, 8)
        strokeOn(scrollFrame, C.Border, 1, 0.6)
        local uiListLayout = Instance.new("UIListLayout", scrollFrame)
        uiListLayout.Padding = UDim.new(0, 4); uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        local padding = Instance.new("UIPadding", scrollFrame)
        padding.PaddingTop = UDim.new(0, 4); padding.PaddingLeft = UDim.new(0, 4)
        padding.PaddingRight = UDim.new(0, 4); padding.PaddingBottom = UDim.new(0, 4)

        local toggleButton = Instance.new("TextButton")
        toggleButton.Size = UDim2.new(1, -16, 0, 28); toggleButton.Position = UDim2.new(0.5, 0, 1, -32); toggleButton.AnchorPoint = Vector2.new(0.5, 0)
        toggleButton.BackgroundColor3 = C.BgCard; toggleButton.BorderSizePixel = 0
        toggleButton.Text = "ATIVAR"; toggleButton.TextColor3 = C.Text
        toggleButton.Font = Enum.Font.GothamBlack; toggleButton.TextSize = 11
        toggleButton.AutoButtonColor = false; toggleButton.ZIndex = 3; toggleButton.Parent = cFrame
        corner(toggleButton, 8)
        local tStroke = strokeOn(toggleButton, C.Border, 1.5, 0.3)

        local function refreshMonsterListUI()
            for _, child in ipairs(scrollFrame:GetChildren()) do
                if child:IsA("Frame") then child:Destroy() end
            end
            local folder = getMonstersFolder()
            if not folder then return end
            local myChar = player.Character; local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart"); local count = 0

            for _, monster in ipairs(folder:GetChildren()) do
                if targetMonsterNames[monster.Name] and not isMonsterDead(monster) then
                    local monsterHRP = monster:FindFirstChild("HumanoidRootPart")
                    if not monsterHRP then continue end
                    count = count + 1
                    local distance = 0
                    if myHRP then distance = math.floor((myHRP.Position - monsterHRP.Position).Magnitude) end

                    local isTarget = (targetMonster == monster)
                    local card = Instance.new("Frame")
                    card.Size = UDim2.new(1, 0, 0, 30)
                    card.BackgroundColor3 = isTarget and Color3.fromRGB(48, 32, 34) or C.BgCard
                    card.BorderSizePixel = 0; card.LayoutOrder = count; card.Parent = scrollFrame
                    corner(card, 5)
                    if isTarget then strokeOn(card, C.Danger, 1.5, 0.2) end

                    local indicator = Instance.new("Frame")
                    indicator.Size = UDim2.new(0, 3, 1, -10); indicator.Position = UDim2.new(0, 5, 0, 5)
                    indicator.BackgroundColor3 = isTarget and C.Danger or Color3.fromRGB(80, 160, 255)
                    indicator.BorderSizePixel = 0; indicator.Parent = card
                    corner(indicator, 2)

                    local nameLabel = Instance.new("TextLabel")
                    nameLabel.Size = UDim2.new(1, -20, 0, 13); nameLabel.Position = UDim2.new(0, 14, 0, 2)
                    nameLabel.BackgroundTransparency = 1; nameLabel.Text = monster.Name
                    nameLabel.TextColor3 = C.Text; nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                    nameLabel.Font = Enum.Font.GothamBold; nameLabel.TextSize = 10; nameLabel.Parent = card

                    local distLabel = Instance.new("TextLabel")
                    distLabel.Size = UDim2.new(1, -20, 0, 11); distLabel.Position = UDim2.new(0, 14, 0, 15)
                    distLabel.BackgroundTransparency = 1; distLabel.Text = distance .. " studs"
                    distLabel.TextColor3 = C.TextMuted; distLabel.TextXAlignment = Enum.TextXAlignment.Left
                    distLabel.Font = Enum.Font.Gotham; distLabel.TextSize = 9; distLabel.Parent = card
                end
            end
            scrollFrame.CanvasSize = UDim2.new(0, 0, 0, uiListLayout.AbsoluteContentSize.Y + 8)
        end

        if not uiUpdateLoop then
            uiUpdateLoop = task.spawn(function()
                while true do task.wait(1); if gui.Parent then refreshMonsterListUI() else break end end
            end)
        end

        toggleButton.MouseButton1Click:Connect(function()
            playClick(); animatePress(toggleButton)
            if isBatActive then
                deactivateBat(); toggleButton.Text = "ATIVAR"
                TweenService:Create(toggleButton, TweenInfo.new(0.2), {BackgroundColor3 = C.BgCard, TextColor3 = C.Text}):Play()
                TweenService:Create(tStroke, TweenInfo.new(0.2), {Color = C.Border, Transparency = 0.3}):Play()
            else
                if activateBat() then
                    toggleButton.Text = "PARAR"
                    TweenService:Create(toggleButton, TweenInfo.new(0.2), {BackgroundColor3 = C.Danger, TextColor3 = Color3.fromRGB(255,255,255)}):Play()
                    TweenService:Create(tStroke, TweenInfo.new(0.2), {Color = C.Danger, Transparency = 0}):Play()
                else
                    toggleButton.Text = "SEM BAT"; task.wait(1.5); toggleButton.Text = "ATIVAR"
                end
            end
            refreshMonsterListUI()
        end)
        toggleButton.MouseEnter:Connect(function() TweenService:Create(tStroke, TweenInfo.new(0.15), {Thickness = 2.5}):Play() end)
        toggleButton.MouseLeave:Connect(function() TweenService:Create(tStroke, TweenInfo.new(0.15), {Thickness = 1.5}):Play() end)

    elseif i == 3 then
        -- ============ ABA 3: MUSIC PLAYER ============
        local visualizer = Instance.new("Frame")
        visualizer.Size = UDim2.new(1, -16, 0, 60); visualizer.Position = UDim2.new(0.5, 0, 0, 6); visualizer.AnchorPoint = Vector2.new(0.5, 0)
        visualizer.BackgroundColor3 = C.InputBg; visualizer.BorderSizePixel = 0; visualizer.ClipsDescendants = true
        visualizer.ZIndex = 3; visualizer.Parent = cFrame
        corner(visualizer, 6)
        strokeOn(visualizer, C.Border, 1, 0.5)
        grad(visualizer, ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 20, 32)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 13, 22)),
        }, 90)

        local bars = {}; local BAR_COUNT = 12
        for b = 1, BAR_COUNT do
            local bar = Instance.new("Frame")
            bar.AnchorPoint = Vector2.new(0, 1)
            bar.Position = UDim2.new(0, 4 + (b - 1) * 12, 1, -4)
            bar.Size = UDim2.new(0, 6, 0, 3)
            bar.BackgroundColor3 = (b % 2 == 1) and Color3.fromRGB(80, 140, 255) or C.Danger
            bar.BorderSizePixel = 0; bar.ZIndex = 4; bar.Parent = visualizer
            corner(bar, 2)
            grad(bar, ColorSequence.new{
                ColorSequenceKeypoint.new(0, (b % 2 == 1) and Color3.fromRGB(120, 190, 255) or Color3.fromRGB(255, 110, 110)),
                ColorSequenceKeypoint.new(1, (b % 2 == 1) and Color3.fromRGB(50, 100, 220) or Color3.fromRGB(180, 30, 30)),
            }, 90)
            bars[b] = { Frame = bar, Current = 3, Target = 3, Speed = 5, Timer = math.random() * 0.2 }
        end

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -16, 0, 20); nameLabel.Position = UDim2.new(0.5, 0, 0, 70); nameLabel.AnchorPoint = Vector2.new(0.5, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = TRACKS[currentTrackIndex].Name
        nameLabel.Font = Enum.Font.GothamBold; nameLabel.TextColor3 = C.Text
        nameLabel.TextSize = 11; nameLabel.TextWrapped = true
        nameLabel.TextYAlignment = Enum.TextYAlignment.Center; nameLabel.ZIndex = 3; nameLabel.Parent = cFrame

        local startBtn = Instance.new("TextButton")
        startBtn.Size = UDim2.new(0, 34, 0, 34); startBtn.Position = UDim2.new(0.5, 0, 1, -8); startBtn.AnchorPoint = Vector2.new(0.5, 1)
        startBtn.BackgroundColor3 = C.BgCard; startBtn.BorderSizePixel = 0
        startBtn.AutoButtonColor = false; startBtn.Text = "▶"
        startBtn.Font = Enum.Font.GothamBold; startBtn.TextColor3 = C.Text; startBtn.TextSize = 14
        startBtn.ZIndex = 3; startBtn.Parent = cFrame
        corner(startBtn, 17)
        local startStroke = strokeOn(startBtn, C.Border, 1.5, 0.3)

        local prevBtn = Instance.new("TextButton")
        prevBtn.Size = UDim2.new(0, 28, 0, 28); prevBtn.Position = UDim2.new(0.5, -38, 1, -11); prevBtn.AnchorPoint = Vector2.new(0.5, 1)
        prevBtn.BackgroundColor3 = C.BgCard; prevBtn.BorderSizePixel = 0; prevBtn.AutoButtonColor = false
        prevBtn.Text = "◀"; prevBtn.Font = Enum.Font.GothamBold; prevBtn.TextColor3 = C.TextDim; prevBtn.TextSize = 11
        prevBtn.ZIndex = 3; prevBtn.Parent = cFrame
        corner(prevBtn, 14)
        local prevStroke = strokeOn(prevBtn, C.Border, 1, 0.5)

        local nextBtn = Instance.new("TextButton")
        nextBtn.Size = UDim2.new(0, 28, 0, 28); nextBtn.Position = UDim2.new(0.5, 38, 1, -11); nextBtn.AnchorPoint = Vector2.new(0.5, 1)
        nextBtn.BackgroundColor3 = C.BgCard; nextBtn.BorderSizePixel = 0; nextBtn.AutoButtonColor = false
        nextBtn.Text = "▶"; nextBtn.Font = Enum.Font.GothamBold; nextBtn.TextColor3 = C.TextDim; nextBtn.TextSize = 11
        nextBtn.ZIndex = 3; nextBtn.Parent = cFrame
        corner(nextBtn, 14)
        local nextStroke = strokeOn(nextBtn, C.Border, 1, 0.5)

        startBtn.MouseButton1Click:Connect(function()
            playClick(); animatePress(startBtn)
            if isMusicPlaying then
                isMusicPlaying = false; musicSound:Stop(); restoreAll()
                startBtn.Text = "▶"; startBtn.BackgroundColor3 = C.BgCard; startBtn.TextColor3 = C.Text
                TweenService:Create(startStroke, TweenInfo.new(0.2), {Color = C.Border, Transparency = 0.3}):Play()
            else
                isMusicPlaying = true
                startBtn.Text = "■"; startBtn.BackgroundColor3 = C.Success; startBtn.TextColor3 = Color3.fromRGB(10, 25, 15)
                TweenService:Create(startStroke, TweenInfo.new(0.2), {Color = C.Success, Transparency = 0}):Play()
                muteAllOthers(); playCurrentTrack()
            end
        end)
        prevBtn.MouseButton1Click:Connect(function()
            playClick(); animatePress(prevBtn)
            currentTrackIndex -= 1; if currentTrackIndex < 1 then currentTrackIndex = #TRACKS end
            nameLabel.Text = TRACKS[currentTrackIndex].Name
            if isMusicPlaying then playCurrentTrack() end
        end)
        nextBtn.MouseButton1Click:Connect(function()
            playClick(); animatePress(nextBtn)
            currentTrackIndex += 1; if currentTrackIndex > #TRACKS then currentTrackIndex = 1 end
            nameLabel.Text = TRACKS[currentTrackIndex].Name
            if isMusicPlaying then playCurrentTrack() end
        end)
        prevBtn.MouseEnter:Connect(function() TweenService:Create(prevStroke, TweenInfo.new(0.15), {Color = C.Accent}):Play() end)
        prevBtn.MouseLeave:Connect(function() TweenService:Create(prevStroke, TweenInfo.new(0.15), {Color = C.Border}):Play() end)
        nextBtn.MouseEnter:Connect(function() TweenService:Create(nextStroke, TweenInfo.new(0.15), {Color = C.Accent}):Play() end)
        nextBtn.MouseLeave:Connect(function() TweenService:Create(nextStroke, TweenInfo.new(0.15), {Color = C.Border}):Play() end)
        startBtn.MouseEnter:Connect(function() TweenService:Create(startStroke, TweenInfo.new(0.15), {Thickness = 2.5}):Play() end)
        startBtn.MouseLeave:Connect(function() TweenService:Create(startStroke, TweenInfo.new(0.15), {Thickness = 1.5}):Play() end)

        RunService.Heartbeat:Connect(function(dt)
            for _, b in ipairs(bars) do
                if isMusicPlaying then
                    b.Timer -= dt
                    if b.Timer <= 0 then b.Target = math.random() * 45 + 5; b.Timer = math.random() * 0.25 + 0.06; b.Speed = math.random() * 6 + 4 end
                    b.Current += (b.Target - b.Current) * math.min(1, dt * b.Speed)
                else
                    b.Current += (3 - b.Current) * math.min(1, dt * 6)
                end
                local h = math.max(3, b.Current); b.Frame.Size = UDim2.new(0, 6, 0, h)
            end
        end)

    elseif i == 4 then
        -- ============ ABA 4: EGG FARM ============
        local scrollFrame = Instance.new("ScrollingFrame")
        scrollFrame.Size = UDim2.new(1, -8, 1, -40); scrollFrame.Position = UDim2.new(0, 4, 0, 4)
        scrollFrame.BackgroundColor3 = C.InputBg; scrollFrame.BorderSizePixel = 0
        scrollFrame.ScrollBarThickness = 2; scrollFrame.ScrollBarImageColor3 = C.Accent
        scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y; scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        scrollFrame.ZIndex = 3; scrollFrame.Parent = cFrame
        corner(scrollFrame, 8)
        strokeOn(scrollFrame, C.Border, 1, 0.6)

        local listLayout = Instance.new("UIListLayout", scrollFrame)
        listLayout.Padding = UDim.new(0, 4); listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        local listPadding = Instance.new("UIPadding", scrollFrame)
        listPadding.PaddingTop = UDim.new(0, 4); listPadding.PaddingBottom = UDim.new(0, 4)
        listPadding.PaddingLeft = UDim.new(0, 4); listPadding.PaddingRight = UDim.new(0, 4)

        local cardCounter = 0
        local lastSystemMsg, lastSystemTime = nil, 0

        local function addCard(title, subtitle, indicatorColor)
            cardCounter = cardCounter + 1
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, 0, 0, 30); card.BackgroundColor3 = C.BgCard
            card.BorderSizePixel = 0; card.LayoutOrder = cardCounter; card.Parent = scrollFrame
            corner(card, 5)

            local indicator = Instance.new("Frame")
            indicator.Size = UDim2.new(0, 3, 1, -10); indicator.Position = UDim2.new(0, 5, 0, 5)
            indicator.BackgroundColor3 = indicatorColor or C.AccentHot; indicator.BorderSizePixel = 0; indicator.Parent = card
            corner(indicator, 2)

            local titleLabel = Instance.new("TextLabel")
            titleLabel.Size = UDim2.new(1, -20, 0, 13); titleLabel.Position = UDim2.new(0, 14, 0, 2)
            titleLabel.BackgroundTransparency = 1; titleLabel.Text = title
            titleLabel.TextColor3 = C.Text; titleLabel.TextSize = 10
            titleLabel.Font = Enum.Font.GothamBold; titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.Parent = card

            local subtitleLabel = Instance.new("TextLabel")
            subtitleLabel.Size = UDim2.new(1, -20, 0, 11); subtitleLabel.Position = UDim2.new(0, 14, 0, 15)
            subtitleLabel.BackgroundTransparency = 1; subtitleLabel.Text = subtitle or ""
            subtitleLabel.TextColor3 = C.TextMuted; subtitleLabel.TextSize = 9
            subtitleLabel.Font = Enum.Font.Gotham; subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left; subtitleLabel.Parent = card

            local handle = {}
            function handle.setDistance(d) subtitleLabel.Text = string.format("Distância: %d studs", math.floor(d)) end
            function handle.setStatus(status, text)
                if status == "progress" then indicator.BackgroundColor3 = C.AccentHot; subtitleLabel.TextColor3 = C.TextDim
                elseif status == "done" then indicator.BackgroundColor3 = C.Success; subtitleLabel.TextColor3 = Color3.fromRGB(140, 240, 170)
                elseif status == "fail" then indicator.BackgroundColor3 = C.Danger; subtitleLabel.TextColor3 = Color3.fromRGB(255, 150, 150) end
                if text then subtitleLabel.Text = text end
            end
            task.defer(function() scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.AbsoluteCanvasSize.Y) end)
            return handle
        end

        local function addSystemCard(message)
            if lastSystemMsg == message and (tick() - lastSystemTime) < 3 then return end
            lastSystemMsg, lastSystemTime = message, tick()
            addCard("Sistema", message, C.TextMuted)
        end

        local function farmLoopFunc()
            local eggNumber = 0
            while isEggFarming do
                local eggs = getEggs()
                if #eggs == 0 then addSystemCard("Nenhum Ovo encontrado"); task.wait(1); continue end
                if not isEggFarming then break end
                eggNumber = eggNumber + 1
                local egg = eggs[math.random(1, #eggs)]
                local card = addCard(string.format("#%d Ovo", eggNumber), "Calculando...", C.AccentHot)
                task.wait(0.1)
                local prompt = findPrompt(egg)
                if not prompt then card.setStatus("fail", "Sem ProximityPrompt"); task.wait(0.5); continue end
                local targetPos = getPromptPos(prompt) or egg:GetPivot().Position
                local ok = teleportTo(targetPos, false, function(d) card.setDistance(d) end)
                if not ok then card.setStatus("fail", "Falha no teleporte"); task.wait(1); continue end
                if not isEggFarming then break end
                card.setStatus("progress", "Coletando...")
                local okHold = holdPrompt(prompt)
                if not isEggFarming then break end
                if not okHold then card.setStatus("fail", "Falha ao coletar"); task.wait(0.5); continue end
                card.setStatus("done", "✓ Coletado — Indo pro Drop-off")
                local ok2 = teleportTo(DROP_OFF, false, nil)
                if not ok2 then card.setStatus("fail", "Falha no drop-off"); task.wait(1); continue end
                if not isEggFarming then break end
                task.wait(0.5)
            end
        end

        local toggleBtn = Instance.new("TextButton")
        toggleBtn.Size = UDim2.new(1, -16, 0, 28); toggleBtn.Position = UDim2.new(0.5, 0, 1, -32); toggleBtn.AnchorPoint = Vector2.new(0.5, 0)
        toggleBtn.BackgroundColor3 = C.Accent; toggleBtn.BorderSizePixel = 0
        toggleBtn.Text = "▶ Ativar Auto Farm"; toggleBtn.TextColor3 = Color3.fromRGB(255,255,255)
        toggleBtn.Font = Enum.Font.GothamBlack; toggleBtn.TextSize = 11
        toggleBtn.AutoButtonColor = false; toggleBtn.ZIndex = 3; toggleBtn.Parent = cFrame
        corner(toggleBtn, 8)
        local btnStroke = strokeOn(toggleBtn, C.AccentHot, 1.5, 0.2)

        toggleBtn.MouseButton1Click:Connect(function()
            playClick(); animatePress(toggleBtn)
            if isEggFarming then
                isEggFarming = false
                if stopEggFarmFunc then stopEggFarmFunc() end
                stopTeleport()
                toggleBtn.Text = "▶ Ativar Auto Farm"
                TweenService:Create(toggleBtn, TweenInfo.new(0.2), {BackgroundColor3 = C.Accent}):Play()
                TweenService:Create(btnStroke, TweenInfo.new(0.2), {Color = C.AccentHot, Thickness = 1.5}):Play()
                addSystemCard("Auto Farm parado")
            else
                if not rootEgg then addSystemCard("Personagem não carregado"); return end
                isEggFarming = true
                toggleBtn.Text = "⏹ Desativar Auto Farm"
                TweenService:Create(toggleBtn, TweenInfo.new(0.2), {BackgroundColor3 = C.Success}):Play()
                TweenService:Create(btnStroke, TweenInfo.new(0.2), {Color = C.Success, Thickness = 2}):Play()
                addSystemCard("Auto Farm iniciado")
                task.spawn(farmLoopFunc)
            end
        end)

        stopEggFarmFunc = function()
            isEggFarming = false; stopTeleport()
            toggleBtn.Text = "▶ Ativar Auto Farm"
            TweenService:Create(toggleBtn, TweenInfo.new(0.2), {BackgroundColor3 = C.Accent}):Play()
            TweenService:Create(btnStroke, TweenInfo.new(0.2), {Color = C.AccentHot}):Play()
        end
        toggleBtn.MouseEnter:Connect(function() TweenService:Create(btnStroke, TweenInfo.new(0.15), {Thickness = 2.5}):Play() end)
        toggleBtn.MouseLeave:Connect(function() TweenService:Create(btnStroke, TweenInfo.new(0.15), {Thickness = 1.5}):Play() end)

        task.spawn(function()
            task.wait(1)
            if not getWorldEggs() then addSystemCard("⚠ WorldEggs não encontrado")
            else addSystemCard(string.format("%d HalloweenEgg(s) encontrados", #getEggs())) end
        end)

    elseif i == 5 then
        -- ============ ABA 5: EGG RADAR ============
        local CONFIG = {
            DimensionName = "HalloweenDimension",
            FolderName    = "WorldEggs",
            EggName       = "HalloweenEgg",
            UpdateInterval = 0.25,
            ZoomMin        = 0.45,
            ZoomMax        = 3.0,
        }

        local function getModelPosition(model)
            local ok, cf = pcall(function() return model:GetBoundingBox() end)
            if ok and cf then return cf.Position end
            local ok2, pivot = pcall(function() return model:GetPivot() end)
            if ok2 and pivot then return pivot.Position end
            return nil
        end
        local function getCharacterPosition()
            local char = player.Character
            if not char then return nil end
            local root = char:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then return root.Position end
            return nil
        end

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, -8, 1, -8); scroll.Position = UDim2.new(0, 4, 0, 4)
        scroll.BackgroundColor3 = C.InputBg; scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 2; scroll.ScrollBarImageColor3 = C.Accent
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.ZIndex = 3; scroll.Parent = cFrame
        corner(scroll, 8)
        strokeOn(scroll, C.Border, 1, 0.6)

        local listLayout = Instance.new("UIListLayout", scroll)
        listLayout.Padding = UDim.new(0, 4); listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        local listPadding = Instance.new("UIPadding", scroll)
        listPadding.PaddingTop = UDim.new(0, 4); listPadding.PaddingBottom = UDim.new(0, 4)
        listPadding.PaddingLeft = UDim.new(0, 4); listPadding.PaddingRight = UDim.new(0, 4)

        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, -20, 0, 40); emptyLabel.Position = UDim2.new(0.5, 0, 0.5, 0); emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        emptyLabel.BackgroundTransparency = 1; emptyLabel.Text = "Procurando Ovos..."
        emptyLabel.TextColor3 = C.TextMuted; emptyLabel.Font = Enum.Font.Gotham; emptyLabel.TextSize = 10
        emptyLabel.TextWrapped = true; emptyLabel.Visible = true; emptyLabel.ZIndex = 3; emptyLabel.Parent = cFrame

        local cards = {}; local cardCounter = 0; local activeDrag = nil

        local function pointerPos(input)
            if input.UserInputType == Enum.UserInputType.Touch then return Vector2.new(input.Position.X, input.Position.Y) end
            return UserInputService:GetMouseLocation()
        end

        local function updateCardInfo(data, myPos)
            local pos = getModelPosition(data.egg)
            if not pos then return end
            if myPos then
                local dist = (myPos - pos).Magnitude
                data.distLabel.Text = string.format("%.0f m", dist)
                if dist < 100 then data.distLabel.TextColor3 = C.Success
                elseif dist < 350 then data.distLabel.TextColor3 = C.AccentHot
                else data.distLabel.TextColor3 = C.Danger end
            else
                data.distLabel.Text = "--"; data.distLabel.TextColor3 = C.TextMuted
            end
        end

        local function updateEmptyState()
            local count = 0; for _ in pairs(cards) do count += 1 end
            emptyLabel.Visible = (count == 0)
        end

        local function removeCard(egg)
            local data = cards[egg]
            if not data then return end
            cards[egg] = nil
            if data.frame then data.frame:Destroy() end
            if activeDrag and activeDrag.data == data then activeDrag = nil end
            updateEmptyState()
        end

        local function createCard(egg)
            if cards[egg] then return end
            cardCounter += 1
            local data = { egg = egg, yaw = math.rad(35), pitch = math.rad(-22), zoom = 1, clone = nil }

            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, 0, 0, 42); card.BackgroundColor3 = C.BgCard
            card.BorderSizePixel = 0; card.LayoutOrder = cardCounter; card.Parent = scroll
            corner(card, 6)
            strokeOn(card, C.Border, 1, 0.5)

            local vp = Instance.new("ViewportFrame")
            vp.Size = UDim2.new(0, 34, 0, 34); vp.Position = UDim2.new(0, 4, 0.5, -17)
            vp.BackgroundColor3 = Color3.fromRGB(14, 14, 22); vp.BorderSizePixel = 0
            vp.Ambient = Color3.fromRGB(160, 160, 175); vp.LightColor = Color3.fromRGB(255, 245, 235)
            vp.LightDirection = Vector3.new(-0.4, -1, -0.6); vp.Parent = card
            corner(vp, 5)
            strokeOn(vp, C.Border, 1, 0.3)

            local world = Instance.new("WorldModel", vp)
            local cam = Instance.new("Camera", vp); cam.FieldOfView = 35; vp.CurrentCamera = cam

            local function updateView()
                local clone = data.clone
                if not clone or not clone.Parent then return end
                local ok, cf, size = pcall(function() local c, s = clone:GetBoundingBox(); return c, s end)
                if not ok or not cf or not size then return end
                local center = cf.Position
                local maxDim = math.max(size.X, size.Y, size.Z, 0.5)
                local baseDist = (maxDim * 0.5) / math.tan(math.rad(cam.FieldOfView) * 0.5) * 1.45
                local dist = baseDist * data.zoom
                local rot = CFrame.Angles(0, data.yaw, 0) * CFrame.Angles(data.pitch, 0, 0)
                cam.CFrame = CFrame.lookAt(center + rot * Vector3.new(0, 0, dist), center)
            end
            data.updateView = updateView

            function data.setPreviewModel(model)
                if data.clone then data.clone:Destroy(); data.clone = nil end
                local clone = model:Clone()
                for _, d in ipairs(clone:GetDescendants()) do
                    if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then d:Destroy()
                    elseif d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
                end
                if clone:IsA("BasePart") then clone.Anchored = true; clone.CanCollide = false end
                clone.Parent = world; data.clone = clone; updateView()
            end
            data.setPreviewModel(egg)

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -46, 0, 13); nameLabel.Position = UDim2.new(0, 44, 0, 6)
            nameLabel.BackgroundTransparency = 1; nameLabel.Text = "Ovo #" .. cardCounter
            nameLabel.TextColor3 = C.Text; nameLabel.Font = Enum.Font.GothamBold; nameLabel.TextSize = 10
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left; nameLabel.TextTruncate = Enum.TextTruncate.AtEnd; nameLabel.Parent = card

            local distLabel = Instance.new("TextLabel")
            distLabel.Size = UDim2.new(1, -46, 0, 14); distLabel.Position = UDim2.new(0, 44, 0, 20)
            distLabel.BackgroundTransparency = 1; distLabel.Text = "--"
            distLabel.TextColor3 = C.Success; distLabel.Font = Enum.Font.GothamBold; distLabel.TextSize = 12
            distLabel.TextXAlignment = Enum.TextXAlignment.Left; distLabel.Parent = card

            data.frame = card; data.distLabel = distLabel

            local lastClick = 0
            vp.InputBegan:Connect(function(input)
                local ut = input.UserInputType
                if ut == Enum.UserInputType.MouseButton1 then
                    local now = os.clock()
                    if now - lastClick < 0.35 then data.yaw = math.rad(35); data.pitch = math.rad(-22); data.zoom = 1; updateView() end
                    lastClick = now; activeDrag = { data = data, mode = "rotate", last = pointerPos(input) }
                elseif ut == Enum.UserInputType.MouseButton2 then
                    activeDrag = { data = data, mode = "zoom", last = pointerPos(input) }
                elseif ut == Enum.UserInputType.Touch then
                    activeDrag = { data = data, mode = "rotate", last = pointerPos(input) }
                end
            end)

            local refreshQueued = false
            local function queueRefresh()
                if refreshQueued then return end
                refreshQueued = true
                task.delay(1, function()
                    refreshQueued = false
                    if not cards[egg] then return end
                    if egg.Parent then data.setPreviewModel(egg) end
                end)
            end
            egg.DescendantAdded:Connect(queueRefresh)
            egg.DescendantRemoving:Connect(queueRefresh)

            cards[egg] = data
            updateEmptyState()
            updateCardInfo(data, getCharacterPosition())
        end

        UserInputService.InputChanged:Connect(function(input)
            if not activeDrag then return end
            local ut = input.UserInputType
            if ut ~= Enum.UserInputType.MouseMovement and ut ~= Enum.UserInputType.Touch then return end
            local pos = pointerPos(input); local delta = pos - activeDrag.last; activeDrag.last = pos
            local d = activeDrag.data
            if activeDrag.mode == "rotate" then
                d.yaw = d.yaw - delta.X * 0.012
                d.pitch = math.clamp(d.pitch - delta.Y * 0.012, math.rad(-85), math.rad(85))
            else
                d.zoom = math.clamp(d.zoom + delta.Y * 0.012, CONFIG.ZoomMin, CONFIG.ZoomMax)
            end
            d.updateView()
        end)

        UserInputService.InputEnded:Connect(function(input)
            if not activeDrag then return end
            local ut = input.UserInputType
            if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.MouseButton2 or ut == Enum.UserInputType.Touch then activeDrag = nil end
        end)

        local eggFolder = nil; local folderConnections = {}
        local function clearFolderConnections()
            for _, c in ipairs(folderConnections) do if c.Connected then c:Disconnect() end end
            table.clear(folderConnections)
        end
        local function bindFolder(folder)
            clearFolderConnections()
            local oldEggs = {}; for egg in pairs(cards) do table.insert(oldEggs, egg) end
            for _, egg in ipairs(oldEggs) do removeCard(egg) end
            eggFolder = folder; cardCounter = 0
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Model") and child.Name == CONFIG.EggName then createCard(child) end
            end
            table.insert(folderConnections, folder.ChildAdded:Connect(function(child)
                if child:IsA("Model") and child.Name == CONFIG.EggName then createCard(child) end
            end))
            table.insert(folderConnections, folder.ChildRemoved:Connect(function(child)
                if cards[child] then removeCard(child) end
            end))
        end

        task.spawn(function()
            while gui.Parent do
                local dimension = Workspace:FindFirstChild(CONFIG.DimensionName)
                local folder = dimension and dimension:FindFirstChild(CONFIG.FolderName)
                if folder and folder ~= eggFolder then bindFolder(folder)
                elseif not folder and eggFolder then
                    local oldEggs = {}; for egg in pairs(cards) do table.insert(oldEggs, egg) end
                    for _, egg in ipairs(oldEggs) do removeCard(egg) end
                    clearFolderConnections(); eggFolder = nil; updateEmptyState()
                end
                task.wait(1)
            end
        end)

        task.spawn(function()
            while gui.Parent do
                task.wait(CONFIG.UpdateInterval)
                local myPos = getCharacterPosition(); local toRemove = nil
                for egg, data in pairs(cards) do
                    if not egg.Parent then
                        toRemove = toRemove or {}; table.insert(toRemove, egg)
                    else updateCardInfo(data, myPos) end
                end
                if toRemove then for _, egg in ipairs(toRemove) do removeCard(egg) end end
            end
        end)

        updateEmptyState()
    end

    tabBtn.MouseButton1Click:Connect(function()
        animatePress(tabBtn); playClick()
        if currentTab == i then return end
        for j, b in ipairs(tabButtons) do
            local bSt = b:FindFirstChildOfClass("UIStroke")
            if j == i then
                TweenService:Create(b, TweenInfo.new(0.25), {BackgroundColor3 = C.Accent}):Play()
                if bSt then TweenService:Create(bSt, TweenInfo.new(0.25), {Color = C.AccentHot, Thickness = 2, Transparency = 0}):Play() end
            else
                TweenService:Create(b, TweenInfo.new(0.25), {BackgroundColor3 = C.BgCard}):Play()
                if bSt then TweenService:Create(bSt, TweenInfo.new(0.25), {Color = C.Border, Thickness = 1, Transparency = 0.4}):Play() end
            end
        end
        contentFrames[currentTab].Visible = false
        contentFrames[i].Visible = true
        currentTab = i
    end)
end

-- ============ DRAG / MINIMIZE / CLOSE ============
local dragging, dragStart, startPos = false, nil, nil
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = panel.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local minimized = false
local fullSize = UDim2.new(0, 260, 0, 270)
local minSize  = UDim2.new(0, 260, 0, 42)
minBtn.MouseButton1Click:Connect(function()
    playClick(); animatePress(minBtn)
    minimized = not minimized
    TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = minimized and minSize or fullSize}):Play()
    content.Visible = not minimized
    sidebar.Visible = not minimized
    minBtn.Text = minimized and "+" or "—"
end)

closeBtn.MouseButton1Click:Connect(function()
    playClick(); animatePress(closeBtn)
    if Speed.Active then Speed:Stop() end
    if isBatActive then deactivateBat() end
    if isMusicPlaying then isMusicPlaying = false; musicSound:Stop(); restoreAll() end
    if isEggFarming then isEggFarming = false; if stopEggFarmFunc then stopEggFarmFunc() end; stopTeleport() end
    local centerPos = UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset + 130, panel.Position.Y.Scale, panel.Position.Y.Offset + 135)
    TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0), Position = centerPos}):Play()
    task.wait(0.3)
    gui:Destroy()
end)
