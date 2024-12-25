-- Configuration
local config = {
    -- Style settings
    colors = {
        friendly = {
            path = {255, 255, 255, 255},
            radius = {255, 0, 0, 100}
        },
        enemy = {
            path = {255, 0, 0, 255},
            radius = {255, 0, 0, 100}
        }
    },
    
    -- Trajectory settings
    predictionSteps = 66,
    pathThickness = 2,
    
    -- Physics settings
    elasticity = 0.45,        -- How bouncy projectiles are
    friction = 0.2,           -- Surface friction when sliding
    
    -- Weapon-specific settings  
    weapons = {
        [TF_WEAPON_GRENADELAUNCHER] = {
            speed = 1200.4,
            gravity = 800,
            radius = 146,
            bounce = true
        },
        [TF_WEAPON_PIPEBOMBLAUNCHER] = {
            speed = 925.38,      -- Base sticky speed (will be modified by charge)
            gravity = 800,
            radius = 146,
            bounce = false
        }
    }
}

-- Calculate sticky charge for any player
local function GetStickyChargeSpeed(player, weapon, isEnemy)
    local baseSpeed = 900
    local maxChargeSpeed = 2400 -- Maximum speed with full charge
    
    if not weapon then return baseSpeed end

    -- Try multiple netvar paths to get charge data
    local chargeBeginTime
    if isEnemy then
        -- Try different netvar paths for enemy charge
        local paths = {
            weapon:GetPropFloat("m_Shared", "m_flChargeBeginTime"),
            weapon:GetPropFloat("LocalTFWeaponMedigunData", "m_flChargeLevel"),
            weapon:GetPropFloat("m_flChargeBeginTime")
        }
        
        -- Use first non-nil value
        for _, time in ipairs(paths) do
            if time and time ~= 0 then
                chargeBeginTime = time
                break
            end
        end
        
        -- If we still don't have charge time, check if weapon is firing
        if not chargeBeginTime or chargeBeginTime == 0 then
            local isShooting = weapon:GetPropBool("m_bAttacking") or false
            if isShooting then
                -- If shooting, estimate charge based on client time
                chargeBeginTime = globals.CurTime() - 0.1
            end
        end
    else
        -- Local player charge time
        chargeBeginTime = weapon:GetPropFloat("PipebombLauncherLocalData", "m_flChargeBeginTime")
    end

    if not chargeBeginTime or chargeBeginTime == 0 then 
        return baseSpeed
    end
    
    -- Calculate charge time and clamp between 0-4 seconds
    local chargeTime = math.max(0, math.min(4, globals.CurTime() - chargeBeginTime))
    
    -- Calculate speed based on charge time
    local chargeSpeed = baseSpeed + (maxChargeSpeed - baseSpeed) * (chargeTime / 4)
    
    -- More detailed debug output for enemy charges
    if isEnemy and globals.TickCount() % 66 == 0 then
        print(string.format("Enemy charge data - BeginTime: %.2f, ChargeTime: %.2f, Speed: %.1f", 
            chargeBeginTime, chargeTime, chargeSpeed))
        print(string.format("Current time: %.2f, Delta: %.2f", 
            globals.CurTime(), globals.CurTime() - chargeBeginTime))
    end
    
    return chargeSpeed
end

-- Get player eye position and angles
local function GetPlayerAimInfo(player)
    local origin = player:GetAbsOrigin()
    local angles
    local startPos
    
    -- Get eye height and position
    local viewOffset = player:GetPropInt("m_fFlags") & FL_DUCKING == FL_DUCKING 
        and Vector3(0, 0, 45)  -- Ducked height
        or Vector3(0, 0, 68)   -- Standing height
    
    startPos = origin + viewOffset
    
    -- Get angles and adjust for view direction
    local pitch = player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[0]") or 0
    local yaw = player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[1]") or 0
    
    -- Normalize yaw angle to -180 to 180 range
    while yaw > 180 do yaw = yaw - 360 end
    while yaw < -180 do yaw = yaw + 360 end
    
    -- Clamp pitch to avoid extreme angles
    pitch = math.max(-89, math.min(89, pitch))
    
    angles = EulerAngles(pitch, yaw, 0)
    
    return startPos, angles
end

-- Simulate grenade trajectory
local function PredictTrajectory(startPos, angles, weaponConfig, player, weaponID, isEnemy)
    local points = {}
    
    -- Calculate initial velocity from angles
    local rad_pitch = math.rad(angles.x)
    local rad_yaw = math.rad(angles.y)
    
    local forward = Vector3(
        math.cos(rad_pitch) * math.cos(rad_yaw),
        math.cos(rad_pitch) * math.sin(rad_yaw),
        -math.sin(rad_pitch)
    )
    
    -- Initialize physics
    local position = Vector3(startPos.x, startPos.y, startPos.z + 10)
    
    -- Get speed based on weapon type and charge
    local speed = weaponConfig.speed
    if weaponID == TF_WEAPON_PIPEBOMBLAUNCHER then
        local weapon = player:GetPropEntity("m_hActiveWeapon")
        speed = GetStickyChargeSpeed(player, weapon, isEnemy)
    end
    
    -- Normalize the forward vector manually
    local length = math.sqrt(forward.x * forward.x + forward.y * forward.y + forward.z * forward.z)
    if length > 0 then
        forward.x = forward.x / length
        forward.y = forward.y / length
        forward.z = forward.z / length
    end
    local velocity = forward * speed
    
    local timeStep = globals.TickInterval()
    local sv_gravity = client.GetConVar("sv_gravity") or 800
    local gravity = Vector3(0, 0, -sv_gravity)

    -- Debug first prediction
    if isEnemy and globals.TickCount() % 66 == 0 then
        print(string.format("Initial velocity: (%.1f, %.1f, %.1f)", velocity.x, velocity.y, velocity.z))
        print(string.format("Initial position: (%.1f, %.1f, %.1f)", position.x, position.y, position.z))
    end

    -- Add initial point
    table.insert(points, position)
    
    -- Prediction loop
    for i = 1, config.predictionSteps do
        -- Store previous position
        local prevPos = Vector3(position.x, position.y, position.z)
        
        -- Update physics
        position = position + (velocity * timeStep)
        velocity = velocity + (gravity * timeStep)
        
        -- Check for collision
        local trace = engine.TraceLine(prevPos, position, MASK_SHOT)
        
        -- Debug trace info for enemies
        if isEnemy and i == 1 and globals.TickCount() % 66 == 0 then
            print(string.format("First trace - fraction: %.2f, hit: %s", 
                trace.fraction,
                trace.entity and trace.entity:GetClass() or "none"))
        end

        if trace.fraction < 1.0 then
            position = trace.endpos
            table.insert(points, position)
            
            if weaponConfig.bounce then
                -- Reflect velocity off surface
                local normal = trace.plane
                velocity = velocity - (normal * (2 * velocity:Dot(normal)))
                
                -- Apply elasticity and friction
                velocity = velocity * config.elasticity
                velocity.x = velocity.x * (1 - config.friction)
                velocity.y = velocity.y * (1 - config.friction)
            else
                break  -- Stop on collision for non-bouncing projectiles
            end
            
            -- Debug collision for enemies
            if isEnemy and globals.TickCount() % 66 == 0 then
                print(string.format("Collision at point %d: (%.1f, %.1f, %.1f)", 
                    #points, position.x, position.y, position.z))
            end
        end
        
        table.insert(points, Vector3(position.x, position.y, position.z))
    end
    
    return points
end

-- Draw lines between consecutive WorldToScreen points
local function DrawLines(points, color)
    if #points < 2 then return end

    local lastScreen = nil
    
    -- Set line color
    draw.Color(color[1], color[2], color[3], color[4])
    
    for i = 1, #points do
        local point = points[i]
        local screen = client.WorldToScreen(point)
        
        if screen then
            if lastScreen then
                -- Draw lines with configurable thickness
                for t = -config.pathThickness, config.pathThickness do
                    draw.Line(
                        math.floor(lastScreen[1]),
                        math.floor(lastScreen[2] + t),
                        math.floor(screen[1]),
                        math.floor(screen[2] + t)
                    )
                end
            end
            lastScreen = screen
        end
    end
end

-- Draw radius circle at final point
local function DrawRadius(point, radius, color)
    local screenPos = client.WorldToScreen(point)
    if not screenPos then return end
    
    draw.Color(color[1], color[2], color[3], color[4])
    
    local radiusPoints = {}
    for i = 0, 32 do
        local angle = (i / 32) * math.pi * 2
        local radiusPoint = Vector3(
            point.x + math.cos(angle) * radius,
            point.y + math.sin(angle) * radius,
            point.z
        )
        local radiusScreen = client.WorldToScreen(radiusPoint)
        if radiusScreen then
            table.insert(radiusPoints, radiusScreen)
        end
    end
    
    -- Draw radius outline
    if #radiusPoints > 1 then
        for i = 1, #radiusPoints do
            local p1 = radiusPoints[i]
            local p2 = radiusPoints[i + 1] or radiusPoints[1]
            draw.Line(
                math.floor(p1[1]),
                math.floor(p1[2]),
                math.floor(p2[1]),
                math.floor(p2[2])
            )
        end
    end
end

-- Process single player's trajectory
local function ProcessPlayerTrajectory(player, isEnemy)
    -- Get weapon and config
    local weapon = player:GetPropEntity("m_hActiveWeapon")
    if not weapon then return end
    
    local weaponID = weapon:GetWeaponID()
    local weaponConfig = config.weapons[weaponID]
    if not weaponConfig then return end

    -- Get firing position and angles
    local startPos, angles = GetPlayerAimInfo(player)
    
    -- Get appropriate colors
    local colors = isEnemy and config.colors.enemy or config.colors.friendly
    
    -- Predict and draw trajectory
    local points = PredictTrajectory(startPos, angles, weaponConfig, player, weaponID, isEnemy)
    
    DrawLines(points, colors.path)
    
    -- Draw radius at final point if we have points
    if #points > 0 then
        DrawRadius(points[#points], weaponConfig.radius, colors.radius)
    end
    
    -- Debug print for enemy trajectories
    if isEnemy and globals.TickCount() % 66 == 0 then
        print(string.format("Enemy trajectory - Start: (%.1f, %.1f, %.1f) Angles: (%.1f, %.1f)", 
            startPos.x, startPos.y, startPos.z, angles.x, angles.y))
        print(string.format("Points generated: %d", #points))
    end
end

-- Main drawing callback
local function OnDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end
    
    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then return end
    
    -- Process all players
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player:IsAlive() and not player:IsDormant() then
            local isEnemy = player:GetTeamNumber() ~= me:GetTeamNumber()
            ProcessPlayerTrajectory(player, isEnemy)
        end
    end
end

callbacks.Register("Draw", "GrenadeTrajectory", OnDraw)
