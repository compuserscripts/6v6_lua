-- enemycam.lua - TF2 Enemy Camera
-- Creates a camera window in the upper right corner that shows enemy players
-- By default shows the view of the player on the enemy team who is being healed by a medic
-- Config options for alternative views
-- Optimized version

-- Configuration
local CONFIG = {
    -- Camera position and size
    x_position = 0, -- Will be set correctly in init after getting screen size
    y_position = 20,
    width = 320,
    height = 240,
    
    -- Features
    show_border = true,
    show_info = true,
    
    -- Camera view settings
    -- "raw" - Show the exact view from player's eyes
    -- "offset" - Apply slight offset for better visibility (like in first-person games)
    camera_view_mode = "offset", 
    forward_offset = 16.5, -- How far forward to offset the camera in "offset" mode
    upward_offset = 12,    -- How far upward to offset the camera in "offset" mode
    
    -- Target selection mode
    -- "healed" - Show the view of enemy players being healed by medics
    -- "closest" - Show the view of enemy players closest to you
    -- "top_score" - Show the view of enemy player with highest score
    -- "random" - Show the view of a random enemy player
    -- "medic" - Show the view of enemy medics
    mode = "closest",
    
    -- Filter options
    focus_medic_pairs = true, -- Prioritize showing medic+patient pairs
    ignore_invisible = true,  -- Don't show invisible spies
    
    -- Tracking options
    track_time = 3.0, -- Time to track a target before switching (0 for no auto-switching)
    follow_killer = 2.0 -- Time to follow your killer after death (0 to disable)
}

-- State variables
local camera_state = {
    materials_initialized = false,
    camera_texture = nil,
    camera_material = nil,
    invisible_material = nil,
    is_camera_visible = true, -- Camera visibility toggle state
    target_player = nil,
    target_medic = nil,
    target_switch_time = 0,
    killer_entity = nil,
    last_death_time = 0,
    last_search_time = 0,
    last_key_press = globals.RealTime(),
    draw_font = nil,
    title_font = nil,
    fullscreen_width = 0,
    fullscreen_height = 0,
    is_in_game = false
}

-- Search interval for finding new targets (seconds)
local SEARCH_INTERVAL = 0.5

-- Initialize proper positions based on screen size
local function InitializePositions()
    camera_state.fullscreen_width, camera_state.fullscreen_height = draw.GetScreenSize()
    CONFIG.x_position = camera_state.fullscreen_width - CONFIG.width - 5
end

-- Initialize fonts
local function InitializeFonts()
    camera_state.title_font = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)
    camera_state.draw_font = draw.CreateFont("Tahoma", 11, 400, FONTFLAG_OUTLINE)
end

-- Initialize materials for rendering
local function InitializeMaterials()
    -- Skip if already initialized or camera is hidden
    if camera_state.materials_initialized or not camera_state.is_camera_visible then 
        return camera_state.materials_initialized
    end
    
    -- Clean up any existing materials first
    --CleanupMaterials()
    
    -- Create texture
    camera_state.camera_texture = materials.CreateTextureRenderTarget("enemyCamTexture", CONFIG.width, CONFIG.height)
    if not camera_state.camera_texture then
        print("Failed to create camera texture")
        return false
    end
    
    -- Create material using the texture
    local materialName = "enemyCamTexture"
    camera_state.camera_material = materials.Create("enemyCamMaterial", string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
            $nofog          1
        }
    ]], materialName))
    if not camera_state.camera_material then
        print("Failed to create camera material")
        --CleanupMaterials()
        return false
    end
    
    -- Create invisible material for hiding player models
    camera_state.invisible_material = materials.Create("enemyCam_invisible_material", [[
        VertexLitGeneric
        {
            $basetexture    "vgui/white_additive"
            $no_draw        1
        }
    ]])
    if not camera_state.invisible_material then
        print("Failed to create invisible material")
        --CleanupMaterials()
        return false
    end
    
    camera_state.materials_initialized = true
    print("Enemy Camera: Materials initialized")
    return true
end

-- Clean up materials to prevent memory leaks
local function CleanupMaterials()
    if camera_state.camera_texture then
        camera_state.camera_texture = nil
    end
    
    camera_state.camera_material = nil
    camera_state.invisible_material = nil
    camera_state.materials_initialized = false
end

-- Get enemy players
local function GetEnemyPlayers()
    local enemy_players = {}
    local local_player = entities.GetLocalPlayer()
    if not local_player then return enemy_players end
    
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player and player:IsValid() and player:IsAlive() and 
           not player:IsDormant() and 
           player:GetTeamNumber() ~= local_player:GetTeamNumber() then
            
            -- Optionally filter invisible spies
            if CONFIG.ignore_invisible and player:InCond(TFCond_Cloaked) then
                goto continue
            end
            
            table.insert(enemy_players, player)
        end
        ::continue::
    end
    
    return enemy_players
end

-- Get target player based on config mode
local function FindTargetPlayer()
    local local_player = entities.GetLocalPlayer()
    if not local_player then return nil end
    
    local enemy_players = GetEnemyPlayers()
    if #enemy_players == 0 then return nil end
    
    -- Special case: follow your killer after death
    if CONFIG.follow_killer > 0 and camera_state.killer_entity and 
       globals.CurTime() - camera_state.last_death_time < CONFIG.follow_killer then
        
        if camera_state.killer_entity:IsValid() and camera_state.killer_entity:IsAlive() and not camera_state.killer_entity:IsDormant() then
            return camera_state.killer_entity, nil
        end
    end
    
    -- Mode selection
    if CONFIG.mode == "healed" then
        -- Find players being healed by medics
        local healed_players = {}
        
        for _, player in ipairs(enemy_players) do
            if player:InCond(TFCond_Healing) then
                -- Try to find the medic healing this player
                local healing_medic = nil
                
                if CONFIG.focus_medic_pairs then
                    for _, potential_medic in ipairs(enemy_players) do
                        if potential_medic:GetPropInt("m_iClass") == 5 then -- 5 is Medic's class ID
                            local medigun = potential_medic:GetEntityForLoadoutSlot(LOADOUT_POSITION_SECONDARY)
                            if medigun and medigun:GetPropEntity("m_hHealingTarget") == player then
                                healing_medic = potential_medic
                                break
                            end
                        end
                    end
                end
                
                table.insert(healed_players, {player = player, medic = healing_medic})
            end
        end
        
        if #healed_players > 0 then
            local chosen = healed_players[math.random(#healed_players)]
            return chosen.player, chosen.medic
        end
        
        -- If no healed players, fall back to closest enemy mode
        CONFIG.mode = "closest"
    end
    
    if CONFIG.mode == "closest" then
        local closest_player = nil
        local min_distance = math.huge
        
        local player_pos = local_player:GetAbsOrigin()
        
        for _, player in ipairs(enemy_players) do
            local enemy_pos = player:GetAbsOrigin()
            local distance = (enemy_pos - player_pos):Length()
            
            if distance < min_distance then
                min_distance = distance
                closest_player = player
            end
        end
        
        return closest_player, nil
    end
    
    if CONFIG.mode == "top_score" then
        local top_player = nil
        local max_score = -1
        
        local resources = entities.GetPlayerResources()
        if not resources then return enemy_players[1], nil end
        
        for _, player in ipairs(enemy_players) do
            local score = resources:GetPropInt("m_iTotalScore", player:GetIndex())
            
            if score > max_score then
                max_score = score
                top_player = player
            end
        end
        
        return top_player, nil
    end
    
    if CONFIG.mode == "medic" then
        for _, player in ipairs(enemy_players) do
            if player:GetPropInt("m_iClass") == 5 then -- 5 is Medic's class ID
                local healing_target = nil
                
                if CONFIG.focus_medic_pairs then
                    local medigun = player:GetEntityForLoadoutSlot(LOADOUT_POSITION_SECONDARY)
                    if medigun then
                        healing_target = medigun:GetPropEntity("m_hHealingTarget")
                    end
                end
                
                return player, healing_target
            end
        end
    end
    
    -- Default/random mode
    return enemy_players[math.random(#enemy_players)], nil
end

-- Get class name from class ID
local function GetClassName(class_id)
    local class_names = {
        [1] = "Scout",
        [2] = "Sniper",
        [3] = "Soldier",
        [4] = "Demoman",
        [5] = "Medic",
        [6] = "Heavy",
        [7] = "Pyro",
        [8] = "Spy",
        [9] = "Engineer"
    }
    
    return class_names[class_id] or "Unknown"
end

-- Get team color
local function GetTeamColor(team_num)
    if team_num == 2 then      -- RED
        return {r = 255, g = 64, b = 64}
    elseif team_num == 3 then  -- BLU
        return {r = 153, g = 204, b = 255}
    else
        return {r = 255, g = 255, b = 255}
    end
end

-- Draw camera borders and info
local function DrawCameraOverlay()
    if not camera_state.target_player then return end
    
    if CONFIG.show_border then
        -- Draw outer border
        draw.Color(235, 64, 52, 255)
        draw.OutlinedRect(
            CONFIG.x_position,
            CONFIG.y_position,
            CONFIG.x_position + CONFIG.width,
            CONFIG.y_position + CONFIG.height
        )
        
        -- Draw title bar border
        draw.OutlinedRect(
            CONFIG.x_position,
            CONFIG.y_position - 20,
            CONFIG.x_position + CONFIG.width,
            CONFIG.y_position
        )
        
        -- Draw title bar background
        draw.Color(130, 26, 17, 255)
        draw.FilledRect(
            CONFIG.x_position + 1,
            CONFIG.y_position - 19,
            CONFIG.x_position + CONFIG.width - 1,
            CONFIG.y_position - 1
        )
    end
    
    if CONFIG.show_info then
        -- Draw title with player info
        draw.SetFont(camera_state.title_font)
        draw.Color(255, 255, 255, 255)
        
        local player_name = camera_state.target_player:GetName() or "Unknown"
        local player_class = GetClassName(camera_state.target_player:GetPropInt("m_iClass"))
        
        local title_text = string.format("%s (%s)", player_name, player_class)
        
        -- If we have a medic, show that info too
        if camera_state.target_medic then
            local medic_name = camera_state.target_medic:GetName() or "Unknown"
            title_text = string.format("%s + Medic: %s", title_text, medic_name)
        end
        
        -- Add camera mode indicator
        local view_mode = CONFIG.camera_view_mode:sub(1,1):upper() .. CONFIG.camera_view_mode:sub(2)
        title_text = string.format("%s [%s]", title_text, view_mode)
        
        local text_w, text_h = draw.GetTextSize(title_text)
        draw.Text(
            math.floor(CONFIG.x_position + CONFIG.width/2 - text_w/2),
            CONFIG.y_position - 16,
            title_text
        )
        
        -- Draw player health info
        draw.SetFont(camera_state.draw_font)
        local health = camera_state.target_player:GetHealth() or 0
        local max_health = camera_state.target_player:GetMaxHealth() or 100
        
        -- Calculate health percentage safely
        local health_percent = 0
        if health > 0 and max_health > 0 then
            health_percent = health / max_health
        end
        
        -- Health color (green to red)
        local health_r = math.floor(255 * (1 - health_percent))
        local health_g = math.floor(255 * health_percent)
        
        draw.Color(0, 0, 0, 180)
        draw.FilledRect(
            CONFIG.x_position + 5,
            CONFIG.y_position + 5,
            CONFIG.x_position + 100,
            CONFIG.y_position + 25
        )
        
        draw.Color(health_r, health_g, 0, 255)
        draw.Text(
            math.floor(CONFIG.x_position + 10),
            CONFIG.y_position + 8,
            string.format("HP: %d/%d", health, max_health)
        )
    end
end

-- Track target player and switch when needed
local function UpdateTargetPlayer()
    local current_time = globals.CurTime()
    
    -- Only search for new targets periodically to avoid performance impact
    if current_time - camera_state.last_search_time < SEARCH_INTERVAL then
        return
    end
    
    camera_state.last_search_time = current_time
    
    -- Check if we need to find a new target
    local need_new_target = false
    
    -- If no current target or it's invalid
    if not camera_state.target_player or not camera_state.target_player:IsValid() or 
       not camera_state.target_player:IsAlive() or camera_state.target_player:IsDormant() then
        need_new_target = true
    end
    
    -- If we have a target and it's time to switch
    if camera_state.target_player and CONFIG.track_time > 0 and 
       current_time - camera_state.target_switch_time >= CONFIG.track_time then
        need_new_target = true
    end
    
    -- Find new target if needed
    if need_new_target then
        camera_state.target_player, camera_state.target_medic = FindTargetPlayer()
        camera_state.target_switch_time = current_time
    end
end

-- Function to reset the script when changing servers
local function ResetScript()
    -- Reset target states
    camera_state.target_player = nil
    camera_state.target_medic = nil
    
    -- Clean up resources
    --CleanupMaterials()
    
    print("Enemy Camera: Reset after server change")
end

-- Handle game events
local function HandleGameEvent(event)
    if event:GetName() == "player_death" then
        local local_player = entities.GetLocalPlayer()
        if not local_player then return end
        
        local victim = entities.GetByUserID(event:GetInt("userid"))
        if victim and local_player:GetIndex() == victim:GetIndex() then
            -- We died, record time and killer
            camera_state.last_death_time = globals.CurTime()
            local attacker_id = event:GetInt("attacker")
            if attacker_id and attacker_id > 0 then
                camera_state.killer_entity = entities.GetByUserID(attacker_id)
            end
        end
    elseif event:GetName() == "game_newmap" then
        camera_state.is_in_game = true
        ResetScript()
    elseif event:GetName() == "teamplay_game_over" or 
           event:GetName() == "tf_game_over" then
        camera_state.is_in_game = false
    end
end

-- Handle key input to toggle camera visibility
local function CheckKeyToggle()
    -- Check for ENTER key press
    if input.IsButtonPressed(KEY_ENTER) then
        local current_time = globals.RealTime()
        
        -- Debounce to prevent multiple toggles with one key press
        if current_time - camera_state.last_key_press > 0.2 then
            camera_state.is_camera_visible = not camera_state.is_camera_visible
            camera_state.last_key_press = current_time
            
            -- Print status message
            if camera_state.is_camera_visible then
                print("Enemy Camera: Visible")
            else
                print("Enemy Camera: Hidden")
                -- Clean up resources when camera is hidden
                --CleanupMaterials()
            end
        end
    end
end

-- Handle camera rendering
local function RenderCameraView(view)
    -- Skip if no target player
    if not camera_state.target_player then return end
    
    -- Skip if target player is not valid
    if not camera_state.target_player:IsValid() then
        camera_state.target_player = nil
        return
    end
    
    -- Start with the player's view
    local player_view = view
    
    -- Get player eye position
    local eye_pos = camera_state.target_player:GetAbsOrigin() + 
                   camera_state.target_player:GetPropVector("localdata", "m_vecViewOffset[0]")
    player_view.origin = eye_pos
    
    -- Get player eye angles
    local pitch = camera_state.target_player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[0]") or 0
    local yaw = camera_state.target_player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[1]") or 0
    local eye_angles = EulerAngles(pitch, yaw, 0)
    player_view.angles = eye_angles
    
    -- Apply offset if configured
    if CONFIG.camera_view_mode == "offset" then
        -- Apply forward offset
        local forward_vector = eye_angles:Forward()
        
        -- Increase forward offset when player is looking down to prevent camera clipping
        local pitch_factor = 1.0
        if pitch > 60 then -- Adjust when looking down significantly
            pitch_factor = 1.0 + ((pitch - 60) / 30) * 7.5 -- Gradually increase offset
        end
        
        player_view.origin = player_view.origin + forward_vector * (CONFIG.forward_offset * pitch_factor)
        
        -- Apply upward offset
        player_view.origin = player_view.origin + Vector3(0, 0, CONFIG.upward_offset)
    end
    
    -- Render the camera view
    render.Push3DView(player_view, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, camera_state.camera_texture)
    render.ViewDrawScene(true, true, player_view)
    render.PopView()
    
    -- Draw the camera on screen
    render.DrawScreenSpaceRectangle(
        camera_state.camera_material,
        CONFIG.x_position, CONFIG.y_position,
        CONFIG.width, CONFIG.height,
        0, 0,
        CONFIG.width, CONFIG.height,
        CONFIG.width, CONFIG.height
    )
end

-- Main PostRenderView function
callbacks.Register("PostRenderView", function(view)
    -- Always check for key toggle regardless of visibility
    CheckKeyToggle()
    
    -- Skip rendering if conditions aren't met
    if engine.Con_IsVisible() or engine.IsGameUIVisible() or not camera_state.is_camera_visible then 
        return
    end
    
    -- Initialize materials if needed (and camera is visible)
    if not camera_state.materials_initialized then
        if not InitializeMaterials() then
            return
        end
    end
    
    -- Update the target player
    UpdateTargetPlayer()
    
    -- Render the camera view
    RenderCameraView(view)
end)

-- Draw overlay information
callbacks.Register("Draw", function()
    -- Skip rendering if conditions aren't met
    if engine.Con_IsVisible() or engine.IsGameUIVisible() or not camera_state.is_camera_visible then 
        return
    end
    
    DrawCameraOverlay()
end)

-- Track game events
callbacks.Register("FireGameEvent", HandleGameEvent)

-- Clean up resources when script is unloaded
callbacks.Register("Unload", function()
    --CleanupMaterials()
    camera_state.target_player = nil
    camera_state.target_medic = nil
end)

-- Initialize everything
InitializePositions()
InitializeFonts()