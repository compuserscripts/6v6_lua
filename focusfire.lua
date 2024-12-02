-- Configuration
local CONFIG = {
    minAttackers = 2,  -- Minimum number of different attackers required to highlight target
    trackerTimeWindow = 3.0  -- How long to consider someone as being "targeted" after being shot
}

-- Pre-cache functions
local RealTime = globals.RealTime
local TraceLine = engine.TraceLine

-- Track target data
local targetData = {}
local lastLifeState = 2  -- Start with LIFE_DEAD (2)

-- Chams material
local chamsMaterial = materials.Create("targeted_chams", [[
    "VertexLitGeneric"
    {
        "$basetexture" "vgui/white_additive"
        "$bumpmap" "vgui/white_additive"
        "$color2" "[100 0.5 0.5]"
        "$selfillum" "1"
        "$selfIllumFresnel" "1"
        "$selfIllumFresnelMinMaxExp" "[0.1 0.2 0.3]"
        "$selfillumtint" "[0 0.3 0.6]"
    }
]])

-- Clean expired attackers
local function CleanExpiredAttackers(currentTime, targetInfo)
    local newAttackers = {}
    for attackerIndex, timestamp in pairs(targetInfo.attackers) do
        if currentTime - timestamp <= CONFIG.trackerTimeWindow then
            newAttackers[attackerIndex] = timestamp
        end
    end
    return newAttackers
end

-- Reset all data (used on respawn)
local function ResetTargetData()
    targetData = {}
end

-- Damage event handler
local function OnPlayerHurt(event)
    if event:GetName() ~= 'player_hurt' then return end
    
    local currentTime = RealTime()
    local victim = entities.GetByUserID(event:GetInt("userid"))
    local attacker = entities.GetByUserID(event:GetInt("attacker"))
    
    if not victim or not attacker then return end
    if victim == attacker then return end  -- Ignore self damage
    
    local victimIndex = victim:GetIndex()
    if not targetData[victimIndex] then
        targetData[victimIndex] = {
            attackers = {},
            isMultiTargeted = false
        }
    end
    
    -- Update attackers list
    targetData[victimIndex].attackers = CleanExpiredAttackers(currentTime, targetData[victimIndex])
    targetData[victimIndex].attackers[attacker:GetIndex()] = currentTime
    
    -- Check if being targeted by enough different players
    local attackerCount = 0
    for _ in pairs(targetData[victimIndex].attackers) do
        attackerCount = attackerCount + 1
    end
    
    targetData[victimIndex].isMultiTargeted = (attackerCount >= CONFIG.minAttackers)
end

-- Main chams function
local function OnDrawModel(ctx)
    local entity = ctx:GetEntity()
    if not entity or not entity:IsPlayer() then return end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or entity:GetTeamNumber() == localPlayer:GetTeamNumber() then return end
    
    -- Clean up expired data
    local currentTime = RealTime()
    local targetInfo = targetData[entity:GetIndex()]
    if targetInfo then
        targetInfo.attackers = CleanExpiredAttackers(currentTime, targetInfo)
        
        -- Update multi-targeted status
        local attackerCount = 0
        for _ in pairs(targetInfo.attackers) do
            attackerCount = attackerCount + 1
        end
        targetInfo.isMultiTargeted = (attackerCount >= CONFIG.minAttackers)
        
        -- Apply chams if multi-targeted
        if targetInfo.isMultiTargeted then
            ctx:ForcedMaterialOverride(chamsMaterial)
        end
    end
end

-- Monitor respawns to reset data
local function OnDraw()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    local currentLifeState = localPlayer:GetPropInt("m_lifeState")
    if lastLifeState == 2 and currentLifeState == 0 then  -- If we went from dead to alive
        ResetTargetData()
        if chamsMaterial then
            chamsMaterial:SetMaterialVarFlag(MATERIAL_VAR_IGNOREZ, false)
        end
    end
    lastLifeState = currentLifeState
end

-- Register callbacks
callbacks.Register("FireGameEvent", "MultiTargetTracker", OnPlayerHurt)
callbacks.Register("DrawModel", "MultiTargetChams", OnDrawModel)
callbacks.Register("Draw", "MultiTargetRespawnCheck", OnDraw)
callbacks.Register("Unload", "MultiTargetCleanup", ResetTargetData)
