-- Sticky Chams Lite
-- A lightweight version that only highlights enemies near stickies

-- Configuration
local STICKY_CHAMS_DISTANCE = 166 -- Max distance for chams in hammer units
local TARGET_SEARCH_RADIUS = 146 * 4 -- Search radius for targets

-- State tracking
local stickies = {}
local chamsMaterial = nil

-- Add this function to check if the local player is a Demoman
local function IsDemoman()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return false end
    return localPlayer:GetPropInt("m_iClass") == 4  -- 4 is Demoman's class ID
end

-- Initialize chams material
local function InitializeChams()
    if not chamsMaterial then
        chamsMaterial = materials.Create("sticky_target_chams", [[
            "UnlitGeneric"
            {
                "$basetexture" "vgui/white_additive"
                "$color2" "[0.5 0 1]"
            }
        ]])
    end
end

-- Helper vector functions with proper nil checks
local function SubtractVectors(vec1, vec2)
    if not vec1 or not vec2 then return Vector3(0,0,0) end
    return Vector3(
        vec1.x - vec2.x,
        vec1.y - vec2.y,
        vec1.z - vec2.z
    )
end

-- Check if player is visible from sticky position
local function CheckPlayerVisibility(startPos, player)
    if not player:IsValid() or not player:IsAlive() or player:IsDormant() then
        return false
    end

    local hitboxes = player:GetHitboxes()
    if not hitboxes then return false end
    
    local spine = hitboxes[4]
    if not spine then return false end
    
    local spineCenter = Vector3(
        (spine[1].x + spine[2].x) / 2,
        (spine[1].y + spine[2].y) / 2,
        (spine[1].z + spine[2].z) / 2
    )
    
    local trace = engine.TraceLine(startPos, spineCenter, MASK_SHOT)
    return trace.fraction > 0.99 or trace.entity == player
end

-- Find players within range of a sticky
local function FindPlayersNearSticky(sticky)
    if not sticky or not sticky:IsValid() or sticky:IsDormant() then
        return {}
    end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return {} end
    
    local stickyPos = sticky:GetAbsOrigin()
    if not stickyPos then return {} end
    
    local nearbyPlayers = {}
    
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player:IsValid() and player:IsAlive() and not player:IsDormant() and
           player:GetTeamNumber() ~= localPlayer:GetTeamNumber() then
            
            local playerPos = player:GetAbsOrigin()
            if playerPos then
                local delta = SubtractVectors(playerPos, stickyPos)
                local dist = delta:Length()
                
                if dist <= TARGET_SEARCH_RADIUS and CheckPlayerVisibility(stickyPos, player) then
                    table.insert(nearbyPlayers, {player = player, distance = dist})
                end
            end
        end
    end
    
    return nearbyPlayers
end

-- Update the list of active stickies
local function UpdateStickies()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    -- Clean up invalid stickies from our list
    for i = #stickies, 1, -1 do
        if not stickies[i]:IsValid() or stickies[i]:IsDormant() then
            table.remove(stickies, i)
        end
    end
    
    -- Find and add new stickies
    local projectiles = entities.FindByClass("CTFGrenadePipebombProjectile")
    for _, proj in pairs(projectiles) do
        if proj:IsValid() and not proj:IsDormant() then
            local thrower = proj:GetPropEntity("m_hThrower")
            local isSticky = proj:GetPropInt("m_iType") == 1
            
            if thrower and thrower == localPlayer and isSticky then
                local found = false
                for _, existing in pairs(stickies) do
                    if existing == proj then
                        found = true
                        break
                    end
                end
                
                if not found then
                    table.insert(stickies, proj)
                end
            end
        end
    end
end

-- Get all targets near any sticky
local function GetAllNearbyTargets()
    local targets = {}
    local targetMap = {}  -- Used to avoid duplicates
    
    for _, sticky in ipairs(stickies) do
        if sticky and sticky:IsValid() and not sticky:IsDormant() then
            -- Only consider stationary stickies
            local vel = sticky:EstimateAbsVelocity()
            if vel:Length() < 1 then
                local nearbyPlayers = FindPlayersNearSticky(sticky)
                
                for _, playerInfo in ipairs(nearbyPlayers) do
                    local player = playerInfo.player
                    if player and not targetMap[player:GetIndex()] then
                        targetMap[player:GetIndex()] = true
                        table.insert(targets, player)
                    end
                end
            end
        end
    end
    
    return targets
end

-- Initialize
InitializeChams()

-- Main update callback
callbacks.Register("CreateMove", function(cmd)
    if not IsDemoman() then return end
    UpdateStickies()
end)

-- DrawModel callback for chams
callbacks.Register("DrawModel", function(ctx)
    if not IsDemoman() or not chamsMaterial then return end
    
    local entity = ctx:GetEntity()
    if not entity or not entity:IsValid() or entity:IsDormant() then return end
    
    -- Only apply chams to players
    if entity:GetClass() == "CTFPlayer" then
        local localPlayer = entities.GetLocalPlayer()
        if not localPlayer then return end
        
        -- Only highlight enemies
        if entity:GetTeamNumber() == localPlayer:GetTeamNumber() then return end
        
        local targets = GetAllNearbyTargets()
        for _, target in ipairs(targets) do
            if entity == target then
                ctx:ForcedMaterialOverride(chamsMaterial)
                break
            end
        end
    end
end)

-- Debug callback (optional, can be removed)
callbacks.Register("Draw", function()
    if not IsDemoman() then return end
    
    -- Draw sticky count in top-left corner
    local validCount = 0
    for _, sticky in ipairs(stickies) do
        if sticky and sticky:IsValid() and not sticky:IsDormant() then
            local vel = sticky:EstimateAbsVelocity()
            if vel:Length() < 1 then
                validCount = validCount + 1
            end
        end
    end
    
    draw.Color(255, 255, 255, 255)
    draw.Text(10, 10, string.format("Active Stickies: %d", validCount))
    
    -- Draw targets count - also change this color to match purple theme
    draw.Color(128, 0, 255, 255)
    draw.Text(10, 25, string.format("Targets in Range: %d", #targets))
end)

-- Cleanup on unload
callbacks.Register("Unload", function()
    stickies = {}
    chamsMaterial = nil
end)