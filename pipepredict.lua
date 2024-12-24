-- Configuration
local config = {
    -- Style settings (only enemy colors needed now)
    colors = {
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
            bounce = true      -- Pipes can bounce
        },
        [TF_WEAPON_PIPEBOMBLAUNCHER] = {
            speed = 925.38,
            gravity = 800,
            radius = 146,
            bounce = false     -- Stickies don't bounce
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
local function PredictTrajectory(startPos, angles, weaponConfig)
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
    local velocity = forward * weaponConfig.speed
    local timeStep = globals.TickInterval()
    local sv_gravity = client.GetConVar("sv_gravity") or 800
    local gravity = Vector3(0, 0, -sv_gravity)

    -- Add initial point
    table.insert(points, position)
    
    -- Prediction loop
    for i = 1, config.predictionSteps do
        local prevPos = Vector3(position.x, position.y, position.z)
        
        -- Update physics
        position = position + (velocity * timeStep)
        velocity = velocity + (gravity * timeStep)
        
        -- Check for collision
        local trace = engine.TraceLine(prevPos, position, MASK_SHOT)

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

-- Process enemy trajectory
local function ProcessEnemyTrajectory(player)
    -- Get weapon and config
    local weapon = player:GetPropEntity("m_hActiveWeapon")
    if not weapon then return end
    
    local weaponID = weapon:GetWeaponID()
    local weaponConfig = config.weapons[weaponID]
    if not weaponConfig then return end

    -- Get firing position and angles
    local startPos, angles = GetPlayerAimInfo(player)
    
    -- Predict and draw trajectory
    local points = PredictTrajectory(startPos, angles, weaponConfig)
    
    DrawLines(points, config.colors.enemy.path)
    
    -- Draw radius at final point if we have points
    if #points > 0 then
        DrawRadius(points[#points], weaponConfig.radius, config.colors.enemy.radius)
    end
end

-- Main drawing callback
local function OnDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end
    
    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then return end
    
    -- Process only enemy players
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player:IsAlive() and not player:IsDormant() 
           and player:GetTeamNumber() ~= me:GetTeamNumber() then
            ProcessEnemyTrajectory(player)
        end
    end
end

callbacks.Register("Draw", "GrenadeTrajectory", OnDraw)
