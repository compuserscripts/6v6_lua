local camera_x_position = 5 
local camera_y_position = 300
local camera_width = 500 
local camera_height = 300
local fullscreen_width, fullscreen_height = draw.GetScreenSize()

-- Constants
local MAX_KILLFEED_ENTRIES = 8

-- Camera control variables
local camera_position = Vector3(0, 0, 0)
local camera_angles = EulerAngles(0, 0, 0)
local own_view_angles = EulerAngles(0, 0, 0)
local camera_speed = 10
local target_player = nil
local current_enemy_index = 1
local visited_players = {}
local first_person_mode = false
local fullscreen_mode = false
local free_camera = false
local last_key_press = 0
local key_delay = 0.2
local MOUSE_SENSITIVITY = 0.06
local last_killer = nil
local persistent_fullscreen = false
local death_time = 0
local current_wave_start = 0

-- Material variables
local materials_initialized = false
local windowed_texture = nil
local windowed_material = nil
local fullscreen_texture = nil
local fullscreen_material = nil
local invisibleMaterial = nil

-- Killfeed variables
local killfeed_deaths = {}

-- HUD fonts
local title_font = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)
local hud_font = draw.CreateFont("TF2 BUILD", 30, 800, FONTFLAG_OUTLINE)
local killfeed_font = draw.CreateFont("TF2 BUILD", 24, 800, FONTFLAG_OUTLINE)

-- Constants
local DEATH_TIME = 2.0
local TRAVEL_TIME = 0.4
local FREEZE_TIME = 4.0
local DEFAULT_WAVE_TIME = 10.0
local BASE_DELAY = TRAVEL_TIME + FREEZE_TIME
local TOTAL_BASE_DELAY = DEATH_TIME + BASE_DELAY

-- Static variables
local lockedWaveTime = nil
local lastDeathTime = nil
local lastDebugTime = 0

--[[
There is a static base respawn time, which is based on a static death time of 2 seconds + the time for the freeze frame (0.4 travel time + 4.0 freeze time).
On top of this base, the non-scaled respawn wave time is added, which is 10 seconds by default, and can be changed per team by an input which happens
upon capturing a control point, which adds or subtracts from a team's base respawn wave time. Then, the game checks the time for the next respawn wave,
and compares it to the time for the base respawn time. If the base respawn time occurs after the next respawn wave, the scaled respawn wave time is added
on top of the next respawn wave to get the wave after the next, and so on until a respawn wave is found that occurs after the base respawn time.
The scaled respawn wave time is the non-scaled respawn wave time, except with the following extra logic: if the respawn wave time is above 5 seconds,
then scale it by a number between 0.25 and 1.0, linearly scaled by the number of players (1 to 8). Then this value is capped to a maximum of 5.
    
This logic happens during any PvP game, tournament mode or not. There are a few exceptions outside of normal PvP play, like in between rounds during Competitive Mode,
you respawn with your static base respawn time, and in pre-game for tournament mode, there are no respawn times.
]]--


local function ScaleWaveTime(waveTime, playerCount)
    if waveTime <= 5.0 then
        return waveTime
    end
    
    local scale = 0.25 + (math.min(playerCount, 8) - 1) * (0.75 / 7)
    return math.min(waveTime * scale, 5.0)
end

local function GetRespawnTime()
    local currentTime = globals.CurTime()
    
    if not lastDeathTime or currentTime - lastDeathTime > 15.0 then
        lockedWaveTime = nil
        lastDeathTime = currentTime
        lastDebugTime = 0
    end
    
    local baseRespawnTime = lastDeathTime + TOTAL_BASE_DELAY
    
    local resources = entities.GetPlayerResources()
    if not resources then return 0 end
    
    local waveTable = resources:GetPropDataTableFloat("m_flNextRespawnTime")
    if not waveTable then return 0 end
    
    if lockedWaveTime and lockedWaveTime > currentTime then
        if currentTime - lastDebugTime >= 1.0 then
            print(string.format("Time to respawn: %.1f", lockedWaveTime - currentTime))
            lastDebugTime = currentTime
        end
        return lockedWaveTime - currentTime
    end
    
    local futureWaves = {}
    local seenWaves = {}
    for _, waveTime in pairs(waveTable) do
        local roundedTime = math.floor(waveTime * 100) / 100
        if waveTime > currentTime and waveTime ~= 0 and not seenWaves[roundedTime] then
            table.insert(futureWaves, waveTime)
            seenWaves[roundedTime] = true
        end
    end
    table.sort(futureWaves)
    
    print("Current time:", currentTime)
    print("Base respawn time:", baseRespawnTime)
    print("Available waves:")
    for i, wave in ipairs(futureWaves) do
        print(string.format("Wave %d: %.2f (in %.2f seconds)", 
            i, wave, wave - currentTime))
    end
    
    if #futureWaves == 0 then
        return TOTAL_BASE_DELAY
    end
    
    local nextWave = futureWaves[1]

    if baseRespawnTime > nextWave then
        -- Get scaled wave time
        local playerCount = 0
        for i = 1, 32 do
            if resources:GetPropInt("m_bConnected", i) == 1 then
                playerCount = playerCount + 1
            end
        end
        
        local fullWaveTime = DEFAULT_WAVE_TIME
        if fullWaveTime > 5.0 then
            local scale = 0.25 + (math.min(playerCount, 8) - 1) * (0.75 / 7)
            fullWaveTime = math.min(fullWaveTime * scale, 5.0)
        end
        
        -- Calculate where we should be after adding the wave time
        local targetTime = nextWave + fullWaveTime
        
        -- Find the next wave after this point
        local targetWave = nil
        for _, wave in ipairs(futureWaves) do
            if wave > targetTime then
                targetWave = wave
                break
            end
        end
        
        -- If we didn't find a suitable wave, add another wave time
        if not targetWave then
            targetWave = futureWaves[#futureWaves] + fullWaveTime
        end
        
        lockedWaveTime = targetWave
    else
        -- Base respawn is before next wave, use next available wave
        lockedWaveTime = nextWave
    end
    
    print(string.format("Selected wave: %.2f (in %.2f seconds)", 
        lockedWaveTime, lockedWaveTime - currentTime))
    lastDebugTime = currentTime
    return lockedWaveTime - currentTime
end

-- Cleanup state
local function CleanupState()
    killfeed_deaths = {}
    camera_position = Vector3(0, 0, 0)
    camera_angles = EulerAngles(0, 0, 0)
    own_view_angles = EulerAngles(0, 0, 0)
    target_player = nil
    current_enemy_index = 1
    visited_players = {}
    first_person_mode = false
    free_camera = false
    fullscreen_mode = persistent_fullscreen
    last_killer = nil
    death_time = 0
    current_wave_start = 0
end

-- Clean up function for materials and textures
local function CleanupMaterials()
    if windowed_texture then
        draw.DeleteTexture(windowed_texture)
        windowed_texture = nil
    end
    if fullscreen_texture then
        draw.DeleteTexture(fullscreen_texture)
        fullscreen_texture = nil
    end
    
    windowed_material = nil
    fullscreen_material = nil
    invisibleMaterial = nil
    materials_initialized = false
end

-- Initialize all materials
local function InitializeAllMaterials()
    -- Clean up any existing materials first
    CleanupMaterials()
    
    -- Create windowed mode materials
    local windowed_texture_name = "camTexture_windowed"
    windowed_texture = materials.CreateTextureRenderTarget(windowed_texture_name, camera_width, camera_height)
    if not windowed_texture then
        error("Failed to create windowed texture")
    end

    windowed_material = materials.Create("camMaterial_windowed", string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
            $nofog         1
        }
    ]], windowed_texture_name))

    -- Create fullscreen mode materials
    local fullscreen_texture_name = "camTexture_fullscreen"
    fullscreen_texture = materials.CreateTextureRenderTarget(fullscreen_texture_name, fullscreen_width, fullscreen_height)
    if not fullscreen_texture then
        error("Failed to create fullscreen texture")
    end

    fullscreen_material = materials.Create("camMaterial_fullscreen", string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
            $nofog         1
        }
    ]], fullscreen_texture_name))

    invisibleMaterial = materials.Create("invisible_material", [[
        VertexLitGeneric
        {
            $basetexture    "vgui/white"
            $no_draw        1
        }
    ]])

    materials_initialized = true
end

local function draw_crosshair(x, y, r, g, b, a)
    local size = 6
    draw.Color(r, g, b, a)
    draw.Line(x, y-size/2 - 10, x, y+size/2 - 10)
    draw.Line(x-size/2 - 10, y, x+size/2 - 10, y)
    draw.Line(x+size/2 + 10, y, x-size/2 + 10, y)
    draw.Line(x, y+size/2 + 10, x, y-size/2 + 10)
end

local function IsAttachedToTargetPlayer(entity)
    if not target_player or not entity then return false end
    
    local moveChild = target_player:GetMoveChild()
    while moveChild do
        if moveChild == entity then return true end
        moveChild = moveChild:GetMovePeer()
    end
    
    return false
end

local function GetEnemyPlayers()
    local enemy_players = {}
    local local_player = entities.GetLocalPlayer()
    if not local_player then return enemy_players end
    
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player and player:IsValid() and player:IsAlive() and 
           not player:IsDormant() and 
           player:GetTeamNumber() ~= local_player:GetTeamNumber() then
            table.insert(enemy_players, player)
        end
    end
    
    return enemy_players
end

local function CycleNextEnemy()
    local enemies = GetEnemyPlayers()
    if #enemies == 0 then
        target_player = nil
        first_person_mode = false
        free_camera = false
        visited_players = {}
        return
    end

    local available_enemies = {}
    for _, player in ipairs(enemies) do
        local already_visited = false
        for _, visited in ipairs(visited_players) do
            if visited == player then
                already_visited = true
                break
            end
        end
        
        if not already_visited then
            table.insert(available_enemies, player)
        end
    end

    if #available_enemies == 0 then
        visited_players = {}
        available_enemies = enemies
    end

    for _, player in ipairs(available_enemies) do
        if player and player:IsValid() and player:IsAlive() and not player:IsDormant() then
            target_player = player
            table.insert(visited_players, player)
            break
        end
    end

    if target_player then
        print("Now spectating: " .. target_player:GetName() .. " (" .. #visited_players .. "/" .. #enemies .. " visited)")
    end
end

local function HandleMovement()
    local forward = Vector3(0, 0, 0)
    local right = Vector3(0, 0, 0)
    local up = Vector3(0, 0, 0)

    if input.IsButtonDown(KEY_W) then
        forward = forward + camera_angles:Forward() * camera_speed
    end
    if input.IsButtonDown(KEY_S) then
        forward = forward - camera_angles:Forward() * camera_speed
    end
    if input.IsButtonDown(KEY_D) then
        right = right + camera_angles:Right() * camera_speed
    end
    if input.IsButtonDown(KEY_A) then
        right = right - camera_angles:Right() * camera_speed
    end
    if input.IsButtonDown(KEY_Q) then
        up.z = up.z + camera_speed
    end
    if input.IsButtonDown(KEY_E) then
        up.z = up.z - camera_speed
    end

    return forward + right + up
end

local function SafeGetTextSize(text)
    if not text or text == "" then
        return 0, 0
    end
    return draw.GetTextSize(text)
end

local function HandleKillfeedEvent(event)
    if event:GetName() == "player_death" then
        local victim = entities.GetByUserID(event:GetInt("userid"))
        local attacker_id = event:GetInt("attacker")
        local attacker = nil
        
        if attacker_id and attacker_id > 0 then
            attacker = entities.GetByUserID(attacker_id)
        end
        
        local assister = nil
        local assister_id = event:GetInt("assister")
        if assister_id and assister_id > 0 then
            assister = entities.GetByUserID(assister_id)
        end
        
        local local_player = entities.GetLocalPlayer()
        
        if victim and local_player and victim:GetIndex() == local_player:GetIndex() and attacker then
            last_killer = attacker
        end

        if not victim then return end

        local current_tick = globals.TickCount()
        local hud_deathnotice_time = client.GetConVar("hud_deathnotice_time")
        
        killfeed_deaths[#killfeed_deaths+1] = {
            victim = victim, 
            attacker = attacker,
            assister = assister,
            tick_to_disappear = current_tick + (hud_deathnotice_time * 66 * 2)
        }

        while #killfeed_deaths > MAX_KILLFEED_ENTRIES do
            table.remove(killfeed_deaths, 1)
        end
    end
end

local function DrawKillfeed()
    if not fullscreen_mode then return end
    
    local current_tick = globals.TickCount()
    
    for i = #killfeed_deaths, 1, -1 do
        if killfeed_deaths[i].tick_to_disappear <= current_tick then
            table.remove(killfeed_deaths, i)
        end
    end
    
    local lastHeight = 5
    local local_player = entities.GetLocalPlayer()
    
    local team_colors = {
        [2] = {255, 64, 64, 255},
        [3] = {153, 204, 255, 255}
    }
    
    local function GetColoredPlayerText(player)
        if not player or not player:IsValid() then
            return {text = "Unknown", color = {255, 255, 255, 255}}
        end

        local name = player:GetName()
        if not name or name == "" then
            return {text = "Unknown", color = {255, 255, 255, 255}}
        end

        if (local_player and player:GetIndex() == local_player:GetIndex()) or 
           (target_player and player:GetIndex() == target_player:GetIndex()) then
            return {text = name, color = {255, 255, 255, 255}}
        else
            local team_color = team_colors[player:GetTeamNumber()] or {255, 255, 255, 255}
            return {text = name, color = team_color}
        end
    end

    for pos, death in ipairs(killfeed_deaths) do
        if not death.victim then goto continue end
        
        local victim_info = GetColoredPlayerText(death.victim)
        local died_alone = death.attacker == death.victim
        local map_death = not death.attacker or not death.attacker:IsValid()
        
        draw.SetFont(killfeed_font)
        local full_text
        local components = {}

        if map_death or died_alone then
            full_text = string.format("%s died a horrible death :(", victim_info.text)
            components = {{text = full_text, color = victim_info.color}}
        else
            local attacker_info = GetColoredPlayerText(death.attacker)
            components = {
                {text = attacker_info.text, color = attacker_info.color}
            }
            
            if death.assister and death.assister:IsValid() and death.assister:GetName() then
                local assister_info = GetColoredPlayerText(death.assister)
                table.insert(components, {text = " + ", color = {255, 255, 255, 255}})
                table.insert(components, {text = assister_info.text, color = assister_info.color})
            end
            
            table.insert(components, {text = " → ", color = {255, 255, 255, 255}})
            table.insert(components, {text = victim_info.text, color = victim_info.color})
            
            full_text = ""
            for _, component in ipairs(components) do
                full_text = full_text .. component.text
            end
        end
        
        local textwidth, textheight = SafeGetTextSize(full_text)
        if textwidth == 0 or textheight == 0 then goto continue end
        
        local x1 = fullscreen_width - textwidth - 30
        local y = lastHeight + textheight
        
        local current_x = x1
        for _, component in ipairs(components) do
            draw.Color(component.color[1], component.color[2], component.color[3], component.color[4])
            draw.TextShadow(current_x, y, component.text)
            current_x = current_x + SafeGetTextSize(component.text)
        end

        lastHeight = lastHeight + textheight + 10

        ::continue::
    end
end

-- Make sure to set death_time when player dies
callbacks.Register("FireGameEvent", function(event)
    if event:GetName() == "player_death" then
        local localPlayer = entities.GetLocalPlayer()
        if not localPlayer then return end
        
        local victim = entities.GetByUserID(event:GetInt("userid"))
        if victim and localPlayer:GetIndex() == victim:GetIndex() then
            death_time = globals.CurTime()
            current_wave_start = 0 -- Reset current wave
        end
    end
end)

-- Track when points are captured to reset wave timing
local function OnGameEvent(event)
    if event:GetName() == "team_control_point_captured" then
        -- Reset our target wave when a point is captured
        targetWaveTime = nil
        current_wave_start = globals.CurTime()
    end
end
callbacks.Register("FireGameEvent", "point_capture_hook", OnGameEvent)

-- Update DrawSpectatorHUD
local function DrawSpectatorHUD()
    if not fullscreen_mode then return end
    
    local time = GetRespawnTime()
    if time > 0 then
        draw.SetFont(hud_font)
        draw.Color(255, 255, 255, 255)
        local respawnText = string.format("Respawning in: %.1f", time)
        local textW, textH = draw.GetTextSize(respawnText)
        draw.TextShadow(
            math.floor(fullscreen_width/2 - textW/2),
            40,
            respawnText
        )
    end
    
    if not target_player or free_camera then return end
    
    -- Rest of your HUD drawing code...
    local health = target_player:GetHealth()
    if not health then return end
    local maxHealth = target_player:GetMaxHealth()
    if not maxHealth then return end
    local playerName = target_player:GetName()
    if not playerName then return end
    
    local healthColor = {
        r = math.floor(255 * (1 - (health / maxHealth))),
        g = math.floor(255 * (health / maxHealth)),
        b = 0
    }

    local crosshairColor = {
        r = 0,
        g = 255,
        b = 0
    }
        
    draw.SetFont(hud_font)
    draw.Color(255, 255, 255, 255)
    local nameW, nameH = draw.GetTextSize(playerName)
    draw.TextShadow(math.floor(fullscreen_width/2 - nameW/2), math.floor(fullscreen_height - 140), playerName)
    
    draw.Color(healthColor.r, healthColor.g, healthColor.b, 255)
    local healthText = string.format("%d HP", health)
    local textW, textH = draw.GetTextSize(healthText)
    draw.TextShadow(math.floor(fullscreen_width/2 - textW/2), math.floor(fullscreen_height - 100), healthText)

    if first_person_mode then
        draw_crosshair(fullscreen_width/2, fullscreen_height/2, crosshairColor.r, crosshairColor.g, crosshairColor.b, 255)
    end
end

local function HandleCameraControls()
    local current_time = globals.RealTime()

    if input.IsButtonPressed(KEY_LCONTROL) and current_time - last_key_press > key_delay then
        persistent_fullscreen = not persistent_fullscreen
        fullscreen_mode = persistent_fullscreen
        last_key_press = current_time
    end

    if input.IsButtonPressed(KEY_TAB) and current_time - last_key_press > key_delay then
        if not target_player or not target_player:IsValid() or not target_player:IsAlive() or target_player:IsDormant() then
            visited_players = {}
        end
        CycleNextEnemy()
        last_key_press = current_time
        free_camera = false
    end

    if input.IsButtonPressed(KEY_SPACE) and target_player and current_time - last_key_press > key_delay then
        first_person_mode = not first_person_mode
        free_camera = false
        last_key_press = current_time
    end

    if not target_player then
        camera_angles = own_view_angles
        camera_position = camera_position + HandleMovement()
    else
        if not first_person_mode then
            local moving = input.IsButtonDown(KEY_W) or input.IsButtonDown(KEY_A) or 
                          input.IsButtonDown(KEY_S) or input.IsButtonDown(KEY_D) or
                          input.IsButtonDown(KEY_Q) or input.IsButtonDown(KEY_E)
            
            if moving and not free_camera then
                free_camera = true
                own_view_angles = camera_angles
            end
        end

        if first_person_mode then
            free_camera = false
            camera_position = target_player:GetAbsOrigin() + target_player:GetPropVector("localdata", "m_vecViewOffset[0]")
            local pitch = target_player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[0]") or 0
            local yaw = target_player:GetPropFloat("tfnonlocaldata", "m_angEyeAngles[1]") or 0
            camera_angles = EulerAngles(pitch, yaw, 0)

            local forward_offset = 16.5
            local upward_offset = 12
            local forward_vector = camera_angles:Forward()
            camera_position = camera_position + forward_vector * forward_offset
            camera_position = camera_position + Vector3(0, 0, upward_offset)
        else
            camera_angles = own_view_angles
            if free_camera then
                camera_position = camera_position + HandleMovement()
            else
                camera_position = target_player:GetAbsOrigin() + Vector3(0, 0, 64) - camera_angles:Forward() * 100
            end
        end
    end
end

callbacks.Register("DrawModel", function(ctx)
    if not target_player or not first_person_mode or not invisibleMaterial then return end
    
    local ent = ctx:GetEntity()
    if not ent then return end

    if ent == target_player or IsAttachedToTargetPlayer(ent) then
        ctx:ForcedMaterialOverride(invisibleMaterial)
    end
end)

callbacks.Register("CreateMove", function(cmd)
    if first_person_mode then return end
    
    -- Allow mouse movement in free cam or when in third person with target
    if free_camera or (target_player and not first_person_mode) then
        local mouse_x = -cmd.mousedx * MOUSE_SENSITIVITY
        local mouse_y = cmd.mousedy * MOUSE_SENSITIVITY
        
        own_view_angles.y = own_view_angles.y + mouse_x
        own_view_angles.x = math.max(-89, math.min(89, own_view_angles.x + mouse_y))
    end
end)

callbacks.Register("PostRenderView", function(view)
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then 
        return
    end

    if not materials_initialized then
        InitializeAllMaterials()
        return
    end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not localPlayer:IsAlive() then
        local current_texture = persistent_fullscreen and fullscreen_texture or windowed_texture
        local current_material = persistent_fullscreen and fullscreen_material or windowed_material
        
        if not current_texture or not current_material then return end

        if camera_position == Vector3(0, 0, 0) then
            camera_position = localPlayer:GetAbsOrigin() + Vector3(0, 0, 64)
            own_view_angles = engine.GetViewAngles()
            
            if last_killer and last_killer:IsValid() and last_killer:IsAlive() and not last_killer:IsDormant() then
                target_player = last_killer
                first_person_mode = true
                free_camera = false
            else
                CycleNextEnemy()
                first_person_mode = true
                free_camera = false
            end
            
            last_killer = nil
            fullscreen_mode = persistent_fullscreen
        end

        -- Clean up invalid target player
        if target_player and (not target_player:IsValid() or not target_player:IsAlive() or target_player:IsDormant()) then
            visited_players = {}
            target_player = nil
            CycleNextEnemy()
        end

        HandleCameraControls()

        local customView = view
        customView.origin = camera_position 
        customView.angles = camera_angles
        
        if first_person_mode then
            customView.fov = 120
        end

        render.Push3DView(customView, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, current_texture)
        render.ViewDrawScene(true, true, customView)
        render.PopView()
        
        local render_x = fullscreen_mode and 0 or camera_x_position
        local render_y = fullscreen_mode and 0 or camera_y_position
        local render_width = fullscreen_mode and fullscreen_width or camera_width
        local render_height = fullscreen_mode and fullscreen_height or camera_height

        render.DrawScreenSpaceRectangle(
            current_material,
            render_x, render_y, 
            render_width, render_height,
            0, 0, 
            render_width, render_height,
            render_width, render_height
        )
    else
        --camera_position = Vector3(0, 0, 0)
        CleanupState()
    end
end)

-- Then modify the Draw callback to print when conditions are met
callbacks.Register("Draw", function()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then 
        return
    end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not localPlayer:IsAlive() then
        --print("Debug Draw: Player dead, fullscreen = " .. tostring(fullscreen_mode))  -- Debug print
        
        if fullscreen_mode then
            DrawSpectatorHUD()  -- Should now always draw at least respawn timer
            DrawKillfeed()
        end

        if not fullscreen_mode then
            draw.Color(235, 64, 52, 255)
            draw.OutlinedRect(
                math.floor(camera_x_position), 
                math.floor(camera_y_position), 
                math.floor(camera_x_position + camera_width),
                math.floor(camera_y_position + camera_height)
            )
            
            draw.OutlinedRect(
                math.floor(camera_x_position), 
                math.floor(camera_y_position - 20),
                math.floor(camera_x_position + camera_width), 
                math.floor(camera_y_position)
            )
            draw.Color(130, 26, 17, 255)
            draw.FilledRect(
                math.floor(camera_x_position + 1), 
                math.floor(camera_y_position - 19),
                math.floor(camera_x_position + camera_width - 1), 
                math.floor(camera_y_position - 1)
            )
            
            draw.SetFont(title_font)
            draw.Color(255, 255, 255, 255)
            local text = "Enemy Spectator"
            if target_player then
                local playerName = target_player:GetName()
                if playerName then
                    text = text .. " - " .. playerName
                    if first_person_mode then
                        text = text .. " (First Person)"
                    elseif free_camera then
                        text = text .. " (Free Camera)"
                    end
                end
            end
            
            local textW, textH = draw.GetTextSize(text)
            draw.Text(
                math.floor(camera_x_position + camera_width * 0.5 - textW * 0.5),
                math.floor(camera_y_position - 16), 
                text
            )
            
            draw.Color(255, 255, 255, 200)
            local controls = {
                "Controls:",
                "Mouse - Look around",
                "WASD - Move camera",
                "E/Q - Up/Down",
                "Space - Toggle perspective",
                "Tab - Cycle enemy players",
                "Ctrl - Toggle fullscreen"
            }
            
            for i, text in ipairs(controls) do
                draw.Text(
                    math.floor(camera_x_position + 5),
                    math.floor(camera_y_position + camera_height + 5 + (i-1)*15),
                    text
                )
            end
        end
    end
end)

callbacks.Register("FireGameEvent", HandleKillfeedEvent)
InitializeAllMaterials()

callbacks.Register("Unload", function()
    CleanupMaterials()
    CleanupState()
end)
