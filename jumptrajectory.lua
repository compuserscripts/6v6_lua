-- Track initialization state and timer
local initialized = false
local lastPredictionTime = 0
local PREDICTION_INTERVAL = 0.016

-- Configuration toggles
local config = {
    pathStyle = 1,
    showPolygon = true,        
    showLandingX = false,       
    requireVisibility = true,  
    minLandingDistance = 100,
    predictionTicks = 66,
    hitChanceWindow = 20 
}

-- Cached vectors and arrays
local vPath = {}
local lastPosition = {}
local priorPrediction = {}
local hitChance = 0
local projectileSimulation2 = Vector3(0, 0, 0)
local vHitbox = { Vector3(-22, -22, 0), Vector3(22, 22, 80) }
local vStep = Vector3(0, 0, 0)
local traceMask = MASK_PLAYERSOLID
local gravity = 0
local tickInterval = 0
local lastTrackedPlayer = nil -- Store the last tracked player to detect changes

-- Impact polygon configuration
local polygonConfig = {
    enabled = true,
    r = 0,         
    g = 255,       
    b = 0,         
    a = 25,        
    size = 40,     
    segments = 13,  
    outline = {
        enabled = true,
        r = 0,
        g = 0, 
        b = 0,
        a = 155
    }
}

-- Impact polygon class
local ImpactPolygon = {}
ImpactPolygon.__index = ImpactPolygon

function ImpactPolygon:new()
    local self = setmetatable({}, ImpactPolygon)
    self.texture = draw.CreateTextureRGBA(string.char(
        0xff, 0xff, 0xff, polygonConfig.a,
        0xff, 0xff, 0xff, polygonConfig.a,
        0xff, 0xff, 0xff, polygonConfig.a,
        0xff, 0xff, 0xff, polygonConfig.a
    ), 2, 2)
    self.segmentAngle = (math.pi * 2) / polygonConfig.segments
    return self
end

function ImpactPolygon:destroy()
    if self.texture then
        draw.DeleteTexture(self.texture)
        self.texture = nil
    end
end

function ImpactPolygon:calculatePositions(plane, origin)
    local positions = {}
    local radius = polygonConfig.size

    if math.abs(plane.z) >= 0.99 then
        for i = 1, polygonConfig.segments do
            local ang = i * self.segmentAngle
            local worldPos = origin + Vector3(
                radius * math.cos(ang),
                radius * math.sin(ang),
                0
            )
            local screenPos = client.WorldToScreen(worldPos)
            if not screenPos then return nil end
            
            positions[i] = {
                screenPos[1], screenPos[2],
                0.5 + 0.5 * math.cos(ang),
                0.5 + 0.5 * math.sin(ang)
            }
        end
    else
        local right = Vector3(-plane.y, plane.x, 0)
        local up = Vector3(
            plane.z * right.y,
            -plane.z * right.x,
            (plane.y * right.x) - (plane.x * right.y)
        )
        
        radius = radius / math.cos(math.asin(plane.z))

        for i = 1, polygonConfig.segments do
            local ang = i * self.segmentAngle
            local worldPos = origin + 
                (right * (radius * math.cos(ang))) +
                (up * (radius * math.sin(ang)))
            local screenPos = client.WorldToScreen(worldPos)
            if not screenPos then return nil end
            
            positions[i] = {
                screenPos[1], screenPos[2],
                0.5 + 0.5 * math.cos(ang),
                0.5 + 0.5 * math.sin(ang)
            }
        end
    end

    return positions
end

function ImpactPolygon:draw(plane, origin)
    if not polygonConfig.enabled then return end

    local positions = self:calculatePositions(plane, origin)
    if not positions then return end

    draw.Color(polygonConfig.r, polygonConfig.g, polygonConfig.b, 255)
    draw.TexturedPolygon(self.texture, positions, true)

    if polygonConfig.outline.enabled then
        draw.Color(
            polygonConfig.outline.r,
            polygonConfig.outline.g,
            polygonConfig.outline.b,
            polygonConfig.outline.a
        )
        local last = positions[#positions]
        for i = 1, #positions do
            local curr = positions[i]
            draw.Line(last[1], last[2], curr[1], curr[2])
            last = curr
        end
    end
end

local function L_line(start_pos, end_pos, secondary_line_size)
    if not (start_pos and end_pos) then return end
    
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then return end
    
    local normalized_direction = direction:Length() > 0 and Vector3(
        direction.x / direction_length,
        direction.y / direction_length,
        direction.z / direction_length
    ) or Vector3(0, 0, 0)
    
    local perpendicular = Vector3(normalized_direction.y, -normalized_direction.x, 0) * secondary_line_size
    
    local w2s_start_pos = client.WorldToScreen(start_pos)
    local w2s_end_pos = client.WorldToScreen(end_pos)
    if not (w2s_start_pos and w2s_end_pos) then return end
    
    local secondary_line_end_pos = start_pos + perpendicular
    local w2s_secondary_line_end_pos = client.WorldToScreen(secondary_line_end_pos)
    if w2s_secondary_line_end_pos then
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_end_pos[1], w2s_end_pos[2])
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_secondary_line_end_pos[1], w2s_secondary_line_end_pos[2])
    end
end

local function IsVisible(entity, localPlayer)
    if not config.requireVisibility then return true end
    if not entity or not localPlayer then return false end
    
    local source = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = entity:GetAbsOrigin()
    local trace = engine.TraceLine(source, targetPos, MASK_VISIBLE)
    return trace.entity == entity
end

local function IsOnGround(player)
    return (player:GetPropInt("m_fFlags") & FL_ONGROUND) == 1
end

local function IsRocketJumping(player)
    if player:GetPropInt("m_iClass") ~= 3 then return false end
    local velocity = player:EstimateAbsVelocity()
    return (not IsOnGround(player) and velocity.z > 100) or player:InCond(81)
end

local function ClearTrajectory()
    vPath = {}
    projectileSimulation2 = Vector3(0, 0, 0)
    hitChance = 0
end

local function Initialize()
    if initialized then return end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    gravity = client.GetConVar("sv_gravity")
    tickInterval = globals.TickInterval()
    vStep = Vector3(0, 0, localPlayer:GetPropFloat("localdata", "m_flStepSize") / 2)
    
    impactPolygon = ImpactPolygon:new()
    
    initialized = true
end

local function Cleanup()
    if impactPolygon then
        impactPolygon:destroy()
        impactPolygon = nil
    end
    
    vPath = {}
    lastPosition = {}
    priorPrediction = {}
    projectileSimulation2 = Vector3(0, 0, 0)
    lastTrackedPlayer = nil
    initialized = false
end

local function OnCreateMove()
    Initialize()
    if not initialized then return end
    
    local curTime = globals.RealTime()
    if curTime - lastPredictionTime < PREDICTION_INTERVAL then
        return
    end
    lastPredictionTime = curTime
    
    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then return end

    -- Check if the last tracked player is still valid and rocket jumping
    if lastTrackedPlayer and (
       not lastTrackedPlayer:IsValid() or 
       not lastTrackedPlayer:IsAlive() or 
       lastTrackedPlayer:IsDormant() or
       not IsRocketJumping(lastTrackedPlayer) or
       not IsVisible(lastTrackedPlayer, me)) then
        -- Player died, became invalid, or stopped rocket jumping - clear trajectory
        ClearTrajectory()
        lastTrackedPlayer = nil
    end

    local bestTarget = nil
    local bestDistance = math.huge

    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player and player:IsAlive() and not player:IsDormant() 
           and player ~= me and player:GetTeamNumber() ~= me:GetTeamNumber()
           and IsRocketJumping(player) and IsVisible(player, me) then
            
            local distance = (player:GetAbsOrigin() - me:GetAbsOrigin()):Length()
            if distance < bestDistance then
                bestDistance = distance
                bestTarget = player
            end
        end
    end

    if bestTarget then
        -- Update the last tracked player
        lastTrackedPlayer = bestTarget
        
        local origin = bestTarget:GetAbsOrigin()
        local viewOffset = bestTarget:GetPropVector("localdata", "m_vecViewOffset[0]")
        local aimPos = origin + viewOffset
        
        local lastP = aimPos
        local lastV = bestTarget:EstimateAbsVelocity()
        local lastG = IsOnGround(bestTarget)

        -- Clear old path data
        vPath = {}
        vPath[1] = lastP

        for i = 1, config.predictionTicks do
            local pos = lastP + lastV * tickInterval
            local vel = lastV
            local onGround = lastG

            local wallTrace = engine.TraceHull(lastP, pos, vHitbox[1], vHitbox[2], traceMask)
            if wallTrace.fraction < 1 then
                local normal = wallTrace.plane
                local angle = math.deg(math.acos(normal:Dot(Vector3(0, 0, 1))))
                if angle > 55 then
                    local dot = vel:Dot(normal)
                    vel = vel - normal * dot
                end
                pos.x, pos.y = wallTrace.endpos.x, wallTrace.endpos.y
            end

            local downTrace = engine.TraceHull(pos + vStep, pos - vStep, vHitbox[1], vHitbox[2], traceMask)
            if downTrace.fraction < 1 then
                pos = downTrace.endpos
                onGround = true
                vel.z = 0
                projectileSimulation2 = pos
            else
                onGround = false
                vel.z = vel.z - gravity * tickInterval
            end

            lastP, lastV, lastG = pos, vel, onGround
            vPath[i + 1] = pos

            if i <= config.hitChanceWindow then
                local currentTick = config.hitChanceWindow - i
                local playerIdx = bestTarget:GetIndex()
                lastPosition[playerIdx] = lastPosition[playerIdx] or {}
                priorPrediction[playerIdx] = priorPrediction[playerIdx] or {}
                lastPosition[playerIdx][currentTick] = priorPrediction[playerIdx][currentTick] or pos
                priorPrediction[playerIdx][currentTick] = pos

                local hitChance1 = math.abs((lastPosition[playerIdx][currentTick] - priorPrediction[playerIdx][currentTick]):Length())
                hitChance = math.max(0, 100 - (hitChance1 * 0.5))
            end
        end
    else
        if lastTrackedPlayer then
            -- No valid target found, and we had a previous target - clear trajectory
            ClearTrajectory()
            lastTrackedPlayer = nil
        end
    end
end

local function OnDraw()
    if not initialized or engine.Con_IsVisible() or engine.IsGameUIVisible() then 
        return 
    end
    
    if #vPath == 0 then return end
    
    draw.Color(255 - math.floor((hitChance / 100) * 255), math.floor((hitChance / 100) * 255), 0, 255)
    
    for i = 1, #vPath - 1 do
        local pos1 = vPath[i]
        local pos2 = vPath[i + 1]

        if config.pathStyle == 1 or config.pathStyle == 3 then
            local screenPos1 = client.WorldToScreen(pos1)
            local screenPos2 = client.WorldToScreen(pos2)
            
            if screenPos1 and screenPos2 and (not (config.pathStyle == 3) or i % 2 == 1) then
                draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
            end
        elseif config.pathStyle == 2 then
            L_line(pos1, pos2, 10)
        end
    end

    if projectileSimulation2.x ~= 0 or projectileSimulation2.y ~= 0 or projectileSimulation2.z ~= 0 then
        local startPoint = vPath[1]
        local distanceToLanding = (projectileSimulation2 - startPoint):Length()
        
        if distanceToLanding > config.minLandingDistance then
            local lastPointIndex = #vPath
            if lastPointIndex >= 2 then
                if config.showPolygon and impactPolygon then
                    local direction = vPath[lastPointIndex] - vPath[lastPointIndex - 1]
                    local plane = direction:Length() > 0 and Vector3(
                        direction.x / direction:Length(),
                        direction.y / direction:Length(),
                        direction.z / direction:Length()
                    ) or Vector3(0, 0, 1)
                    impactPolygon:draw(plane, projectileSimulation2)
                end

                if config.showLandingX then
                    local screenPos = client.WorldToScreen(projectileSimulation2)
                    if screenPos then
                        draw.Line(screenPos[1] - 10, screenPos[2], screenPos[1] + 10, screenPos[2])
                        draw.Line(screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
                    end
                end
            end
        end
    end
end

-- Optimize frequent checks by adding throttling to event handling
local lastEventCheckTime = 0
local EVENT_CHECK_INTERVAL = 0.1 -- Check less frequently

local function HandleGameEvent(event)
    if not initialized or not lastTrackedPlayer then return end
    
    local curTime = globals.RealTime()
    if curTime - lastEventCheckTime < EVENT_CHECK_INTERVAL then
        return
    end
    lastEventCheckTime = curTime
    
    if event:GetName() == "player_death" then
        local victimUserID = event:GetInt("userid")
        if victimUserID then
            local victim = entities.GetByUserID(victimUserID)
            if victim and victim:GetIndex() == lastTrackedPlayer:GetIndex() then
                -- Our tracked player died, clear trajectory
                ClearTrajectory()
                lastTrackedPlayer = nil
            end
        end
    end
end

callbacks.Register("CreateMove", "PathVisualization.CreateMove", OnCreateMove)
callbacks.Register("Draw", "PathVisualization.Draw", OnDraw)
callbacks.Register("FireGameEvent", "PathVisualization.GameEvent", HandleGameEvent)
callbacks.Register("Unload", Cleanup)
