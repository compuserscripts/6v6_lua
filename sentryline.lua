-- Configuration
local CONFIG = {
    showLine = true,       -- Show aim line
    showBoxes = true,      -- Show boxes around sentries
    showChams = true,      -- Show chams on sentries targeting you
    showThroughWalls = true, -- Show ESP through walls
    lineColor = {r = 255, g = 0, b = 0, a = 255},  -- Red line
    lineLength = 1100,     -- Length of aim line in hammer units
    showFriendly = false,  -- Whether to show friendly sentry ESP
    
    -- Box settings
    useCorners = true,     -- Use corners instead of full box
    cornerLength = 10,     -- Length of corner lines
    boxThickness = 2       -- Thickness of box lines
}

-- Colors
local COLOR_SAFE = {0, 255, 0, 125}     -- Green when visible
local COLOR_DANGER = {255, 0, 0, 255}    -- Red when targeting player
local COLOR_HIDDEN = {150, 150, 150, 125} -- Grey when not visible

-- Pre-cache functions
local floor = math.floor
local unpack = unpack or table.unpack
local WorldToScreen = client.WorldToScreen
local Color = draw.Color
local Line = draw.Line
local OutlinedRect = draw.OutlinedRect

-- Track which sentries are targeting local player
local sentryTargetingLocal = {}

-- Create chams material
local chamsMaterial = materials.Create("sentry_chams", [[
    "VertexLitGeneric"
    {
        "$basetexture" "vgui/white_additive"
        "$bumpmap" "vgui/white_additive"
        "$color2" "[1 0 0]"
        "$selfillum" "1"
        "$ignorez" "1"
        "$model" "1"
        "$selfIllumFresnel" "1"
        "$selfIllumFresnelMinMaxExp" "[0.1 0.2 0.3]"
        "$selfillumtint" "[0.6 0 0]"
    }
]])

-- Helper function to check entity visibility
local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end

    local eyePos = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    if not eyePos then return false end

    -- Check visibility using center hitbox
    local hitboxes = entity:GetHitboxes()
    if hitboxes and hitboxes[1] then
        -- Get center of hitbox
        local hitboxPos = (hitboxes[1][1] + hitboxes[1][2]) * 0.5
        local trace = engine.TraceLine(eyePos, hitboxPos, MASK_SHOT_HULL)
        return trace.entity == entity
    end

    -- Fall back to origin-based check if hitboxes aren't available
    local targetPos = entity:GetAbsOrigin()
    if not targetPos then return false end
    
    local trace = engine.TraceLine(eyePos, targetPos, MASK_SHOT_HULL)
    return trace.entity == entity
end

-- Draw ESP box with corners
local function DrawESPBox(x1, y1, x2, y2, color)
    x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)
    
    if CONFIG.useCorners then
        local length = floor(CONFIG.cornerLength)
        length = floor(math.min(length, math.abs(x2 - x1) / 3, math.abs(y2 - y1) / 3))
        
        for i = 0, CONFIG.boxThickness do
            -- Top Left
            Line(x1, y1 + i, floor(x1 + length), y1 + i)
            Line(x1 + i, y1, x1 + i, floor(y1 + length))
            
            -- Top Right
            Line(floor(x2 - length), y1 + i, x2, y1 + i)
            Line(x2 - i, y1, x2 - i, floor(y1 + length))
            
            -- Bottom Left
            Line(x1, y2 - i, floor(x1 + length), y2 - i)
            Line(x1 + i, floor(y2 - length), x1 + i, y2)
            
            -- Bottom Right
            Line(floor(x2 - length), y2 - i, x2, y2 - i)
            Line(x2 - i, floor(y2 - length), x2 - i, y2)
        end
    else
        for i = 0, CONFIG.boxThickness do
            OutlinedRect(x1 - i, y1 - i, x2 + i, y2 + i)
        end
    end
end

-- Helper function to get position from bone matrix
local function GetPositionFromMatrix(matrix)
    return Vector3(
        matrix[1][4],
        matrix[2][4],
        matrix[3][4]
    )
end

-- Helper function to get angles from bone matrix
local function GetAnglesFromMatrix(matrix)
    local forward = Vector3(matrix[1][3], matrix[2][3], matrix[3][3])
    return forward:Angles()
end

-- Helper function to get sentry muzzle position and angles
local function GetSentryAimData(sentry)
    local boneMatrices = sentry:SetupBones()
    if not boneMatrices then return nil, nil end
    
    local level = sentry:GetPropInt("m_iUpgradeLevel") or 0
    local turretBoneIndex = 1
    
    if level == 1 then
        turretBoneIndex = 2
    elseif level == 2 then
        turretBoneIndex = 3
    end
    
    local turretMatrix = boneMatrices[turretBoneIndex]
    if not turretMatrix then return nil, nil end
    
    local muzzlePos = GetPositionFromMatrix(turretMatrix)
    local aimAngles = GetAnglesFromMatrix(turretMatrix)
    
    local target = sentry:GetPropEntity("m_hEnemy")
    if target and target:IsValid() and not target:IsDormant() then
        local targetPos = target:GetAbsOrigin()
        if targetPos then
            targetPos.z = targetPos.z + 40
            local direction = targetPos - muzzlePos
            aimAngles = direction:Angles()
        end
    end
    
    return muzzlePos, aimAngles, target
end

-- Helper function to get end position of aim line
local function GetAimLineEndPos(startPos, angles)
    if not startPos or not angles then return nil end
    local forward = angles:Forward()
    return startPos + (forward * CONFIG.lineLength)
end

local function OnDraw()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    -- Clear the targeting table each frame
    for k in pairs(sentryTargetingLocal) do
        sentryTargetingLocal[k] = nil
    end
    
    local sentries = entities.FindByClass("CObjectSentrygun")
    for _, sentry in pairs(sentries) do
        if not sentry:IsValid() or sentry:IsDormant() then goto continue end
        if sentry:GetPropBool("m_bBuilding") then goto continue end
        if not CONFIG.showFriendly and sentry:GetTeamNumber() == localPlayer:GetTeamNumber() then 
            goto continue 
        end
        
        local muzzlePos, angles, target = GetSentryAimData(sentry)
        if not muzzlePos or not angles then goto continue end
        
        -- Check if sentry is targeting local player
        local isTargetingLocal = target and target:IsValid() and target:GetIndex() == localPlayer:GetIndex()
        if isTargetingLocal then
            sentryTargetingLocal[sentry:GetIndex()] = true
        end

        -- Draw box if enabled
        if CONFIG.showBoxes then
            local pos = sentry:GetAbsOrigin()
            local mins = sentry:GetMins()
            local maxs = sentry:GetMaxs()

            if pos and mins and maxs then
                local bottomPos = Vector3(pos.x, pos.y, pos.z + mins.z)
                local topPos = Vector3(pos.x, pos.y, pos.z + maxs.z)
                
                local screenBottom = WorldToScreen(bottomPos)
                local screenTop = WorldToScreen(topPos)
                
                if screenBottom and screenTop then
                    local height = screenBottom[2] - screenTop[2]
                    local width = height * 0.75
                    
                    local x1 = floor(screenBottom[1] - width / 2)
                    local y1 = floor(screenTop[2])
                    local x2 = floor(screenBottom[1] + width / 2)
                    local y2 = floor(screenBottom[2])
                    
                    local isActuallyVisible = IsVisible(sentry, localPlayer)

                    -- If we're not showing through walls and sentry isn't visible, skip drawing
                    if not CONFIG.showThroughWalls and not isActuallyVisible then 
                        goto continue 
                    end
                    
                    -- Determine color based on visibility and targeting
                    local color
                    if not isActuallyVisible then
                        color = COLOR_HIDDEN
                    else
                        color = isTargetingLocal and COLOR_DANGER or COLOR_SAFE
                    end
                    
                    Color(unpack(color))
                    DrawESPBox(x1, y1, x2, y2, color)
                end
            end
        end
        
        if CONFIG.showLine then
            local endPos = GetAimLineEndPos(muzzlePos, angles)
            if not endPos then goto continue end
            
            local startScreen = WorldToScreen(muzzlePos)
            local endScreen = WorldToScreen(endPos)
            
            if startScreen and endScreen then
                Color(CONFIG.lineColor.r, CONFIG.lineColor.g, CONFIG.lineColor.b, CONFIG.lineColor.a)
                Line(startScreen[1], startScreen[2], endScreen[1], endScreen[2])
            end
        end
        
        ::continue::
    end
end

-- Chams function for sentries
local function OnDrawModel(ctx)
    if not CONFIG.showChams then return end

    local entity = ctx:GetEntity()
    if not entity then return end
    
    -- Only apply chams to sentries targeting local player
    if entity:GetClass() == "CObjectSentrygun" and sentryTargetingLocal[entity:GetIndex()] then
        ctx:ForcedMaterialOverride(chamsMaterial)
    end
end

-- Clean up on script unload
callbacks.Register("Unload", function()
    for k in pairs(sentryTargetingLocal) do
        sentryTargetingLocal[k] = nil
    end
    chamsMaterial = nil
end)

-- Register callbacks
callbacks.Register("Draw", "SentryAimline", OnDraw)
callbacks.Register("DrawModel", "SentryChams", OnDrawModel)
