-- Global variables for materials
local scope_tex = nil
local scope_material = nil
local materials_initialized = false
local base_fov = client.GetConVar("fov_desired") or 90
local fov_offset = 0 -- Start at no offset
local newZoomStyle = true -- Flag to toggle between zoom styles
local zoom_step = 2 -- Default step for scrollwheel style
local zoom_step_new = 1.75 -- Default step for movement keys style
local storedCustomView = nil -- Store the custom view for hitboxes

-- New zoom lock variables
local zoom_locked = false
local warning_alpha = 0
local warning_fade_start = 0

-- Colors for hitbox ESP
local TEAM_COLORS = {
    [2] = {r = 87, g = 160, b = 211, a = 100},  -- BLU
    [3] = {r = 237, g = 84, b = 84, a = 100}    -- RED
}

-- Get screen dimensions
local screen_width, screen_height = draw.GetScreenSize()

-- Cleanup function for materials and textures
local function CleanupMaterials()
    scope_tex = nil
    scope_material = nil
    materials_initialized = false
end

-- Initialize materials function
local function InitializeMaterials()
    if materials_initialized then return true end
    
    -- Create fullscreen texture and material
    local texture_name = "scope_tex"
    scope_tex = materials.CreateTextureRenderTarget(texture_name, screen_width, screen_height)
    if not scope_tex then return false end

    local material_kv = string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
            $nofog          1
        }
    ]], texture_name)
    
    scope_material = materials.Create("scope_material", material_kv)
    if not scope_material then return false end
    
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

-- Draw scope lines and hitboxes
callbacks.Register("Draw", function()
    -- Don't draw if menus are open or not scoped
    if not IsScoped() or engine.Con_IsVisible() or engine.IsGameUIVisible() or input.IsButtonDown(KEY_ESCAPE) then 
        CleanupMaterials() -- Clean up materials when closing
        return
    end

    -- Draw single pixel scope lines
    draw.Color(255, 255, 255, 255)
    draw.FilledRect(0, screen_height/2, screen_width, screen_height/2 + 1)
    draw.FilledRect(screen_width/2, 0, screen_width/2 + 1, screen_height)

    -- Draw warning message if needed
    if warning_alpha > 0 then
        local current_time = globals.RealTime()
        local time_since_warning = current_time - warning_fade_start
        if time_since_warning < 1.0 then
            warning_alpha = math.floor(math.max(0, 255 * (1.0 - time_since_warning)))
            draw.Color(255, 0, 0, warning_alpha)
            draw.SetFont(draw.CreateFont("Arial", 20, 800))
            local warning_text = "Zoom Locked!"
            local text_w, text_h = draw.GetTextSize(warning_text)
            draw.Text(screen_width - text_w - 20, screen_height - text_h - 20, warning_text)
        else
            warning_alpha = 0
        end
    end
    
    -- Draw hitboxes
    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    
    if localPlayer and storedCustomView then
        for _, player in pairs(players) do
            if player:IsAlive() and not player:IsDormant() and player:GetIndex() ~= localPlayer:GetIndex() then
                local hitboxes = player:GetHitboxes()
                if hitboxes then
                    local headHitbox = hitboxes[1]  -- Head hitbox
                    if headHitbox then
                        local mins = headHitbox[1]
                        local maxs = headHitbox[2]

                        -- Get all 8 corners of the hitbox cube
                        local corners = {
                            Vector3(mins.x, mins.y, mins.z), -- Bottom front left
                            Vector3(maxs.x, mins.y, mins.z), -- Bottom front right
                            Vector3(mins.x, maxs.y, mins.z), -- Bottom back left 
                            Vector3(maxs.x, maxs.y, mins.z), -- Bottom back right
                            Vector3(mins.x, mins.y, maxs.z), -- Top front left
                            Vector3(maxs.x, mins.y, maxs.z), -- Top front right
                            Vector3(mins.x, maxs.y, maxs.z), -- Top back left
                            Vector3(maxs.x, maxs.y, maxs.z)  -- Top back right
                        }

                        -- Project corners to screen space using stored custom view
                        local screenCorners = {}
                        local allCornersVisible = true

                        for _, corner in ipairs(corners) do
                            local screenPos = client.WorldToScreen(corner, storedCustomView)
                            if not screenPos then
                                allCornersVisible = false
                                break
                            end
                            table.insert(screenCorners, screenPos)
                        end

                        -- Draw the box if all corners are visible
                        if allCornersVisible then
                            -- Find the bounding box of all projected corners
                            local left = math.huge
                            local right = -math.huge
                            local top = math.huge
                            local bottom = -math.huge

                            for _, corner in ipairs(screenCorners) do
                                left = math.min(left, corner[1])
                                right = math.max(right, corner[1])
                                top = math.min(top, corner[2])
                                bottom = math.max(bottom, corner[2])
                            end

                            -- Draw the box
                            local teamColor = TEAM_COLORS[player:GetTeamNumber()]
                            if teamColor then
                                draw.Color(teamColor.r, teamColor.g, teamColor.b, teamColor.a)
                                draw.FilledRect(left, top, right, bottom)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Block scroll wheel when scoped
callbacks.Register("SendStringCmd", function(cmd)
    if IsScoped() and (cmd:Get() == "invprev" or cmd:Get() == "invnext") then
        return false
    end
end)

-- Handle zoom controls and FOV adjustments
callbacks.Register("CreateMove", function(cmd)
    if IsScoped() then
        if newZoomStyle then
            if input.IsButtonPressed(113) then -- MWHEEL_DOWN
                zoom_locked = true
                warning_alpha = 255
                warning_fade_start = globals.RealTime()
            elseif input.IsButtonPressed(112) then -- MWHEEL_UP
                zoom_locked = false
            end

            -- Only allow zoom adjustments if not locked
            if not zoom_locked then
                -- Zoom in when forward (W) and right (D) are held
                if (cmd.buttons & IN_FORWARD) ~= 0 and (cmd.buttons & IN_MOVERIGHT) ~= 0 then
                    fov_offset = math.max(fov_offset - zoom_step_new, -80)
                end
                
                -- Zoom out when backward (S) and left (A) are held
                if (cmd.buttons & IN_BACK) ~= 0 and (cmd.buttons & IN_MOVELEFT) ~= 0 then
                    fov_offset = math.min(fov_offset + zoom_step_new, 30)
                end
            elseif ((cmd.buttons & IN_FORWARD) ~= 0 and (cmd.buttons & IN_MOVERIGHT) ~= 0) or 
                   ((cmd.buttons & IN_BACK) ~= 0 and (cmd.buttons & IN_MOVELEFT) ~= 0) then
                -- Show warning if trying to adjust while locked
                warning_alpha = 255
                warning_fade_start = globals.RealTime()
            end
        else
            -- Original scrollwheel style
            if input.IsButtonPressed(112) or input.IsButtonDown(112) then -- MWHEEL_UP
                cmd.buttons = cmd.buttons & ~MOUSE_WHEEL_UP
                fov_offset = math.max(fov_offset - zoom_step, -10)
            elseif input.IsButtonPressed(113) or input.IsButtonDown(113) then -- MWHEEL_DOWN
                cmd.buttons = cmd.buttons & ~MOUSE_WHEEL_DOWN
                fov_offset = math.min(fov_offset + zoom_step, 120)
            end
        end
    end
end)

-- Main render callback
callbacks.Register("PostRenderView", function(view)
    if engine.Con_IsVisible() or engine.IsGameUIVisible() or input.IsButtonDown(KEY_ESCAPE) then 
        CleanupMaterials()
        return
    end
    
    if not materials_initialized and not InitializeMaterials() then
        return
    end
    
    if not IsScoped() then 
        CleanupMaterials()
        return 
    end
    
    if not scope_tex or not scope_material then 
        return
    end
    
    -- Set up custom view
    local customView = view
    customView.angles = engine.GetViewAngles()
    customView.fov = base_fov + fov_offset
    storedCustomView = customView -- Store for hitbox drawing
    
    -- Render the scene to our texture
    render.Push3DView(customView, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, scope_tex)
    render.ViewDrawScene(true, true, customView)
    render.PopView()
    
    -- Draw the texture to the screen
    render.DrawScreenSpaceRectangle(
        scope_material,
        0, 0,
        screen_width, screen_height,
        0, 0,
        screen_width, screen_height,
        screen_width, screen_height
    )
end)

-- Cleanup on script unload
callbacks.Register("Unload", function()
    CleanupMaterials()
    storedCustomView = nil
end)

-- Initialize materials on load
InitializeMaterials()
