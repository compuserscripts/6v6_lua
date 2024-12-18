-- Configuration
local friendly_color = {0, 255, 255, 185} -- Cyan color for friendly heal beams
local enemy_color = {255, 50, 50, 185} -- Red color for enemy heal beams
local enemy_only = false -- Set to true to only show enemy medics
local max_distance = 2000 -- Maximum distance to draw heal beams
local visible_only = true -- Only show heal beams for visible players

-- Team numbers in TF2
local TEAM_RED = 2
local TEAM_BLUE = 3

-- Medigun class ID for TF2
local MEDIGUN_CLASS = "CWeaponMedigun"

-- Check if a player is visible
local function IsPlayerVisible(player, localPlayer)
    if not visible_only then return true end
    
    if not player or not localPlayer then return false end
    
    local localEyePos = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = player:GetAbsOrigin() + Vector3(0, 0, 40) -- Aim for chest area
    
    local trace = engine.TraceLine(localEyePos, targetPos, MASK_SHOT)
    return trace.entity == player
end

local function DrawHealLine()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    -- Find all medics
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        -- Check if player is valid and alive
        if not player:IsValid() or not player:IsAlive() then 
            goto continue 
        end
        
        -- Skip if enemy_only is true and this is a friendly medic
        if enemy_only and player:GetTeamNumber() == localPlayer:GetTeamNumber() then
            goto continue
        end
        
        -- Check if player is too far away
        if vector.Distance(localPlayer:GetAbsOrigin(), player:GetAbsOrigin()) > max_distance then
            goto continue
        end
        
        -- Check visibility if enabled
        if not IsPlayerVisible(player, localPlayer) then
            goto continue
        end
        
        -- Get player's active weapon
        local activeWeapon = player:GetPropEntity("m_hActiveWeapon")
        if not activeWeapon or activeWeapon:GetClass() ~= MEDIGUN_CLASS then
            goto continue
        end
        
        -- Get heal target
        local healTarget = activeWeapon:GetPropEntity("m_hHealingTarget")
        if not healTarget or not healTarget:IsValid() or not healTarget:IsAlive() then
            goto continue
        end
        
        -- Check heal target visibility if enabled
        if not IsPlayerVisible(healTarget, localPlayer) then
            goto continue
        end
        
        -- Get screen positions
        local medicPos = player:GetAbsOrigin()
        medicPos.z = medicPos.z + 50 -- Adjust for player height

        local targetPos = healTarget:GetAbsOrigin()
        targetPos.z = targetPos.z + 50 -- Adjust for player height
        
        local medicScreen = client.WorldToScreen(medicPos)
        local targetScreen = client.WorldToScreen(targetPos)
        
        -- Draw line if both positions are on screen
        if medicScreen and targetScreen then
            -- Select color based on if medic is on our team
            local color = (player:GetTeamNumber() == localPlayer:GetTeamNumber()) 
                and friendly_color 
                or enemy_color
                
            draw.Color(table.unpack(color))
            draw.Line(medicScreen[1], medicScreen[2], targetScreen[1], targetScreen[2])
        end
        
        ::continue::
    end
end

-- Register callback
callbacks.Register("Draw", "DrawHealLine", DrawHealLine)
