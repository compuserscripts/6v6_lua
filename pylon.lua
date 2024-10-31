-- Configuration variables
local updateInterval = 0 -- Default update interval in seconds
local pylonWidth = 6 -- Width of pylon in pixels
local pylonHeight = 350 -- Height in hammer units
local pylonOffset = 35 -- Offset above player head in hammer units
local pylonColor = {r = 255, g = 0, b = 0} -- Default red color
local pylonStartAlpha = 200 -- Starting alpha at bottom
local pylonEndAlpha = 25 -- Ending alpha at top
local segments = 10 -- Number of segments for fade effect
local minDistance = 800 -- Minimum distance in hammer units to draw pylon

-- Store medic positions with timestamps
local medicPositions = {}

-- Check if we can directly see the medic
local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end
    local source = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = entity:GetAbsOrigin()
    local trace = engine.TraceLine(source, targetPos, MASK_VISIBLE)
    return trace.entity == entity
end

-- Check if individual pylon segments are visible
local function isPointVisible(fromPos, toPos)
    local trace = engine.TraceLine(fromPos, toPos, MASK_SOLID | MASK_VISIBLE | MASK_OPAQUE)
    return trace.fraction >= 1.0
end

-- Get distance between two points
local function getDistance(pos1, pos2)
    local delta = Vector3(pos2.x - pos1.x, pos2.y - pos1.y, pos2.z - pos1.z)
    return math.sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
end

local function shouldUpdatePosition(medicIndex)
    if updateInterval == 0 then return true end
    
    local lastUpdate = medicPositions[medicIndex] and medicPositions[medicIndex].lastUpdate or 0
    return (globals.RealTime() - lastUpdate) >= updateInterval
end

local function storeMedicPosition(medicIndex, position)
    medicPositions[medicIndex] = {
        position = position,
        lastUpdate = globals.RealTime()
    }
end

callbacks.Register("Draw", function()
    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    local eyePos = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    
    for _, player in pairs(players) do
        if player:IsValid() and player:IsAlive() and player:GetTeamNumber() ~= localPlayer:GetTeamNumber() 
           and player:GetPropInt("m_iClass") == TF2_Medic then
            
            -- Skip if we can see the medic directly
            if IsVisible(player, localPlayer) then
                goto continue
            end

            -- Skip if we're too close to the medic
            if getDistance(localPlayer:GetAbsOrigin(), player:GetAbsOrigin()) < minDistance then
                goto continue
            end
            
            local medicIndex = player:GetIndex()
            local currentPos = player:GetAbsOrigin()
            local medicHeight = player:GetMaxs().z
            currentPos.z = currentPos.z + medicHeight + pylonOffset
            
            if shouldUpdatePosition(medicIndex) then
                storeMedicPosition(medicIndex, currentPos)
            end
            
            local basePosition = medicPositions[medicIndex] and medicPositions[medicIndex].position or currentPos
            local segmentHeight = pylonHeight / segments
            local lastScreenPos = nil
            local lastVisible = false
            
            for i = 0, segments do
                local worldPos = Vector3(
                    basePosition.x,
                    basePosition.y,
                    basePosition.z + (i * segmentHeight)
                )
                
                local visible = isPointVisible(eyePos, worldPos)
                if not visible then
                    lastScreenPos = nil
                    lastVisible = false
                    goto continueSegment
                end
                
                local screenPos = client.WorldToScreen(worldPos)
                if screenPos and lastScreenPos and visible then
                    local progress = i / segments
                    local alpha = math.floor(pylonStartAlpha - (progress * (pylonStartAlpha - pylonEndAlpha)))
                    
                    for w = 0, pylonWidth - 1 do
                        draw.Color(pylonColor.r, pylonColor.g, pylonColor.b, alpha)
                        draw.Line(lastScreenPos[1] + w, lastScreenPos[2], screenPos[1] + w, screenPos[2])
                    end
                end
                
                lastScreenPos = screenPos
                lastVisible = visible
                
                ::continueSegment::
            end
            
            ::continue::
        end
    end
end)