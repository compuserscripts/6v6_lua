-- Configuration
local settings = {
    hide_hats = true,       -- Hide all hats
    hide_misc = true,       -- Hide misc items
    hide_botkillers = true  -- Hide botkiller attachments
}

-- Invisible material for hiding models
local invisibleMaterial = nil

-- Initialize invisible material
local function InitMaterial()
    if not invisibleMaterial then
        invisibleMaterial = materials.Create("invisible_cosmetics", [[
            VertexLitGeneric
            {
                $basetexture    "vgui/white"
                $no_draw        1
            }
        ]])
    end
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

-- Check if entity is attached to a player
local function IsAttachedToPlayer(entity)
    if not entity then return false end
    
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player and player:IsValid() then
            -- Check move children chain
            local moveChild = player:GetMoveChild()
            while moveChild do
                if moveChild == entity then 
                    return true 
                end
                moveChild = moveChild:GetMovePeer()
            end
        end
    end
    
    return false
end

-- Main DrawModel callback
callbacks.Register("DrawModel", function(ctx)
    if not invisibleMaterial then
        InitMaterial()
        return
    end
    
    local entity = ctx:GetEntity()
    if not entity or not entity:IsValid() then return end
    
    -- Check if entity is a cosmetic and attached to a player
    if IsCosmetic(entity) and IsAttachedToPlayer(entity) then
        ctx:ForcedMaterialOverride(invisibleMaterial)
    end
end)

-- Cleanup on script unload
callbacks.Register("Unload", function()
    invisibleMaterial = nil
end)
