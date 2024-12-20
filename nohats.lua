-- Configuration
local settings = {
    hide_hats = true,       -- Hide all hats
    hide_misc = true,       -- Hide misc items
    hide_botkillers = true  -- Hide botkiller attachments
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

-- Main DrawModel callback
callbacks.Register("DrawModel", function(ctx)
    if not invismat then
        InitMaterial()
        return
    end
    
    local entity = ctx:GetEntity()
    if not entity or not entity:IsValid() then return end
    
    -- Hide if entity is a cosmetic
    if IsCosmetic(entity) then
        ctx:ForcedMaterialOverride(invismat)
    end
end)

-- Cleanup on script unload
callbacks.Register("Unload", function()
    invismat = nil
end)
