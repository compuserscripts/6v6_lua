-- Configuration
local CONFIG = {
    showBoxes = true,
    showTracers = false,
    boxColor = {255, 165, 0, 255},  -- Orange for hiders
    tracerColor = {0, 0, 255, 255}, -- Blue for tracers
    timeToMarkAsHider = 5.5,  -- Seconds player must remain stationary
    updatePositionThreshold = 1.0,  -- Units player must move to be considered "moving"
    maxDistance = 1650,  -- Maximum distance to check for hiders (hammer units)
    cleanupInterval = 1.0  -- Clean invalid players every second
}

-- Player tracking data
local playerData = {}
local lastLifeState = 2  -- Start with LIFE_DEAD (2)
local nextCleanupTime = 0

-- Pre-cache commonly used functions for performance
local floor = math.floor
local unpack = unpack or table.unpack
local RealTime = globals.RealTime
local WorldToScreen = client.WorldToScreen
local GetScreenSize = draw.GetScreenSize
local Color = draw.Color
local Line = draw.Line
local OutlinedRect = draw.OutlinedRect

-- Helper function to calculate distance between positions
local function DistanceBetweenVectors(v1, v2)
    if not v1 or not v2 then return 0 end
    local dx = v1.x - v2.x
    local dy = v1.y - v2.y
    local dz = v1.z - v2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Reset all tracking data
local function ResetPlayerData()
    playerData = {}
end

-- Clean up invalid targets
local function CleanInvalidTargets()
    local currentTime = RealTime()
    if currentTime < nextCleanupTime then return end
    
    nextCleanupTime = currentTime + CONFIG.cleanupInterval
    
    -- Only clean up if we have data to clean
    if next(playerData) == nil then return end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    for playerIndex, data in pairs(playerData) do
        local entity = entities.GetByIndex(playerIndex)
        
        -- Remove data only if entity is completely invalid or definitely not in play
        if not entity or 
           not entity:IsAlive() or
           entity:GetTeamNumber() == localPlayer:GetTeamNumber() then
            playerData[playerIndex] = nil
        end
    end
end

-- Check if player is within valid range
local function IsPlayerInRange(player, localPlayer)
    if not player or not localPlayer then return false end
    
    local playerPos = player:GetAbsOrigin()
    local localPos = localPlayer:GetAbsOrigin()
    
    return DistanceBetweenVectors(playerPos, localPos) <= CONFIG.maxDistance
end

-- Update player data
local function UpdatePlayerData(player)
    if not player or not player:IsAlive() then return end
    
    local currentTime = RealTime()
    local currentPos = player:GetAbsOrigin()
    local playerIndex = player:GetIndex()
    
    -- Initialize new player data
    if not playerData[playerIndex] then
        playerData[playerIndex] = {
            lastPosition = currentPos,
            lastMoveTime = currentTime,
            isHider = false,
            lastUpdateTime = currentTime
        }
        return
    end
    
    local data = playerData[playerIndex]
    data.lastUpdateTime = currentTime
    
    local distance = DistanceBetweenVectors(currentPos, data.lastPosition)
    
    if distance > CONFIG.updatePositionThreshold then
        data.lastPosition = currentPos
        data.lastMoveTime = currentTime
        data.isHider = false
    elseif currentTime - data.lastMoveTime > CONFIG.timeToMarkAsHider then
        data.isHider = true
    end
end

local function DrawPlayerESP(player, data)
    local playerPos = player:GetAbsOrigin()
    local screenW, screenH = GetScreenSize()
    local centerX, centerY = floor(screenW / 2), floor(screenH / 2)
    
    -- Draw box
    if CONFIG.showBoxes then
        local mins = player:GetMins()
        local maxs = player:GetMaxs()
        
        if mins and maxs then
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
                
                Color(unpack(CONFIG.boxColor))
                OutlinedRect(x1, y1, x2, y2)
            end
        end
    end
    
    -- Draw tracer
    if CONFIG.showTracers then
        local screenPos = WorldToScreen(playerPos)
        if screenPos then
            Color(unpack(CONFIG.tracerColor))
            Line(centerX, screenH, screenPos[1], screenPos[2])
        end
    end
end

local function OnDraw()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not localPlayer:IsAlive() then return end
    
    -- Check for respawn
    local currentLifeState = localPlayer:GetPropInt("m_lifeState")
    if lastLifeState == 2 and currentLifeState == 0 then  -- If we went from dead to alive
        ResetPlayerData()
    end
    lastLifeState = currentLifeState
    
    -- Clean up invalid targets periodically
    CleanInvalidTargets()
    
    -- Process players
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player and player:IsAlive() and 
           player:GetTeamNumber() ~= localPlayer:GetTeamNumber() and
           IsPlayerInRange(player, localPlayer) then
            
            UpdatePlayerData(player)
            
            local data = playerData[player:GetIndex()]
            if data and data.isHider and not player:IsDormant() then
                DrawPlayerESP(player, data)
            end
        end
    end
end

-- Register callbacks
callbacks.Register("Draw", "HiderESP", OnDraw)
callbacks.Register("Unload", "HiderESPCleanup", ResetPlayerData)
