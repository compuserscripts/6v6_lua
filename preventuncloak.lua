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

    -- If cloak is getting low (below 16%), prevent movement to allow recharge
    -- 16% chosen because it gives enough buffer to prevent accidental uncloaking
    if cloakMeter < 16 then
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
