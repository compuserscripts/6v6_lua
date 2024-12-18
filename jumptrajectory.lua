local hitChance = 0
local vPath = {}
local projectileSimulation2 = Vector3(0, 0, 0)
local vHitbox = { Vector3(-22, -22, 0), Vector3(22, 22, 80) }
local lastPosition = {}
local priorPrediction = {}

local Path_styles = {"Line", "Alt Line", "Dashed"}
local Path_styles_selected = 1

-- Helper functions
local function Normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function RotateVector(vector, angle)
    local rad = math.rad(angle)
    local cosAngle = math.cos(rad)
    local sinAngle = math.sin(rad)
    return Vector3(
        vector.x * cosAngle - vector.y * sinAngle,
        vector.x * sinAngle + vector.y * cosAngle,
        vector.z
    )
end

local function L_line(start_pos, end_pos, secondary_line_size)
    if not (start_pos and end_pos) then
        return
    end
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then
        return
    end
    local normalized_direction = Normalize(direction)
    local perpendicular = Vector3(normalized_direction.y, -normalized_direction.x, 0) * secondary_line_size
    local w2s_start_pos = client.WorldToScreen(start_pos)
    local w2s_end_pos = client.WorldToScreen(end_pos)
    if not (w2s_start_pos and w2s_end_pos) then
        return
    end
    local secondary_line_end_pos = start_pos + perpendicular
    local w2s_secondary_line_end_pos = client.WorldToScreen(secondary_line_end_pos)
    if w2s_secondary_line_end_pos then
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_end_pos[1], w2s_end_pos[2])
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_secondary_line_end_pos[1], w2s_secondary_line_end_pos[2])
    end
end

local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end
    local source = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = entity:GetAbsOrigin()
    local trace = engine.TraceLine(source, targetPos, MASK_VISIBLE)
    return trace.entity == entity
end

local function IsOnGround(player)
    local pFlags = player:GetPropInt("m_fFlags")
    return (pFlags & FL_ONGROUND) == 1
end

local function IsRocketJumping(player)
    if player:GetPropInt("m_iClass") ~= 3 then
        return false
    end
    local isGrounded = IsOnGround(player)
    local velocity = player:EstimateAbsVelocity()
    return not isGrounded and velocity.z > 100
end

local function OnCreateMove()
    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then return end
    
    local tick_interval = globals.TickInterval()
    local gravity = client.GetConVar("sv_gravity")
    local stepSize = me:GetPropFloat("localdata", "m_flStepSize")
    vPath = {}
    projectileSimulation2 = Vector3(0, 0, 0)

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
        -- Get the player's actual view position as starting point
        local origin = bestTarget:GetAbsOrigin()
        local viewOffset = bestTarget:GetPropVector("localdata", "m_vecViewOffset[0]")
        local aimPos = origin + viewOffset
        
        -- Start prediction from view height
        local lastP = aimPos
        local lastV = bestTarget:EstimateAbsVelocity()
        local lastG = IsOnGround(bestTarget)
        local vStep = Vector3(0, 0, stepSize / 2)

        vPath[1] = lastP

        for i = 1, 66 do
            local pos = lastP + lastV * tick_interval
            local vel = lastV
            local onGround = lastG

            local wallTrace = engine.TraceHull(lastP, pos, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID)
            if wallTrace.fraction < 1 then
                local normal = wallTrace.plane
                local angle = math.deg(math.acos(normal:Dot(Vector3(0, 0, 1))))
                if angle > 55 then
                    local dot = vel:Dot(normal)
                    vel = vel - normal * dot
                end
                pos.x, pos.y = wallTrace.endpos.x, wallTrace.endpos.y
            end

            local downTrace = engine.TraceHull(pos + vStep, pos - vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID)
            if downTrace.fraction < 1 then
                pos = downTrace.endpos
                onGround = true
                vel.z = 0
                projectileSimulation2 = pos
            else
                onGround = false
                vel.z = vel.z - gravity * tick_interval
            end

            lastP, lastV, lastG = pos, vel, onGround
            vPath[i + 1] = pos

            if i <= 20 then
                local currentTick = 20 - i
                local playerIdx = bestTarget:GetIndex()
                lastPosition[playerIdx] = lastPosition[playerIdx] or {}
                priorPrediction[playerIdx] = priorPrediction[playerIdx] or {}
                lastPosition[playerIdx][currentTick] = priorPrediction[playerIdx][currentTick] or pos
                priorPrediction[playerIdx][currentTick] = pos

                local hitChance1 = math.abs((lastPosition[playerIdx][currentTick] - priorPrediction[playerIdx][currentTick]):Length())
                hitChance = math.max(0, 100 - (hitChance1 * 0.5))
            end
        end
    end
end

local function OnDraw()
    if not vPath or #vPath == 0 then return end
    
    draw.Color(255 - math.floor((hitChance / 100) * 255), math.floor((hitChance / 100) * 255), 0, 255)
    
    for i = 1, #vPath - 1 do
        local pos1 = vPath[i]
        local pos2 = vPath[i + 1]

        if Path_styles_selected == 1 or Path_styles_selected == 3 then
            local screenPos1 = client.WorldToScreen(pos1)
            local screenPos2 = client.WorldToScreen(pos2)
            
            if screenPos1 and screenPos2 and (not (Path_styles_selected == 3) or i % 2 == 1) then
                draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
            end
        end

        if Path_styles_selected == 2 then
            L_line(pos1, pos2, 10)
        end
    end

    -- Draw landing point indicator
    if projectileSimulation2.x ~= 0 or projectileSimulation2.y ~= 0 or projectileSimulation2.z ~= 0 then
        local screenPos = client.WorldToScreen(projectileSimulation2)
        if screenPos then
            draw.Line(screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
            draw.Line(screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
        end
    end
end

callbacks.Register("CreateMove", function()
    if input.IsButtonPressed(KEY_INSERT) then
        Path_styles_selected = Path_styles_selected + 1
        if Path_styles_selected > #Path_styles then
            Path_styles_selected = 1
        end
    end
end)

callbacks.Register("CreateMove", "PathVisualization.CreateMove", OnCreateMove)
callbacks.Register("Draw", "PathVisualization.Draw", OnDraw)
