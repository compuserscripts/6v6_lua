-- Configuration variables
local updateInterval = 0.5 -- Update interval in seconds (0 = every frame)
local pylonWidth = 6 -- Width of pylon in pixels
local pylonHeight = 350 -- Height in hammer units
local pylonOffset = 35 -- Offset above player head in hammer units
local pylonColor = {r = 255, g = 0, b = 0} -- Default red color
local pylonStartAlpha = 200 -- Starting alpha at bottom
local pylonEndAlpha = 25 -- Ending alpha at top
local segments = 10 -- Number of segments for fade effect
local minDistance = 800 -- Minimum distance in hammer units to draw pylon
local visibilityPersistence = 0.2 -- How long to keep using previous visibility results (seconds)

-- Store medic positions with timestamps
local medicPositions = {}
local lastCleanup = 0
local cleanupInterval = 1.0 -- Cleanup stale entries every second
local minDistanceSqr = minDistance * minDistance -- Pre-calculate squared min distance

-- Visibility cache to prevent flashing
local visibilityCache = {}
local lastVisibilityCheckTime = {}

-- Reuse vectors to prevent allocation during rendering
local reuseWorldPos = Vector3(0, 0, 0)
local teamCache = {}
local classCache = {}
local validCache = {}
local aliveCache = {}
local posCache = {}
local heightCache = {}

-- Cache frequently used functions and values
local Vector3 = Vector3
local TraceLine = engine.TraceLine
local WorldToScreen = client.WorldToScreen
local TF2_Medic = 5
local MASK_VISIBLE = MASK_VISIBLE
local floor = math.floor
local RealTime = globals.RealTime
local FrameCount = globals.FrameCount
local Color = draw.Color
local Line = draw.Line
local IsGameUIVisible = engine.IsGameUIVisible
local Con_IsVisible = engine.Con_IsVisible

-- Pre-calculate segment data
local segmentHeight = pylonHeight / segments
local alphaSteps = {}
for i = 0, segments do
    local progress = i / segments
    alphaSteps[i] = floor(pylonStartAlpha - (progress * (pylonStartAlpha - pylonEndAlpha)))
end

-- Check if we can directly see the position with caching for stability
local function isVisibleCached(fromPos, targetPos, identifier)
    local currentTime = RealTime()
    
    -- Check if we need to update the cache
    if not lastVisibilityCheckTime[identifier] or 
       (currentTime - lastVisibilityCheckTime[identifier] > visibilityPersistence) then
        
        -- Update the cache
        local trace = TraceLine(fromPos, targetPos, MASK_VISIBLE)
        visibilityCache[identifier] = trace.fraction >= 0.99
        lastVisibilityCheckTime[identifier] = currentTime
    end
    
    -- Return cached value
    return visibilityCache[identifier]
end

-- Get distance between two points without vector allocation
local function getDistanceSqr(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dy = pos2.y - pos1.y
    local dz = pos2.z - pos1.z
    return dx * dx + dy * dy + dz * dz
end

local function shouldUpdatePosition(medicIndex)
    if updateInterval == 0 then return true end
    
    local lastUpdate = medicPositions[medicIndex] and medicPositions[medicIndex].lastUpdate or 0
    return (RealTime() - lastUpdate) >= updateInterval
end

local function cleanupStaleEntries()
    local currentTime = RealTime()
    
    -- Only clean up periodically
    if currentTime - lastCleanup < cleanupInterval then
        return
    end
    
    lastCleanup = currentTime
    
    -- Remove stale entries
    for medicIdx, data in pairs(medicPositions) do
        if currentTime - data.lastUpdate > updateInterval * 3 then
            medicPositions[medicIdx] = nil
            -- Clean up associated visibility cache
            for k in pairs(visibilityCache) do
                if string.match(k, "^" .. medicIdx .. "_") then
                    visibilityCache[k] = nil
                    lastVisibilityCheckTime[k] = nil
                end
            end
        end
    end
end

-- Update entity caches less frequently
local function updateEntityCaches()
    local frameCount = FrameCount()
    if frameCount % 10 == 0 then -- Update every 10 frames
        local players = entities.FindByClass("CTFPlayer")
        for _, player in pairs(players) do
            local index = player:GetIndex()
            if player:IsValid() then
                validCache[index] = true
                teamCache[index] = player:GetTeamNumber()
                classCache[index] = player:GetPropInt("m_iClass")
                aliveCache[index] = player:IsAlive()
                posCache[index] = player:GetAbsOrigin()
                heightCache[index] = player:GetMaxs().z
            else
                validCache[index] = false
            end
        end
    end
end

callbacks.Register("Draw", function()
    -- Skip if game UI is visible
    if IsGameUIVisible() or Con_IsVisible() then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    -- Cache these values outside the loop
    local localPos = localPlayer:GetAbsOrigin()
    local eyePos = localPos + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local localTeam = localPlayer:GetTeamNumber()
    
    -- Update entity caches
    updateEntityCaches()
    
    -- Clean up stale entries
    cleanupStaleEntries()
    
    -- Process all players (using cached data when possible)
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        local index = player:GetIndex()
        
        -- Use cached values when possible
        if not validCache[index] or (teamCache[index] == localTeam) or 
           (classCache[index] ~= TF2_Medic) or not aliveCache[index] then
            goto continue
        end
        
        local playerPos = posCache[index] or player:GetAbsOrigin()
        
        -- Skip if we can see the medic directly (with caching)
        if isVisibleCached(eyePos, playerPos, index .. "_base") then
            goto continue
        end

        -- Skip if we're too close to the medic (using squared distance for performance)
        local distanceSqr = getDistanceSqr(localPos, playerPos)
        if distanceSqr < minDistanceSqr then
            goto continue
        end
        
        -- Update position with Z offset
        local currentPos = Vector3(playerPos.x, playerPos.y, playerPos.z + (heightCache[index] or 0) + pylonOffset)
        
        if shouldUpdatePosition(index) then
            -- Store a deep copy to avoid reference issues
            if not medicPositions[index] then
                medicPositions[index] = {}
            end
            
            medicPositions[index].position = Vector3(currentPos.x, currentPos.y, currentPos.z)
            medicPositions[index].lastUpdate = RealTime()
        end
        
        -- If we don't have a position yet, create one
        if not medicPositions[index] or not medicPositions[index].position then
            medicPositions[index] = {
                position = Vector3(currentPos.x, currentPos.y, currentPos.z),
                lastUpdate = RealTime()
            }
        end
        
        local basePosition = medicPositions[index].position
        local lastScreenPos = nil
        local anySegmentVisible = false
        
        -- First pass: verify that at least one segment is visible
        for i = 0, segments do
            reuseWorldPos.x = basePosition.x
            reuseWorldPos.y = basePosition.y
            reuseWorldPos.z = basePosition.z + (i * segmentHeight)
            
            local segmentKey = index .. "_segment_" .. i
            if isVisibleCached(eyePos, reuseWorldPos, segmentKey) then
                anySegmentVisible = true
                break
            end
        end
        
        -- Skip drawing if no segments are visible
        if not anySegmentVisible then
            goto continue
        end
        
        -- Second pass: draw visible segments
        for i = 0, segments do
            reuseWorldPos.x = basePosition.x
            reuseWorldPos.y = basePosition.y
            reuseWorldPos.z = basePosition.z + (i * segmentHeight)
            
            local segmentKey = index .. "_segment_" .. i
            local visible = isVisibleCached(eyePos, reuseWorldPos, segmentKey)
            
            if not visible then
                lastScreenPos = nil
                goto continueSegment
            end
            
            local screenPos = WorldToScreen(reuseWorldPos)
            if screenPos and lastScreenPos then
                Color(pylonColor.r, pylonColor.g, pylonColor.b, alphaSteps[i])
                
                for w = 0, pylonWidth - 1 do
                    Line(lastScreenPos[1] + w, lastScreenPos[2], screenPos[1] + w, screenPos[2])
                end
            end
            
            lastScreenPos = screenPos
            
            ::continueSegment::
        end
        
        ::continue::
    end
end)

-- On script unload, clean up memory
callbacks.Register("Unload", function()
    medicPositions = nil
    teamCache = nil
    classCache = nil
    validCache = nil
    aliveCache = nil
    posCache = nil
    heightCache = nil
    alphaSteps = nil
    visibilityCache = nil
    lastVisibilityCheckTime = nil
end)
