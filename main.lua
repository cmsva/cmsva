--[[
    DonchoigameHub - Client
    Đặt LocalScript này trong StarterPlayer > StarterPlayerScripts.

    Tính năng:
    - Fix Lag mạnh (có thể hoàn tác)
    - ESP người chơi khác
    - ESP quái/NPC
    - Speed tùy chỉnh (client-side)
    - Auto Farm theo tag/attribute do game định nghĩa
    - Flycam cho máy tính và điện thoại
    - Fullbright/Night Vision (có thể hoàn tác)
    - JumpBoost (client-side)
    - Nút hướng dẫn đến Social Links của trang game
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("DonchoigameHub")
if oldGui then
    oldGui:Destroy()
end

local staleNightVision = Lighting:FindFirstChild("DonchoigameHubNightVision")
if staleNightVision and staleNightVision:GetAttribute("DonchoigameHubKeep") then
    staleNightVision:Destroy()
end

local state = {
    FixLag = false,
    ESP = false,
    MonsterESP = false,
    Speed = false,
    AutoFarm = false,
    Flycam = false,
    Fullbright = false,
    JumpBoost = false,
}

-- Giới hạn điều chỉnh Speed và sức mạnh của JumpBoost.
local MIN_WALK_SPEED = 8
local MAX_WALK_SPEED = 120
local SPEED_STEP = 4
local selectedWalkSpeed = 32
local BOOST_JUMP_POWER = 85
local BOOST_JUMP_HEIGHT = 14

-- Mục tiêu Auto Farm: gắn tag FarmTarget hoặc attribute IsFarmTarget=true.
local AUTO_FARM_TAG = "FarmTarget"
local AUTO_FARM_ATTRIBUTE = "IsFarmTarget"
local AUTO_FARM_REACH_DISTANCE = 6
local AUTO_FARM_MOVE_TIMEOUT = 8
local AUTO_FARM_TARGET_COOLDOWN = 1

local COLORS = {
    Background = Color3.fromRGB(13, 17, 28),
    Panel = Color3.fromRGB(20, 26, 42),
    PanelHover = Color3.fromRGB(27, 35, 56),
    Stroke = Color3.fromRGB(52, 65, 91),
    Text = Color3.fromRGB(241, 245, 255),
    Muted = Color3.fromRGB(151, 163, 188),
    Accent = Color3.fromRGB(82, 124, 255),
    Accent2 = Color3.fromRGB(134, 82, 255),
    On = Color3.fromRGB(49, 209, 139),
    Off = Color3.fromRGB(78, 88, 110),
}

local function addCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
    return corner
end

local function addStroke(instance, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency or 0
    stroke.Parent = instance
    return stroke
end

local function notify(title, text)
    task.spawn(function()
        for _ = 1, 5 do
            local success = pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = title,
                    Text = text,
                    Duration = 6,
                })
            end)
            if success then
                return
            end
            task.wait(0.35)
        end
    end)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DonchoigameHub"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 50
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Điều khiển cảm ứng của Flycam
local mobileControls = Instance.new("Frame")
mobileControls.Name = "FlycamMobileControls"
mobileControls.AnchorPoint = Vector2.new(0.5, 1)
mobileControls.Position = UDim2.new(0.5, 0, 1, -24)
mobileControls.Size = UDim2.fromOffset(270, 116)
mobileControls.BackgroundTransparency = 1
mobileControls.Visible = false
mobileControls.ZIndex = 30
mobileControls.Parent = screenGui

local flyMove = {
    Forward = false,
    Backward = false,
    Left = false,
    Right = false,
    Up = false,
    Down = false,
    Boost = false,
}

local function makeFlyButton(text, position, moveName)
    local button = Instance.new("TextButton")
    button.Name = moveName
    button.Position = position
    button.Size = UDim2.fromOffset(52, 52)
    button.BackgroundColor3 = COLORS.Panel
    button.BackgroundTransparency = 0.12
    button.Text = text
    button.TextColor3 = COLORS.Text
    button.TextSize = 22
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = false
    button.ZIndex = 31
    button.Parent = mobileControls
    addCorner(button, 15)
    addStroke(button, COLORS.Stroke, 1, 0.15)

    local function setPressed(pressed)
        flyMove[moveName] = pressed
        TweenService:Create(
            button,
            TweenInfo.new(0.1),
            {
                BackgroundColor3 = pressed and COLORS.Accent or COLORS.Panel,
                BackgroundTransparency = pressed and 0 or 0.12,
            }
        ):Play()
    end

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        then
            setPressed(true)
        end
    end)

    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1
        then
            setPressed(false)
        end
    end)

    return button
end

makeFlyButton("▲", UDim2.fromOffset(58, 0), "Forward")
makeFlyButton("◀", UDim2.fromOffset(0, 58), "Left")
makeFlyButton("▼", UDim2.fromOffset(58, 58), "Backward")
makeFlyButton("▶", UDim2.fromOffset(116, 58), "Right")
makeFlyButton("+", UDim2.fromOffset(208, 0), "Up")
makeFlyButton("−", UDim2.fromOffset(208, 58), "Down")

local applyFullbright
local postEffectOriginals = {}

local function applyPostEffectPolicy()
    local shouldDisable = state.FixLag or state.Fullbright

    for instance in postEffectOriginals do
        if not instance or not instance.Parent then
            postEffectOriginals[instance] = nil
        end
    end

    for _, instance in Lighting:GetDescendants() do
        if instance:IsA("PostEffect") and not instance:GetAttribute("DonchoigameHubKeep") then
            if shouldDisable then
                if not postEffectOriginals[instance] then
                    postEffectOriginals[instance] = {
                        Enabled = instance.Enabled,
                    }
                end
                instance.Enabled = false
            else
                local original = postEffectOriginals[instance]
                if original then
                    instance.Enabled = original.Enabled
                    postEffectOriginals[instance] = nil
                end
            end
        end
    end
end

-- Fix Lag
local lagOriginals = {}
local lagConnections = {}
local lagGeneration = 0

local function rememberAndSet(instance, propertyName, newValue)
    local originals = lagOriginals[instance]
    if not originals then
        originals = {}
        lagOriginals[instance] = originals
    end

    if originals[propertyName] == nil then
        local success, oldValue = pcall(function()
            return instance[propertyName]
        end)
        if not success then
            return
        end

        originals[propertyName] = {
            Value = oldValue,
        }
    end

    pcall(function()
        instance[propertyName] = newValue
    end)
end

local function belongsToHumanoidModel(instance)
    local model = instance:FindFirstAncestorOfClass("Model")
    return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function reduceInstance(instance)
    if not state.FixLag then
        return
    end

    if instance:GetAttribute("DonchoigameHubKeep") then
        return
    end

    if instance:IsA("PostEffect") then
        applyPostEffectPolicy()
        return
    end

    if instance:IsA("ParticleEmitter")
        or instance:IsA("Trail")
        or instance:IsA("Beam")
        or instance:IsA("Smoke")
        or instance:IsA("Fire")
        or instance:IsA("Sparkles")
    then
        rememberAndSet(instance, "Enabled", false)
        return
    end

    if instance:IsA("BasePart") then
        rememberAndSet(instance, "CastShadow", false)
        rememberAndSet(instance, "Reflectance", 0)

        -- Giữ vật liệu nhân vật/NPC để avatar không bị biến dạng.
        if not belongsToHumanoidModel(instance) then
            rememberAndSet(instance, "Material", Enum.Material.SmoothPlastic)
        end
        return
    end

    if instance:IsA("Decal") or instance:IsA("Texture") then
        if not belongsToHumanoidModel(instance) then
            rememberAndSet(instance, "Transparency", 1)
        end
        return
    end

    if instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight")
    then
        rememberAndSet(instance, "Shadows", false)
        return
    end

    if instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
        rememberAndSet(instance, "Enabled", false)
        return
    end

    if instance:IsA("Terrain") then
        rememberAndSet(instance, "WaterWaveSize", 0)
        rememberAndSet(instance, "WaterWaveSpeed", 0)
        rememberAndSet(instance, "WaterReflectance", 0)
    end
end

local function setFixLag(enabled)
    lagGeneration += 1
    local thisGeneration = lagGeneration

    for _, connection in lagConnections do
        connection:Disconnect()
    end
    table.clear(lagConnections)

    if enabled then
        table.insert(lagConnections, workspace.DescendantAdded:Connect(reduceInstance))
        table.insert(lagConnections, Lighting.DescendantAdded:Connect(reduceInstance))

        task.spawn(function()
            local descendants = workspace:GetDescendants()
            for index, instance in descendants do
                if not state.FixLag or lagGeneration ~= thisGeneration then
                    return
                end
                reduceInstance(instance)
                if index % 250 == 0 then
                    RunService.Heartbeat:Wait()
                end
            end

            for _, instance in Lighting:GetDescendants() do
                if not state.FixLag or lagGeneration ~= thisGeneration then
                    return
                end
                reduceInstance(instance)
            end
        end)
    else
        for instance, originals in lagOriginals do
            if instance and instance.Parent then
                for propertyName, original in originals do
                    pcall(function()
                        instance[propertyName] = original.Value
                    end)
                end
            end
        end
        table.clear(lagOriginals)

        if state.Fullbright then
            task.defer(function()
                applyFullbright()
            end)
        end
    end

    applyPostEffectPolicy()
end

-- ESP
local espObjects = {}
local espCharacterConnections = {}

local function clearESP(player)
    local entry = espObjects[player]
    if not entry then
        return
    end

    if entry.Highlight then
        entry.Highlight:Destroy()
    end
    if entry.Billboard then
        entry.Billboard:Destroy()
    end
    espObjects[player] = nil
end

local function getESPColor(player)
    if player.Team then
        return player.TeamColor.Color
    end
    return Color3.fromRGB(72, 211, 255)
end

local function createESP(player)
    if player == localPlayer or not state.ESP then
        return
    end

    clearESP(player)

    local character = player.Character
    if not character then
        return
    end

    local head = character:FindFirstChild("Head")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not head or not root then
        return
    end

    local color = getESPColor(player)

    local highlight = Instance.new("Highlight")
    highlight.Name = "DonchoigameESP"
    highlight.Adornee = character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.FillTransparency = 0.72
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = 0.08
    highlight.Parent = character

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DonchoigameESPTag"
    billboard.Adornee = head
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 10000
    billboard.Size = UDim2.fromOffset(190, 30)
    billboard.StudsOffset = Vector3.new(0, 2.7, 0)
    billboard.Parent = screenGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = player.DisplayName
    label.TextColor3 = color
    label.TextSize = 14
    label.Font = Enum.Font.GothamSemibold
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.25
    label.Parent = billboard

    espObjects[player] = {
        Highlight = highlight,
        Billboard = billboard,
        Label = label,
        Root = root,
    }
end

local function watchPlayerForESP(player)
    if player == localPlayer or espCharacterConnections[player] then
        return
    end

    espCharacterConnections[player] = player.CharacterAdded:Connect(function(character)
        if not state.ESP then
            return
        end
        character:WaitForChild("HumanoidRootPart", 8)
        character:WaitForChild("Head", 8)
        createESP(player)
    end)

    if state.ESP then
        createESP(player)
    end
end

local function setESP(enabled)
    if enabled then
        for _, player in Players:GetPlayers() do
            watchPlayerForESP(player)
            createESP(player)
        end
    else
        for player in espObjects do
            clearESP(player)
        end
    end
end

Players.PlayerAdded:Connect(watchPlayerForESP)
Players.PlayerRemoving:Connect(function(player)
    clearESP(player)
    local connection = espCharacterConnections[player]
    if connection then
        connection:Disconnect()
        espCharacterConnections[player] = nil
    end
end)

for _, player in Players:GetPlayers() do
    watchPlayerForESP(player)
end

local espTimer = 0
RunService.Heartbeat:Connect(function(deltaTime)
    if not state.ESP then
        return
    end

    espTimer += deltaTime
    if espTimer < 0.15 then
        return
    end
    espTimer = 0

    local character = localPlayer.Character
    local localRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        return
    end

    for player, entry in espObjects do
        if entry.Root and entry.Root.Parent and entry.Label then
            local distance = (entry.Root.Position - localRoot.Position).Magnitude
            local color = getESPColor(player)
            entry.Label.Text = string.format("%s  •  %dm", player.DisplayName, math.floor(distance + 0.5))
            entry.Label.TextColor3 = color
            entry.Highlight.FillColor = color
        else
            createESP(player)
        end
    end
end)

-- ESP quái/NPC
local MONSTER_COLOR = Color3.fromRGB(255, 91, 91)
local monsterESPObjects = {}
local monsterScanGeneration = 0

local function isMonsterModel(model)
    if not model:IsA("Model") or not model:IsDescendantOf(workspace) then
        return false
    end

    if Players:GetPlayerFromCharacter(model) then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end

    -- Attribute false dùng để loại trừ NPC thân thiện khỏi chế độ tự nhận diện.
    if model:GetAttribute("IsMonster") == false then
        return false
    end

    -- Tag Monster hoặc attribute IsMonster=true luôn được ưu tiên.
    if model:GetAttribute("IsMonster") == true or CollectionService:HasTag(model, "Monster") then
        return true
    end

    -- Fallback: mọi model có Humanoid nhưng không phải nhân vật người chơi.
    return true
end

local function clearMonsterESP(model)
    local entry = monsterESPObjects[model]
    if not entry then
        return
    end

    if entry.DiedConnection then
        entry.DiedConnection:Disconnect()
    end
    if entry.AncestryConnection then
        entry.AncestryConnection:Disconnect()
    end
    if entry.Highlight then
        entry.Highlight:Destroy()
    end
    if entry.Billboard then
        entry.Billboard:Destroy()
    end

    monsterESPObjects[model] = nil
end

local function createMonsterESP(model)
    if not state.MonsterESP or not isMonsterModel(model) then
        return
    end

    local current = monsterESPObjects[model]
    if current and current.Root and current.Root.Parent then
        return
    end
    clearMonsterESP(model)

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
    local head = model:FindFirstChild("Head", true) or root
    if not humanoid or not root or not head then
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "DonchoigameMonsterESP"
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = MONSTER_COLOR
    highlight.FillTransparency = 0.64
    highlight.OutlineColor = Color3.fromRGB(255, 228, 174)
    highlight.OutlineTransparency = 0.04
    highlight.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DonchoigameMonsterESPTag"
    billboard.Adornee = head
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 10000
    billboard.Size = UDim2.fromOffset(220, 34)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.Parent = screenGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = model.Name
    label.TextColor3 = MONSTER_COLOR
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.18
    label.Parent = billboard

    local entry = {
        Highlight = highlight,
        Billboard = billboard,
        Label = label,
        Root = root,
        Humanoid = humanoid,
    }
    monsterESPObjects[model] = entry

    entry.DiedConnection = humanoid.Died:Connect(function()
        clearMonsterESP(model)
    end)
    entry.AncestryConnection = model.AncestryChanged:Connect(function()
        if not model:IsDescendantOf(workspace) then
            clearMonsterESP(model)
        end
    end)
end

local function findMonsterModel(instance)
    if instance:IsA("Model") then
        return instance
    end
    return instance:FindFirstAncestorOfClass("Model")
end

local function setMonsterESP(enabled)
    monsterScanGeneration += 1
    local thisGeneration = monsterScanGeneration

    if enabled then
        task.spawn(function()
            local descendants = workspace:GetDescendants()
            for index, instance in descendants do
                if not state.MonsterESP or monsterScanGeneration ~= thisGeneration then
                    return
                end

                if instance:IsA("Model") then
                    createMonsterESP(instance)
                end

                if index % 200 == 0 then
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    else
        local modelsToClear = {}
        for model in monsterESPObjects do
            table.insert(modelsToClear, model)
        end
        for _, model in modelsToClear do
            clearMonsterESP(model)
        end
    end
end

workspace.DescendantAdded:Connect(function(instance)
    if not state.MonsterESP then
        return
    end

    task.defer(function()
        local model = findMonsterModel(instance)
        if model then
            createMonsterESP(model)
        end
    end)
end)

local monsterESPTimer = 0
RunService.Heartbeat:Connect(function(deltaTime)
    if not state.MonsterESP then
        return
    end

    monsterESPTimer += deltaTime
    if monsterESPTimer < 0.15 then
        return
    end
    monsterESPTimer = 0

    local character = localPlayer.Character
    local localRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not localRoot then
        return
    end

    local modelsToRefresh = {}
    for model, entry in monsterESPObjects do
        if entry.Root
            and entry.Root.Parent
            and entry.Humanoid
            and entry.Humanoid.Parent
            and entry.Humanoid.Health > 0
        then
            local distance = (entry.Root.Position - localRoot.Position).Magnitude
            local health = math.max(0, math.floor(entry.Humanoid.Health + 0.5))
            local displayName = entry.Humanoid.DisplayName
            if displayName == "" then
                displayName = model.Name
            end
            entry.Label.Text = string.format(
                "%s  •  %dm  •  %d HP",
                displayName,
                math.floor(distance + 0.5),
                health
            )
        else
            table.insert(modelsToRefresh, model)
        end
    end

    for _, model in modelsToRefresh do
        clearMonsterESP(model)
        if model and model.Parent then
            createMonsterESP(model)
        end
    end
end)

-- Speed và JumpBoost hoàn toàn client-side
local movementDefaults = nil

local function rememberMovementDefaults(humanoid)
    movementDefaults = {
        Humanoid = humanoid,
        WalkSpeed = humanoid.WalkSpeed,
        UseJumpPower = humanoid.UseJumpPower,
        JumpPower = humanoid.JumpPower,
        JumpHeight = humanoid.JumpHeight,
    }
end

local function applyClientMovement()
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    if not movementDefaults or movementDefaults.Humanoid ~= humanoid then
        rememberMovementDefaults(humanoid)
    end

    humanoid.WalkSpeed = state.Speed and selectedWalkSpeed or movementDefaults.WalkSpeed

    if humanoid.UseJumpPower then
        humanoid.JumpPower = state.JumpBoost and BOOST_JUMP_POWER or movementDefaults.JumpPower
    else
        humanoid.JumpHeight = state.JumpBoost and BOOST_JUMP_HEIGHT or movementDefaults.JumpHeight
    end
end

localPlayer.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then
        return
    end

    rememberMovementDefaults(humanoid)
    applyClientMovement()
end)

if localPlayer.Character then
    local currentCharacter = localPlayer.Character
    task.spawn(function()
        local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
            or currentCharacter:WaitForChild("Humanoid", 10)
        if humanoid then
            rememberMovementDefaults(humanoid)
            applyClientMovement()
        end
    end)
end

-- Một số controller đặt lại WalkSpeed sau khi menu vừa chỉnh.
-- Duy trì giá trị trong lúc bật để Speed/JumpBoost không bị mất hiệu lực.
RunService.Heartbeat:Connect(function()
    if not state.Speed and not state.JumpBoost then
        return
    end

    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    if not movementDefaults or movementDefaults.Humanoid ~= humanoid then
        rememberMovementDefaults(humanoid)
    end

    if state.Speed and humanoid.WalkSpeed ~= selectedWalkSpeed then
        humanoid.WalkSpeed = selectedWalkSpeed
    end

    if state.JumpBoost then
        if humanoid.UseJumpPower and humanoid.JumpPower ~= BOOST_JUMP_POWER then
            humanoid.JumpPower = BOOST_JUMP_POWER
        elseif not humanoid.UseJumpPower and humanoid.JumpHeight ~= BOOST_JUMP_HEIGHT then
            humanoid.JumpHeight = BOOST_JUMP_HEIGHT
        end
    end
end)

-- Fullbright
local fullbrightSnapshot = nil
local fullbrightConnection = nil
local fullbrightTimer = 0
local fullbrightAtmosphereSnapshots = {}
local nightVisionEffect = nil

applyFullbright = function()
    -- Giữ nguyên ClockTime để bầu trời vẫn là ban đêm, chỉ nâng ánh sáng môi trường.
    Lighting.Brightness = 3
    Lighting.FogStart = 0
    Lighting.FogEnd = 1000000
    Lighting.Ambient = Color3.fromRGB(205, 205, 215)
    Lighting.OutdoorAmbient = Color3.fromRGB(190, 195, 210)
    Lighting.GlobalShadows = false
    Lighting.ExposureCompensation = 0.18
    Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
    Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
    Lighting.EnvironmentDiffuseScale = 1
    Lighting.EnvironmentSpecularScale = 0.2
    Lighting.ShadowSoftness = 0

    for _, instance in Lighting:GetDescendants() do
        if instance:IsA("Atmosphere") then
            if not fullbrightAtmosphereSnapshots[instance] then
                fullbrightAtmosphereSnapshots[instance] = {
                    Density = instance.Density,
                    Offset = instance.Offset,
                    Haze = instance.Haze,
                    Glare = instance.Glare,
                }
            end

            instance.Density = 0
            instance.Offset = 0
            instance.Haze = 0
            instance.Glare = 0
        end
    end

    if not nightVisionEffect or not nightVisionEffect.Parent then
        nightVisionEffect = Instance.new("ColorCorrectionEffect")
        nightVisionEffect.Name = "DonchoigameHubNightVision"
        nightVisionEffect:SetAttribute("DonchoigameHubKeep", true)
        nightVisionEffect.Brightness = 0.07
        nightVisionEffect.Contrast = 0.06
        nightVisionEffect.Saturation = -0.04
        nightVisionEffect.TintColor = Color3.fromRGB(255, 250, 240)
        nightVisionEffect.Parent = Lighting
    end
    nightVisionEffect.Enabled = true
    applyPostEffectPolicy()
end

local function setFullbright(enabled)
    if fullbrightConnection then
        fullbrightConnection:Disconnect()
        fullbrightConnection = nil
    end

    if enabled then
        fullbrightSnapshot = {
            Brightness = Lighting.Brightness,
            FogStart = Lighting.FogStart,
            FogEnd = Lighting.FogEnd,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            GlobalShadows = Lighting.GlobalShadows,
            ExposureCompensation = Lighting.ExposureCompensation,
            ColorShift_Top = Lighting.ColorShift_Top,
            ColorShift_Bottom = Lighting.ColorShift_Bottom,
            EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
            ShadowSoftness = Lighting.ShadowSoftness,
        }

        applyFullbright()
        fullbrightTimer = 0
        fullbrightConnection = RunService.Heartbeat:Connect(function(deltaTime)
            fullbrightTimer += deltaTime
            if fullbrightTimer >= 0.5 then
                fullbrightTimer = 0
                applyFullbright()
            end
        end)
    elseif fullbrightSnapshot then
        for propertyName, value in fullbrightSnapshot do
            Lighting[propertyName] = value
        end
        fullbrightSnapshot = nil

        for atmosphere, snapshot in fullbrightAtmosphereSnapshots do
            if atmosphere and atmosphere.Parent then
                for propertyName, value in snapshot do
                    atmosphere[propertyName] = value
                end
            end
        end
        table.clear(fullbrightAtmosphereSnapshots)

        if nightVisionEffect then
            nightVisionEffect:Destroy()
            nightVisionEffect = nil
        end

        applyPostEffectPolicy()

        if state.FixLag then
            task.defer(function()
                for _, instance in Lighting:GetDescendants() do
                    reduceInstance(instance)
                end
            end)
        end
    end
end

-- Flycam
local FLYCAM_SPEED = 55
local FLYCAM_BOOST_MULTIPLIER = 2.5
local FLYCAM_LOOK_SENSITIVITY = 0.0035
local FLYCAM_RENDER_NAME = "DonchoigameHubFlycam"

local mainFrame
local launcherButton
local savedCamera
local flyPosition = Vector3.zero
local flyYaw = 0
local flyPitch = 0
local rotatingMouse = false
local lookTouch = nil
local lastTouchPosition = nil
local playerControls = nil

local keyboardMap = {
    [Enum.KeyCode.W] = "Forward",
    [Enum.KeyCode.S] = "Backward",
    [Enum.KeyCode.A] = "Left",
    [Enum.KeyCode.D] = "Right",
    [Enum.KeyCode.E] = "Up",
    [Enum.KeyCode.Q] = "Down",
}

local function clearFlyInput()
    for moveName in flyMove do
        flyMove[moveName] = false
    end
    rotatingMouse = false
    lookTouch = nil
    lastTouchPosition = nil
end

local function rotateFlycam(delta)
    flyYaw -= delta.X * FLYCAM_LOOK_SENSITIVITY
    flyPitch = math.clamp(
        flyPitch - delta.Y * FLYCAM_LOOK_SENSITIVITY,
        math.rad(-85),
        math.rad(85)
    )
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not state.Flycam then
        return
    end

    local moveName = keyboardMap[input.KeyCode]
    if moveName and not gameProcessed then
        flyMove[moveName] = true
        return
    end

    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        flyMove.Boost = true
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton2 and not gameProcessed then
        rotatingMouse = true
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        return
    end

    if input.UserInputType == Enum.UserInputType.Touch and not gameProcessed then
        local camera = workspace.CurrentCamera
        local viewportWidth = camera and camera.ViewportSize.X or 0
        if input.Position.X > viewportWidth * 0.42 then
            lookTouch = input
            lastTouchPosition = Vector2.new(input.Position.X, input.Position.Y)
        end
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not state.Flycam then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseMovement and rotatingMouse then
        rotateFlycam(input.Delta)
    elseif input.UserInputType == Enum.UserInputType.Touch and input == lookTouch then
        local position = Vector2.new(input.Position.X, input.Position.Y)
        if lastTouchPosition then
            rotateFlycam(position - lastTouchPosition)
        end
        lastTouchPosition = position
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local moveName = keyboardMap[input.KeyCode]
    if moveName then
        flyMove[moveName] = false
    end

    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        flyMove.Boost = false
    end

    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rotatingMouse = false
        if state.Flycam then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    end

    if input == lookTouch then
        lookTouch = nil
        lastTouchPosition = nil
    end
end)

UserInputService.WindowFocusReleased:Connect(clearFlyInput)

local function getPlayerControls()
    if playerControls then
        return playerControls
    end

    local success, result = pcall(function()
        local playerModule = require(localPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
        return playerModule:GetControls()
    end)

    if success then
        playerControls = result
    end
    return playerControls
end

local function updatePlayerControlState()
    local controls = getPlayerControls()
    if not controls then
        return
    end

    if state.Flycam or state.AutoFarm then
        controls:Disable()
    else
        controls:Enable()
    end
end

local function updateFlycam(deltaTime)
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local x = (flyMove.Right and 1 or 0) - (flyMove.Left and 1 or 0)
    local y = (flyMove.Up and 1 or 0) - (flyMove.Down and 1 or 0)
    local z = (flyMove.Backward and 1 or 0) - (flyMove.Forward and 1 or 0)
    local localDirection = Vector3.new(x, y, z)

    local rotation = CFrame.Angles(0, flyYaw, 0) * CFrame.Angles(flyPitch, 0, 0)
    if localDirection.Magnitude > 0 then
        local speed = FLYCAM_SPEED
        if flyMove.Boost then
            speed *= FLYCAM_BOOST_MULTIPLIER
        end
        flyPosition += rotation:VectorToWorldSpace(localDirection.Unit) * speed * deltaTime
    end

    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = CFrame.new(flyPosition) * rotation
end

local function setFlycam(enabled)
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    RunService:UnbindFromRenderStep(FLYCAM_RENDER_NAME)
    clearFlyInput()

    if enabled then
        savedCamera = {
            CameraType = camera.CameraType,
            CameraSubject = camera.CameraSubject,
            CFrame = camera.CFrame,
            FieldOfView = camera.FieldOfView,
            MouseBehavior = UserInputService.MouseBehavior,
            MouseIconEnabled = UserInputService.MouseIconEnabled,
        }

        flyPosition = camera.CFrame.Position
        local pitch, yaw = camera.CFrame:ToOrientation()
        flyPitch = pitch
        flyYaw = yaw

        camera.CameraType = Enum.CameraType.Scriptable
        mobileControls.Visible = UserInputService.TouchEnabled
        RunService:BindToRenderStep(
            FLYCAM_RENDER_NAME,
            Enum.RenderPriority.Camera.Value + 1,
            updateFlycam
        )

        if mainFrame and launcherButton then
            mainFrame.Visible = false
            launcherButton.Visible = true
        end
    else
        mobileControls.Visible = false

        if savedCamera then
            camera.CameraType = savedCamera.CameraType
            camera.FieldOfView = savedCamera.FieldOfView
            camera.CFrame = savedCamera.CFrame

            if savedCamera.CameraSubject and savedCamera.CameraSubject.Parent then
                camera.CameraSubject = savedCamera.CameraSubje
