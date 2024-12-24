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
    
    -- Get angles
    local pitch = player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[0]") or 0
    local yaw = player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[1]") or 0
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
    
    -- Get sticky charge time and adjust speed
    local speed = weaponConfig.speed
    if weaponID == TF_WEAPON_PIPEBOMBLAUNCHER then
        local weapon = player:GetPropEntity("m_hActiveWeapon")
        if weapon then
            local chargeBeginTime = weapon:GetPropFloat("m_flChargeBeginTime") or 0
            if isEnemy and globals.TickCount() % 66 == 0 then
                print("Charge Begin Time: " .. chargeBeginTime)
            end
            
            if chargeBeginTime ~= 0 then
                local chargeTime = globals.CurTime() - chargeBeginTime
                -- Base speed (900) + charge bonus (up to 1500 over 4 seconds)
                speed = 900 + math.min(math.max(chargeTime / 4, 0), 1) * 1500
                
                if isEnemy and globals.TickCount() % 66 == 0 then
                    print(string.format("Charge time: %.2f, Speed: %.1f", chargeTime, speed))
                end
            end
        end
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
