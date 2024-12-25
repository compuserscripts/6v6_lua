-- Constants for fine-tuning
local KEY_BIND = KEY_R
local MIN_RELEASE_HEIGHT = 384     -- Double again for extreme safety
local VELOCITY_SCALE = 0.4        -- Double scaling factor
local RELEASE_TICKS = 20          -- Much more aggressive tick threshold
local MAX_PREDICTION_TICKS = 24   -- Shorter prediction window
local TICK_INTERVAL = globals.TickInterval()
local GRAVITY = client.GetConVar("sv_gravity") or 800 -- default is 800

-- State variables
local isJumpbugArmed = false
local crouchReleased = false
local lastKeyState = false
local initialHeight = 0

-- Calculate release height based on velocity
local function getTargetReleaseHeight(velocity)
    local speed = math.abs(velocity.z)
    return math.max(MIN_RELEASE_HEIGHT, MIN_RELEASE_HEIGHT + speed * VELOCITY_SCALE)
end

-- Predict position after n ticks
local function predictPosition(origin, velocity, ticks)
    local time = ticks * TICK_INTERVAL
    local zVel = velocity.z - (GRAVITY * time)
    local zPos = origin.z + (velocity.z * time) - (0.5 * GRAVITY * time * time)
    return Vector3(
        origin.x + (velocity.x * time),
        origin.y + (velocity.y * time),
        zPos
    ), Vector3(velocity.x, velocity.y, zVel)
end

-- Get player state with enhanced prediction
local function getPlayerInfo()
    local player = entities.GetLocalPlayer()
    if not player then return nil end
    
    local origin = player:GetAbsOrigin()
    local velocity = player:EstimateAbsVelocity()
    local flags = player:GetPropInt("m_fFlags")
    local isOnGround = (flags & FL_ONGROUND) == 1
    
    -- Ground detection with more trace points
    local minDist = 9999
    local offsets = {
        {0, 0},                               -- Center
        {4, 0}, {-4, 0}, {0, 4}, {0, -4},    -- Inner ring
        {4, 4}, {-4, 4}, {4, -4}, {-4, -4},  -- Inner corners
        {8, 0}, {-8, 0}, {0, 8}, {0, -8},    -- Outer ring
        {8, 8}, {-8, 8}, {8, -8}, {-8, -8},  -- Outer corners
    }
    
    for _, offset in ipairs(offsets) do
        local traceStart = origin + Vector3(offset[1], offset[2], 1)
        local traceEnd = traceStart - Vector3(0, 0, 256)
        
        local trace = engine.TraceLine(
            traceStart,
            traceEnd,
            MASK_PLAYERSOLID
        )
        
        if trace.fraction < 1 then
            minDist = math.min(minDist, (traceStart.z - trace.endpos.z) * trace.fraction)
        end
    end
    
    -- Predict ticks until ground
    local ticksToGround = 0
    local testPos = origin
    local testVel = velocity
    
    while ticksToGround < 32 do
        testPos, testVel = predictPosition(origin, velocity, ticksToGround)
        
        local traceStart = testPos + Vector3(0, 0, 1)
        local traceEnd = traceStart - Vector3(0, 0, 8)
        
        local trace = engine.TraceLine(
            traceStart,
            traceEnd,
            MASK_PLAYERSOLID
        )
        
        if trace.fraction < 1 then
            break
        end
        
        ticksToGround = ticksToGround + 1
    end

    return {
        origin = origin,
        velocity = velocity,
        isOnGround = isOnGround,
        groundDist = minDist,
        ticksToGround = ticksToGround
    }
end

-- Debug tracking with essential info
local function logEvent(info, event, cmd)
    if event == "START" then
        initialHeight = info.origin.z
        print("\n=== JUMPBUG SEQUENCE START ===")
        print(string.format("Starting Height: %.1f | Velocity: %.1f", info.origin.z, info.velocity.z))
    elseif event == "END" or event == "FAIL" then
        print(string.format("\n=== JUMPBUG SEQUENCE %s ===", event))
        print(string.format("Height Diff: %.1f", info.origin.z - initialHeight))
    end
    
    if event == "TICK" and info.groundDist > 100 then return end
    
    local buttons = cmd and cmd.buttons or 0
    local hasJump = (buttons & IN_JUMP) == IN_JUMP
    local hasDuck = (buttons & IN_DUCK) == IN_DUCK
    local targetHeight = getTargetReleaseHeight(info.velocity)
    
    print(string.format("[Tick %d] %s | Height: %.1f | Vel Z: %.1f | Release At: %.1f | Ticks to Ground: %d | Jump: %s | Duck: %s",
        globals.TickCount(),
        event,
        info.groundDist,
        info.velocity.z,
        targetHeight,
        info.ticksToGround,
        tostring(hasJump),
        tostring(hasDuck)
    ))
end

-- Core jumpbug logic
local function onCreateMove(cmd)
    local info = getPlayerInfo()
    if not info then return end

    -- Handle key press
    local currentKeyState = input.IsButtonDown(KEY_BIND)
    local keyPressed = currentKeyState and not lastKeyState
    lastKeyState = currentKeyState

    -- Start sequence
    if keyPressed and not info.isOnGround then
        isJumpbugArmed = true
        crouchReleased = false
        cmd.buttons = cmd.buttons | IN_DUCK
        logEvent(info, "START", cmd)
        return
    end

    -- Handle the jumpbug sequence
    if isJumpbugArmed then
        -- Calculate target release height
        local targetHeight = getTargetReleaseHeight(info.velocity)
        
        -- Release when approaching ground
        if not crouchReleased and (info.ticksToGround <= RELEASE_TICKS or info.groundDist <= targetHeight) then
            crouchReleased = true
            cmd.buttons = cmd.buttons & ~IN_DUCK
            logEvent(info, "CROUCH_RELEASE", cmd)
        end

        -- Jump handling
        if crouchReleased then
            cmd.buttons = cmd.buttons | IN_JUMP
            
            if info.isOnGround then
                isJumpbugArmed = false
                logEvent(info, "END", cmd)
            else
                logEvent(info, "JUMPING", cmd)
            end
        else
            logEvent(info, "TICK", cmd)
        end

        -- Maintain crouch state
        if crouchReleased then
            cmd.buttons = cmd.buttons & ~IN_DUCK
        else
            cmd.buttons = cmd.buttons | IN_DUCK
        end
    end
end

-- Simple UI
local function onDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end
    
    local text = isJumpbugArmed and "JUMPBUG ACTIVE" or "JUMPBUG READY"
    local color = isJumpbugArmed and {0, 255, 0, 255} or {255, 255, 255, 255}
    
    draw.Color(table.unpack(color))
    draw.Text(10, 10, text)
end

-- Register callbacks
callbacks.Register("CreateMove", "jumpbug_logic", onCreateMove)
callbacks.Register("Draw", "jumpbug_ui", onDraw)
