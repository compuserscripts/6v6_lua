-- Create a semi-random threshold that changes periodically
local function getRandomThreshold()
    -- Get current time in seconds to use as seed
    local timeSeed = math.floor(globals.RealTime())
    -- Change threshold every 2 seconds
    local periodSeed = math.floor(timeSeed / 2)
    -- Use the time-based seed to generate a random value between 15-17
    engine.RandomSeed(periodSeed)
    return 15 + engine.RandomFloat(0, 2)
end

local function cloakManager(cmd)
    -- Get local player
    local player = entities.GetLocalPlayer()
    if not player then return end

    -- Check if player is a spy and is cloaked
    if player:GetPropInt("m_iClass") ~= 8 or not player:InCond(TFCond_Cloaked) then 
        return 
    end

    -- Get cloak meter
    local cloakMeter = player:GetPropFloat("m_flCloakMeter") 
    
    -- Get current threshold (changes every 2 seconds)
    local threshold = getRandomThreshold()

    -- If cloak is getting low, prevent movement to allow recharge
    if cloakMeter < threshold then
        -- Clear movement buttons
        cmd.forwardmove = 0
        cmd.sidemove = 0
        cmd.upmove = 0
        
        -- Clear movement keys from buttons
        cmd.buttons = cmd.buttons & ~IN_FORWARD
        cmd.buttons = cmd.buttons & ~IN_BACK
        cmd.buttons = cmd.buttons & ~IN_MOVELEFT
        cmd.buttons = cmd.buttons & ~IN_MOVERIGHT
    end
end

-- Register the callback
callbacks.Register("CreateMove", "cloak_manager", cloakManager)

-- Cleanup on unload
callbacks.Register("Unload", function()
    callbacks.Unregister("CreateMove", "cloak_manager")
end)
