-- Global variables for materials and rendering
local ScopeRenderer = {
    materials = {
        texture = nil,
        material = nil
    },
    screen = {
        width = 0,
        height = 0
    },
    zoom = {
        base_fov = client.GetConVar("fov_desired") or 90,
        offset = 0,
        step = 2,
        step_new = 1.75,
        locked = false,
        warning = {
            alpha = 0,
            fade_start = 0
        }
    },
    view = {
        custom = nil,
        new_style = true
    }
}

-- Team colors for ESP
local TEAM_COLORS = {
    [2] = {r = 87, g = 160, b = 211, a = 100},  -- BLU
    [3] = {r = 237, g = 84, b = 84, a = 100}    -- RED
}

-- Initialize materials only once when needed
function ScopeRenderer:InitializeMaterials()
    if self.materials.material then return true end
    
    -- Get current screen dimensions
    self.screen.width, self.screen.height = draw.GetScreenSize()
    
    -- Create fullscreen texture 
    local texture_name = "scope_tex_persistent"
    self.materials.texture = materials.CreateTextureRenderTarget(texture_name, self.screen.width, self.screen.height)
    if not self.materials.texture then return false end

    -- Create persistent material
    local material_kv = string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
            $nofog          1
        }
    ]], texture_name)
    
    self.materials.material = materials.Create("scope_material_persistent", material_kv)
    if not self.materials.material then return false end
    
    return true
end

-- Check if player is scoped
function ScopeRenderer:IsScoped()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return false end

    local activeWeapon = localPlayer:GetPropEntity("m_hActiveWeapon")
    if not activeWeapon then return false end

    if activeWeapon:GetClass() ~= "CTFSniperRifle" then return false end

    local chargedDamage = activeWeapon:GetPropFloat("SniperRifleLocalData", "m_flChargedDamage")
    return chargedDamage > 0
end

-- Draw scope overlay and hitboxes
callbacks.Register("Draw", function()
    -- Initialize local player first
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    -- Early exit conditions
    if not ScopeRenderer:IsScoped() or 
       engine.Con_IsVisible() or 
       engine.IsGameUIVisible() or 
       input.IsButtonDown(KEY_ESCAPE) then return end
       
    -- Ensure we have proper screen dimensions
    ScopeRenderer.screen.width, ScopeRenderer.screen.height = draw.GetScreenSize()
    
    -- Set default color state
    draw.Color(255, 255, 255, 255)

    -- Set color for scope lines
    draw.Color(255, 255, 255, 255) -- White color for better visibility
    -- Draw scope lines
    draw.FilledRect(0, ScopeRenderer.screen.height/2, ScopeRenderer.screen.width, ScopeRenderer.screen.height/2 + 1)
    draw.FilledRect(ScopeRenderer.screen.width/2, 0, ScopeRenderer.screen.width/2 + 1, ScopeRenderer.screen.height)

    -- Draw zoom lock warning
    if ScopeRenderer.zoom.warning.alpha > 0 then
        local current_time = globals.RealTime()
        local time_since_warning = current_time - ScopeRenderer.zoom.warning.fade_start
        if time_since_warning < 1.0 then
            ScopeRenderer.zoom.warning.alpha = math.floor(math.max(0, 255 * (1.0 - time_since_warning)))
            draw.Color(255, 0, 0, ScopeRenderer.zoom.warning.alpha)
            draw.SetFont(draw.CreateFont("Arial", 20, 800))
            local warning_text = "Zoom Locked!"
            local text_w, text_h = draw.GetTextSize(warning_text)
            draw.Text(ScopeRenderer.screen.width - text_w - 20, ScopeRenderer.screen.height - text_h - 20, warning_text)
        else
            ScopeRenderer.zoom.warning.alpha = 0
        end
    end

    -- Draw hitboxes
    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    
    if localPlayer and ScopeRenderer.view.custom then
        for _, player in pairs(players) do
            if player:IsAlive() and not player:IsDormant() and player:GetIndex() ~= localPlayer:GetIndex() then
                local hitboxes = player:GetHitboxes()
                if hitboxes then
                    local headHitbox = hitboxes[1]
                    if headHitbox then
                        local mins = headHitbox[1]
                        local maxs = headHitbox[2]

                        local corners = {
                            Vector3(mins.x, mins.y, mins.z),
                            Vector3(maxs.x, mins.y, mins.z),
                            Vector3(mins.x, maxs.y, mins.z),
                            Vector3(maxs.x, maxs.y, mins.z),
                            Vector3(mins.x, mins.y, maxs.z),
                            Vector3(maxs.x, mins.y, maxs.z),
                            Vector3(mins.x, maxs.y, maxs.z),
                            Vector3(maxs.x, maxs.y, maxs.z)
                        }

                        local screenCorners = {}
                        local allCornersVisible = true

                        for _, corner in ipairs(corners) do
                            local screenPos = client.WorldToScreen(corner, ScopeRenderer.view.custom)
                            if not screenPos then
                                allCornersVisible = false
                                break
                            end
                            table.insert(screenCorners, screenPos)
                        end

                        if allCornersVisible then
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

                            local teamColor = TEAM_COLORS[player:GetTeamNumber()]
                            if teamColor then
                                -- Ensure color is set before drawing
                                draw.Color(teamColor.r, teamColor.g, teamColor.b, teamColor.a)
                                if left and right and top and bottom then -- Make sure we have valid coordinates
                                    draw.FilledRect(left, top, right, bottom)
                                end
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
    if ScopeRenderer:IsScoped() and (cmd:Get() == "invprev" or cmd:Get() == "invnext") then
        return false
    end
end)

-- Handle zoom controls
callbacks.Register("CreateMove", function(cmd)
    if not ScopeRenderer:IsScoped() then return end

    if ScopeRenderer.view.new_style then
        if input.IsButtonPressed(113) then -- MWHEEL_DOWN
            ScopeRenderer.zoom.locked = true
            ScopeRenderer.zoom.warning.alpha = 255
            ScopeRenderer.zoom.warning.fade_start = globals.RealTime()
        elseif input.IsButtonPressed(112) then -- MWHEEL_UP
            ScopeRenderer.zoom.locked = false
        end

        if not ScopeRenderer.zoom.locked then
            if (cmd.buttons & IN_FORWARD) ~= 0 and (cmd.buttons & IN_MOVERIGHT) ~= 0 then
                ScopeRenderer.zoom.offset = math.max(ScopeRenderer.zoom.offset - ScopeRenderer.zoom.step_new, -80)
            end
            
            if (cmd.buttons & IN_BACK) ~= 0 and (cmd.buttons & IN_MOVELEFT) ~= 0 then
                ScopeRenderer.zoom.offset = math.min(ScopeRenderer.zoom.offset + ScopeRenderer.zoom.step_new, 30)
            end
        elseif ((cmd.buttons & IN_FORWARD) ~= 0 and (cmd.buttons & IN_MOVERIGHT) ~= 0) or 
               ((cmd.buttons & IN_BACK) ~= 0 and (cmd.buttons & IN_MOVELEFT) ~= 0) then
            ScopeRenderer.zoom.warning.alpha = 255
            ScopeRenderer.zoom.warning.fade_start = globals.RealTime()
        end
    else
        if input.IsButtonPressed(112) or input.IsButtonDown(112) then -- MWHEEL_UP
            cmd.buttons = cmd.buttons & ~MOUSE_WHEEL_UP
            ScopeRenderer.zoom.offset = math.max(ScopeRenderer.zoom.offset - ScopeRenderer.zoom.step, -10)
        elseif input.IsButtonPressed(113) or input.IsButtonDown(113) then -- MWHEEL_DOWN
            cmd.buttons = cmd.buttons & ~MOUSE_WHEEL_DOWN
            ScopeRenderer.zoom.offset = math.min(ScopeRenderer.zoom.offset + ScopeRenderer.zoom.step, 120)
        end
    end
end)

-- Main render callback
callbacks.Register("PostRenderView", function(view)
    if engine.Con_IsVisible() or engine.IsGameUIVisible() or input.IsButtonDown(KEY_ESCAPE) then return end
    
    if not ScopeRenderer:IsScoped() then return end
    
    if not ScopeRenderer:InitializeMaterials() then return end
    
    -- Set up custom view
    local customView = view
    customView.angles = engine.GetViewAngles()
    customView.fov = ScopeRenderer.zoom.base_fov + ScopeRenderer.zoom.offset
    ScopeRenderer.view.custom = customView
    
    -- Render the scene to our texture
    render.Push3DView(customView, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, ScopeRenderer.materials.texture)
    render.ViewDrawScene(true, true, customView)
    render.PopView()
    
    -- Draw the texture to the screen
    render.DrawScreenSpaceRectangle(
        ScopeRenderer.materials.material,
        0, 0,
        ScopeRenderer.screen.width, ScopeRenderer.screen.height,
        0, 0,
        ScopeRenderer.screen.width, ScopeRenderer.screen.height,
        ScopeRenderer.screen.width, ScopeRenderer.screen.height
    )
end)

-- Clean up properly on unload
callbacks.Register("Unload", function()
    -- We don't destroy materials anymore, they persist between script reloads
    ScopeRenderer.view.custom = nil
end)
