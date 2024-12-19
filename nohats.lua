-- Configuration
local settings = {
    hide_hats = true,       -- Hide all hats
    hide_misc = true,       -- Hide misc items
    hide_botkillers = true  -- Hide botkiller attachments
}

-- Visibility check caching
local nextVisCheck = {}
local visibilityCache = {}
local vecCache = {
    eyePos = Vector3(0, 0, 0),
    viewOffset = Vector3(0, 0, 0)
}

-- Invisible material for hiding models
local invismat = nil

-- Initialize invisible material
local function InitMaterial()
    if not invismat then
        invismat = materials.Create("invisible_cosmetics", [[
            VertexLitGeneric
            {
                $basetexture    "vgui/white"
                $no_draw        1
            }
        ]])
    end
end

-- Optimized visibility check from ammo script
local function IsVisible(entity)
    if not entity then return false end
    
    local pos = entity:GetAbsOrigin()
    local id = math.floor(pos.x) .. math.floor(pos.y) .. math.floor(pos.z)
    local curTick = globals.TickCount()
    
    if nextVisCheck[id] and curTick < nextVisCheck[id] then
        return visibilityCache[id]
    end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return false end
    
    vecCache.viewOffset = localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    vecCache.eyePos = localPlayer:GetAbsOrigin()
    vecCache.eyePos.x = vecCache.eyePos.x + vecCache.viewOffset.x
    vecCache.eyePos.y = vecCache.eyePos.y + vecCache.viewOffset.y
    vecCache.eyePos.z = vecCache.eyePos.z + vecCache.viewOffset.z
    
    local trace = engine.TraceLine(vecCache.eyePos, pos, MASK_SHOT_HULL)
    
    visibilityCache[id] = trace.fraction > 0.99
    nextVisCheck[id] = curTick + 3
    
    return visibilityCache[id]
end

-- Check if entity is a cosmetic item
local function IsCosmetic(entity)
    if not entity then return false end
    
    local class = entity:GetClass()
    if not class then return false end
    
    -- Check for hat/misc classes
    if class == "CTFWearable" then
        return true
    end
    
    -- Check for botkiller attachments
    if settings.hide_botkillers and class == "CTFWearableDemoShield" then
        return true
    end
    
    return false
end

-- Check if entity is attached to a player and get owner
local function GetAttachedPlayer(entity)
    if not entity then return nil end
    
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player and player:IsValid() then
            -- Check move children chain
            local moveChild = player:GetMoveChild()
            while moveChild do
                if moveChild == entity then 
                    return player
                end
                moveChild = moveChild:GetMovePeer()
            end
        end
    end
    
    return nil
end

-- Main DrawModel callback
callbacks.Register("DrawModel", function(ctx)
    if not invismat then
        InitMaterial()
        return
    end
    
    local entity = ctx:GetEntity()
    if not entity or not entity:IsValid() then return end
    
    -- Check if entity is a cosmetic
    if IsCosmetic(entity) then
        local ownerPlayer = GetAttachedPlayer(entity)
        if ownerPlayer then
            -- Only hide cosmetics on visible players
            if IsVisible(ownerPlayer) then
                ctx:ForcedMaterialOverride(invismat)
            end
        end
    end
end)

-- Cleanup on script unload
callbacks.Register("Unload", function()
    invismat = nil
    nextVisCheck = {}
    visibilityCache = {}
    vecCache = {
        eyePos = Vector3(0, 0, 0),
        viewOffset = Vector3(0, 0, 0)
    }
end)
