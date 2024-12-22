-- Global variables for materials
local fullscreen_texture = nil
local fullscreen_material = nil
local materials_initialized = false
local base_fov = client.GetConVar("fov_desired") or 90
local fov_offset = 90 -- Start
local fov_step = 2

-- Get screen dimensions
local screen_width, screen_height = draw.GetScreenSize()

-- Initialize materials function
local function InitializeMaterials()
    if materials_initialized then return true end
    
    -- Create fullscreen texture and material
    local texture_name = "fullscreen_texture"
    fullscreen_texture = materials.CreateTextureRenderTarget(texture_name, screen_width, screen_height)
    if not fullscreen_texture then return false end

    local material_kv = string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
            $nofog          1
        }
    ]], texture_name)
    
    fullscreen_material = materials.Create("fullscreen_material", material_kv)
    if not fullscreen_material then return false end
    
    materials_initialized = true
    return true
end

-- Check if player is scoped
local function IsScoped()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return false end

    local activeWeapon = localPlayer:GetPropEntity("m_hActiveWeapon")
    if not activeWeapon then return false end

    if activeWeapon:GetClass() ~= "CTFSniperRifle" then return false end

    local chargedDamage = activeWeapon:GetPropFloat("SniperRifleLocalData", "m_flChargedDamage")
    return chargedDamage > 0
end

-- Draw scope lines
callbacks.Register("Draw", function()
    if not IsScoped() or engine.Con_IsVisible() or engine.IsGameUIVisible() then 
        return
    end
    
    -- Draw single pixel scope lines
    draw.Color(0, 0, 0, 255)
    draw.FilledRect(0, screen_height/2, screen_width, screen_height/2 + 1)
    draw.FilledRect(screen_width/2, 0, screen_width/2 + 1, screen_height)
end)

-- Block scroll wheel when scoped
callbacks.Register("SendStringCmd", function(cmd)
    if IsScoped() and (cmd:Get() == "invprev" or cmd:Get() == "invnext") then
        print("test")
        return false
    end
end)

-- Handle scroll wheel and FOV adjustments
callbacks.Register("CreateMove", function(cmd)
    if IsScoped() then
        if input.IsButtonPressed(112) or input.IsButtonDown(112) then -- MWHEEL_UP
            cmd.buttons = cmd.buttons & ~MOUSE_WHEEL_UP
            fov_offset = math.max(fov_offset - fov_step, -10)
            print("MWHEEL_UP")
        elseif input.IsButtonPressed(113) or input.IsButtonDown(113) then -- MWHEEL_DOWN
            cmd.buttons = cmd.buttons & ~MOUSE_WHEEL_DOWN
            fov_offset = math.min(fov_offset + fov_step, 120)
            print("MWHEEL_DOWN")
        end
    end
end)

-- Main render callback
callbacks.Register("PostRenderView", function(view)
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then 
        return
    end
    
    if not materials_initialized and not InitializeMaterials() then
        return
    end
    
    if not IsScoped() then return end
    
    if not fullscreen_texture or not fullscreen_material then 
        return
    end
    
    -- Set up custom view
    local customView = view
    customView.angles = engine.GetViewAngles()
    customView.fov = base_fov + fov_offset
    
    -- Render the scene to our texture
    render.Push3DView(customView, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, fullscreen_texture)
    render.ViewDrawScene(true, true, customView)
    render.PopView()
    
    -- Draw the texture to the screen
    render.DrawScreenSpaceRectangle(
        fullscreen_material,
        0, 0,
        screen_width, screen_height,
        0, 0,
        screen_width, screen_height,
        screen_width, screen_height
    )
end)

-- Cleanup on script unload
callbacks.Register("Unload", function()
    fullscreen_texture = nil
    fullscreen_material = nil
    materials_initialized = false
end)

-- Initialize materials on load
InitializeMaterials()
