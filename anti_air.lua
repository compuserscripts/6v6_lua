-- Configuration
local CONFIG = {
    showTracers = true,
    showBoxes = true,
    showChams = false,
    tracerOnlyWhenNotVisible = false,
    boxOnlyWhenNotVisible = false,
    chamsOnlyWhenNotVisible = false,
    
    -- Box settings
    useCorners = true,  -- Use corners instead of full box
    cornerLength = 10,  -- Length of corner lines
    boxThickness = 2,   -- Thickness of box lines
}

-- Constants
local SOLDIER_CLASS = 3
local BLAST_JUMPING_COND = 81
local MAX_DISTANCE_SQR = 3500 * 3500
local CLEANUP_INTERVAL = 0.5  -- Clean every 500ms

-- Colors
local COLOR_VISIBLE = {0, 255, 0, 125}
local COLOR_HIDDEN = {255, 0, 0, 255}
local COLOR_TRACER = {255, 0, 255, 255}

-- Pre-cache functions
local floor = math.floor
local unpack = unpack or table.unpack
local RealTime = globals.RealTime
local WorldToScreen = client.WorldToScreen
local TraceLine = engine.TraceLine
local GetScreenSize = draw.GetScreenSize
local Color = draw.Color
local Line = draw.Line
local OutlinedRect = draw.OutlinedRect

-- State tracking
local lastLifeState = 2  -- Start with LIFE_DEAD (2)
local nextCleanupTime = 0
local trackedPlayers = {}

-- Chams material
local chamsMaterial = materials.Create("soldier_chams", [[
    "VertexLitGeneric"
    {
        "$basetexture" "vgui/white_additive"
        "$bumpmap" "vgui/white_additive"
        "$color2" "[100 0.5 0.5]"
        "$selfillum" "1"
        "$ignorez" "1"
        "$selfIllumFresnel" "1"
        "$selfIllumFresnelMinMaxExp" "[0.1 0.2 0.3]"
        "$selfillumtint" "[0 0.3 0.6]"
    }
]])

-- Improved visibility checking function
local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end

    -- Get eye position for more accurate tracing
    local eyePos = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = entity:GetAbsOrigin()
    if not eyePos or not targetPos then return false end

    -- Use appropriate mask based on team
    local isTeammate = entity:GetTeamNumber() == localPlayer:GetTeamNumber()
    local mask = isTeammate and MASK_SHOT_HULL or MASK_VISIBLE
    
    -- Perform trace
    local trace = engine.TraceLine(eyePos, targetPos, mask)
    
    -- Different handling for teammates vs enemies
    if isTeammate then
        return trace.fraction > 0.97 -- More lenient check for teammates
    else
        return trace.entity == entity -- Must hit the exact entity for enemies
    end
end

-- Draw ESP box with corners, handling perspective correctly
local function DrawESPBox(x1, y1, x2, y2, isVisible)
    -- Convert all coordinates to integers
    x1 = floor(x1)
    y1 = floor(y1)
    x2 = floor(x2)
    y2 = floor(y2)
    
    Color(unpack(isVisible and COLOR_VISIBLE or COLOR_HIDDEN))
    
    if CONFIG.useCorners then
        local length = floor(CONFIG.cornerLength)
        
        -- Ensure corner length doesn't exceed box dimensions
        length = floor(math.min(length, math.abs(x2 - x1) / 3, math.abs(y2 - y1) / 3))
        
        for i = 0, CONFIG.boxThickness do
            -- Top Left
            Line(x1, y1 + i, floor(x1 + length), y1 + i)  -- Horizontal
            Line(x1 + i, y1, x1 + i, floor(y1 + length))  -- Vertical
            
            -- Top Right
            Line(floor(x2 - length), y1 + i, x2, y1 + i)  -- Horizontal
            Line(x2 - i, y1, x2 - i, floor(y1 + length))  -- Vertical
            
            -- Bottom Left
            Line(x1, y2 - i, floor(x1 + length), y2 - i)  -- Horizontal
            Line(x1 + i, floor(y2 - length), x1 + i, y2)  -- Vertical
            
            -- Bottom Right
            Line(floor(x2 - length), y2 - i, x2, y2 - i)  -- Horizontal
            Line(x2 - i, floor(y2 - length), x2 - i, y2)  -- Vertical
        end
    else
        for i = 0, CONFIG.boxThickness do
            OutlinedRect(x1 - i, y1 - i, x2 + i, y2 + i)
        end
    end
end

-- Clean up invalid targets
local function CleanInvalidTargets()
    local currentTime = RealTime()
    if currentTime < nextCleanupTime then return end
    
    nextCleanupTime = currentTime + CLEANUP_INTERVAL
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    for entIndex, lastSeen in pairs(trackedPlayers) do
        local entity = entities.GetByIndex(entIndex)
        
        -- Clean if entity is invalid, dead, dormant, or hasn't been seen recently
        if not entity or 
           not entity:IsValid() or 
           not entity:IsAlive() or
           entity:IsDormant() or
           entity:GetTeamNumber() == localPlayer:GetTeamNumber() or
           currentTime - lastSeen > CLEANUP_INTERVAL * 2 then
            trackedPlayers[entIndex] = nil
        end
    end
end

-- Reset all data
local function ResetTracking()
    for k in pairs(trackedPlayers) do
        trackedPlayers[k] = nil
    end
end

-- Main drawing function
local function OnDraw()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    -- Check if player just respawned
    local currentLifeState = localPlayer:GetPropInt("m_lifeState")
    if lastLifeState == 2 and currentLifeState == 0 then
        ResetTracking()
        if chamsMaterial then
            chamsMaterial:SetMaterialVarFlag(MATERIAL_VAR_IGNOREZ, false)
        end
    end
    lastLifeState = currentLifeState

    local players = entities.FindByClass("CTFPlayer")
    local screenW, screenH = GetScreenSize()
    local centerX, centerY = floor(screenW / 2), floor(screenH / 2)

    -- Clean up invalid targets
    CleanInvalidTargets()

    for idx, player in pairs(players) do
        -- Skip dormant players
        if player:IsDormant() then goto continue end
        
        if player:IsAlive() and
           player:GetTeamNumber() ~= localPlayer:GetTeamNumber() and
           player:GetPropInt("m_iClass") == SOLDIER_CLASS and
           player:InCond(BLAST_JUMPING_COND) then

            -- Update tracking
            trackedPlayers[player:GetIndex()] = RealTime()

            -- Check if player is within distance
            local playerPos = player:GetAbsOrigin()
            local localPos = localPlayer:GetAbsOrigin()
            if not playerPos or not localPos then goto continue end

            local dx = playerPos.x - localPos.x
            local dy = playerPos.y - localPos.y
            local dz = playerPos.z - localPos.z
            local distSqr = dx * dx + dy * dy + dz * dz

            if distSqr > MAX_DISTANCE_SQR then goto continue end

            -- Visibility check using improved function
            local isVisible = IsVisible(player, localPlayer)

            -- 2D Box drawing
            if CONFIG.showBoxes and (not CONFIG.boxOnlyWhenNotVisible or not isVisible) then
                local mins = player:GetMins()
                local maxs = player:GetMaxs()

                if not mins or not maxs then goto continue end

                local bottomPos = Vector3(playerPos.x, playerPos.y, playerPos.z + mins.z)
                local topPos = Vector3(playerPos.x, playerPos.y, playerPos.z + maxs.z)

                local screenBottom = WorldToScreen(bottomPos)
                local screenTop = WorldToScreen(topPos)

                if screenBottom and screenTop then
                    local height = screenBottom[2] - screenTop[2]
                    local width = height * 0.75

                    local x1 = floor(screenBottom[1] - width / 2)
                    local y1 = floor(screenTop[2])
                    local x2 = floor(screenBottom[1] + width / 2)
                    local y2 = floor(screenBottom[2])

                    DrawESPBox(x1, y1, x2, y2, isVisible)
                end
            end

            -- Tracer drawing
            if CONFIG.showTracers and (not CONFIG.tracerOnlyWhenNotVisible or not isVisible) then
                local screenPos = WorldToScreen(playerPos)
                if screenPos then
                    Color(unpack(COLOR_TRACER))
                    Line(centerX, screenH, screenPos[1], screenPos[2])
                end
            end
        end
        ::continue::
    end
end

-- Chams function
local function OnDrawModel(ctx)
    if not CONFIG.showChams then return end

    local entity = ctx:GetEntity()
    if not entity or not entity:IsPlayer() then return end
    
    -- Skip dormant entities
    if entity:IsDormant() then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or entity:GetTeamNumber() == localPlayer:GetTeamNumber() then return end

    if entity:GetPropInt("m_iClass") == SOLDIER_CLASS and
       entity:InCond(BLAST_JUMPING_COND) then

        -- Visibility check using improved function
        local isVisible = IsVisible(entity, localPlayer)

        if not CONFIG.chamsOnlyWhenNotVisible or not isVisible then
            ctx:ForcedMaterialOverride(chamsMaterial)
        end
    end
end

-- Clean up on script unload
callbacks.Register("Unload", "AntiAirCleanup", function()
    ResetTracking()
    chamsMaterial = nil
end)

-- Register main callbacks
callbacks.Unregister("Draw", "SimplifiedSoldierESP")
callbacks.Register("Draw", "SimplifiedSoldierESP", OnDraw)
callbacks.Unregister("DrawModel", "SimplifiedSoldierChams")
callbacks.Register("DrawModel", "SimplifiedSoldierChams", OnDrawModel)
