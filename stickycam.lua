-- Camera state and configuration
local camera_x_position = 5
local camera_y_position = 300
local camera_width = 500 
local camera_height = 300
local CAMERA_OFFSET = 35
local TARGET_LOCK_DURATION = 5
local TARGET_SEARCH_RADIUS = 146 * 4  -- Increased to 4x sticky explosion radius
local OCCLUSION_CHECK_INTERVAL = 0.1
local ANGLE_INTERPOLATION_SPEED = 0.1

-- Sticky and target tracking state
local stickies = {}
local current_sticky = nil
local current_target = nil
local smoothed_angles = EulerAngles(0, 0, 0)
local target_lock_time = 0
local target_visible = false
local last_occlusion_check = 0

-- Sticky cycling state
local last_key_press = globals.RealTime()
local key_delay = 0.2
local visited_stickies = {}

-- Material state
local materials_initialized = false
local cameraTexture = nil
local cameraMaterial = nil
local invisibleMaterial = nil

-- Font for HUD
local font = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)

local function InitializeMaterials()
    if materials_initialized then return true end
    
    -- Clean up any existing materials first
    if cameraTexture then
        draw.DeleteTexture(cameraTexture)
        cameraTexture = nil
    end
    
    -- Create texture
    cameraTexture = materials.CreateTextureRenderTarget("camMaterial", camera_width, camera_height)
    if not cameraTexture then
        print("Failed to create camera texture")
        return false
    end
    
    -- Create material using the texture
    local materialName = "camMaterial"
    cameraMaterial = materials.Create("camMaterial", string.format([[
        UnlitGeneric
        {
            $basetexture    "%s"
            $ignorez        1
            $nofog         1
        }
    ]], materialName))
    if not cameraMaterial then
        print("Failed to create camera material")
        if cameraTexture then
            draw.DeleteTexture(cameraTexture)
            cameraTexture = nil
        end
        return false
    end

    invisibleMaterial = materials.Create("invisible_material", [[
        VertexLitGeneric
        {
            $basetexture    "vgui/white"
            $no_draw        1
        }
    ]])
    
    materials_initialized = true
    return true
end

local function CalculateAngles(source, dest)
    local M_RADPI = 180 / math.pi
    local delta = Vector3(dest.x - source.x, dest.y - source.y, dest.z - source.z)
    local hyp = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    
    -- Calculate pitch
    local pitch = math.atan(delta.z / hyp) * M_RADPI
    
    -- Calculate yaw using atan
    local yaw = math.atan(delta.y / delta.x) * M_RADPI
    
    -- Adjust yaw based on quadrant
    if delta.x < 0 then
        yaw = yaw + 180
    elseif delta.y < 0 then
        yaw = yaw + 360
    end
    
    -- Handle NaN cases
    if pitch ~= pitch then pitch = 0 end
    if yaw ~= yaw then yaw = 0 end
    
    return EulerAngles(-pitch, yaw, 0)
end

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

local function IsStickyOnCeiling(sticky)
    local pos = sticky:GetAbsOrigin()
    
    -- Check if there's something solid above us and nothing below
    local ceilingTrace = engine.TraceLine(pos, pos + Vector3(0, 0, 10), MASK_SOLID)
    local floorTrace = engine.TraceLine(pos, pos - Vector3(0, 0, 10), MASK_SOLID)
    
    return ceilingTrace.fraction < 0.3 and floorTrace.fraction > 0.7
end

local function GetStickyNormal(sticky)
    local pos = sticky:GetAbsOrigin()
    local upTrace = engine.TraceLine(pos, pos + Vector3(0, 0, 5), MASK_SOLID)
    
    -- If there's something very close above us, we're probably on a ceiling
    if upTrace.fraction < 0.2 then
        return Vector3(0, 0, 1)  -- Return upward normal
    end
    
    local downTrace = engine.TraceLine(pos, pos - Vector3(0, 0, 5), MASK_SOLID)
    if downTrace.fraction < 1 then
        return downTrace.plane
    end
    
    return Vector3(0, 0, 1)  -- Default to up if no surface found
end

local function CalculateCameraOffset(stickyPos, normal)
    -- Check which direction is blocked
    local upTrace = engine.TraceLine(stickyPos, stickyPos + Vector3(0, 0, 15), MASK_SOLID)
    local downTrace = engine.TraceLine(stickyPos, stickyPos - Vector3(0, 0, 15), MASK_SOLID)
    
    -- If up is blocked but down is open, force camera downward
    if upTrace.fraction < 0.5 and downTrace.fraction > 0.5 then
        return stickyPos - Vector3(0, 0, CAMERA_OFFSET)
    end
    
    -- If down is blocked but up is open, force camera upward
    if downTrace.fraction < 0.5 and upTrace.fraction > 0.5 then
        return stickyPos + Vector3(0, 0, CAMERA_OFFSET)
    end
    
    -- If neither is clearly blocked, use the normal
    return stickyPos + normal * CAMERA_OFFSET
end

local function FindNearestVisiblePlayer(position)
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return nil end
    
    -- Debug positions
    local screenPos = client.WorldToScreen(position)
    if screenPos then
        draw.Color(255, 0, 0, 255)
        draw.FilledRect(screenPos[1]-2, screenPos[2]-2, screenPos[1]+2, screenPos[2]+2)
    end
    
    if current_target and globals.RealTime() - target_lock_time < TARGET_LOCK_DURATION then
        if current_target:IsValid() and current_target:IsAlive() and not current_target:IsDormant() then
            if globals.RealTime() - last_occlusion_check > OCCLUSION_CHECK_INTERVAL then
                target_visible = CheckPlayerVisibility(position, current_target)
                last_occlusion_check = globals.RealTime()
                
                -- Debug target position
                local targetScreenPos = client.WorldToScreen(current_target:GetAbsOrigin())
                if targetScreenPos and target_visible then
                    draw.Color(0, 255, 0, 255)
                    draw.FilledRect(targetScreenPos[1]-3, targetScreenPos[2]-3, 
                                  targetScreenPos[1]+3, targetScreenPos[2]+3)
                end
            end
            
            if target_visible then
                local targetPos = current_target:GetAbsOrigin()
                local dist = (targetPos - position):Length()
                if dist <= TARGET_SEARCH_RADIUS then
                    return current_target
                end
            end
        end
    end
    
    local nearest = nil
    local nearestDist = TARGET_SEARCH_RADIUS
    
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player:IsValid() and player:IsAlive() and not player:IsDormant() and
           player:GetTeamNumber() ~= localPlayer:GetTeamNumber() then
            
            local playerPos = player:GetAbsOrigin()
            local dist = (playerPos - position):Length()
            
            -- Debug each potential target
            local playerScreenPos = client.WorldToScreen(playerPos)
            if playerScreenPos then
                draw.Color(255, 255, 0, 255)
                draw.FilledRect(playerScreenPos[1]-2, playerScreenPos[2]-2,
                              playerScreenPos[1]+2, playerScreenPos[2]+2)
            end
            
            if dist < nearestDist and CheckPlayerVisibility(position, player) then
                nearest = player
                nearestDist = dist
            end
        end
    end
    
    if nearest and nearest ~= current_target then
        target_lock_time = globals.RealTime()
        target_visible = true
        last_occlusion_check = globals.RealTime()
    end
    
    return nearest
end

local function LerpAngles(start, target, factor)
    local dx = target.x - start.x
    local dy = target.y - start.y
    
    while dy > 180 do dy = dy - 360 end
    while dy < -180 do dy = dy + 360 end
    
    return EulerAngles(
        start.x + dx * factor,
        start.y + dy * factor,
        0
    )
end

local function UpdateStickies()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    -- Clean up invalid stickies from our list
    for i = #stickies, 1, -1 do
        if not stickies[i]:IsValid() or stickies[i]:IsDormant() then
            table.remove(stickies, i)
            -- Also remove from visited if it was there
            for j = #visited_stickies, 1, -1 do
                if visited_stickies[j] == stickies[i] then
                    table.remove(visited_stickies, j)
                end
            end
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

    -- Only update current_sticky if we don't have a valid one from cycling
    if not current_sticky or not current_sticky:IsValid() or current_sticky:IsDormant() then
        current_sticky = nil
        current_target = nil
        target_visible = false
        
        -- Find any valid sticky to use
        for i = #stickies, 1, -1 do
            local sticky = stickies[i]
            local vel = sticky:EstimateAbsVelocity()
            
            if vel:Length() < 1 then
                local stickyPos = sticky:GetAbsOrigin()
                if FindNearestVisiblePlayer(stickyPos) then
                    current_sticky = sticky
                    break
                end
            end
        end
    end
end

local function IsCameraViewClear(origin, angles)
    local forward = angles:Forward()
    local trace = engine.TraceLine(
        origin, 
        origin + forward * 50,
        MASK_SOLID
    )
    return trace.fraction > 0.9
end

-- Move this function definition before UpdateUserInput
local function CycleNextSticky()
    -- Find available stationary stickies
    local available_stickies = {}
    for _, sticky in ipairs(stickies) do
        if sticky and sticky:IsValid() and not sticky:IsDormant() then
            local vel = sticky:EstimateAbsVelocity()
            if vel:Length() < 1 then
                table.insert(available_stickies, sticky)
            end
        end
    end

    print(string.format("Available stickies: %d, Total stickies: %d", #available_stickies, #stickies)) -- Debug print
    
    if #available_stickies == 0 then
        current_sticky = nil
        current_target = nil
        target_visible = false
        visited_stickies = {}
        return
    end
    
    -- Find unvisited stickies
    local unvisited_stickies = {}
    for _, sticky in ipairs(available_stickies) do
        local already_visited = false
        for _, visited in ipairs(visited_stickies) do
            if visited == sticky then
                already_visited = true
                break
            end
        end
        
        if not already_visited then
            table.insert(unvisited_stickies, sticky)
        end
    end
    
    print(string.format("Unvisited stickies: %d, Visited stickies: %d", #unvisited_stickies, #visited_stickies)) -- Debug print
    
    -- Reset if all stickies visited
    if #unvisited_stickies == 0 then
        visited_stickies = {}
        unvisited_stickies = available_stickies
        print("Reset visited stickies list") -- Debug print
    end
    
    if #unvisited_stickies > 0 then
        current_sticky = unvisited_stickies[1]
        table.insert(visited_stickies, current_sticky)
        current_target = nil
        target_visible = false
        target_lock_time = 0
        print("Cycled to next sticky") -- Debug print
    end
end

local function UpdateUserInput()
    local current_time = globals.RealTime()
    
    if input.IsButtonPressed(KEY_TAB) and current_time - last_key_press > key_delay then
        print("TAB pressed, cycling stickies")
        CycleNextSticky()
        last_key_press = current_time
        return true
    end
    
    return false
end

-- Update the Draw callback to show correct counts
callbacks.Register("Draw", function()
    if not current_sticky or not current_target then return end
    
    -- Previous drawing code stays the same until title...
    
    local playerName = current_target:GetName() or "Unknown"
    local timeRemaining = math.max(0, TARGET_LOCK_DURATION - (globals.RealTime() - target_lock_time))
    local targetStatus = target_visible and "Tracking" or "Target Lost"
    
    -- Count only valid, stationary stickies
    local available_count = 0
    for _, sticky in ipairs(stickies) do
        if sticky and sticky:IsValid() and not sticky:IsDormant() then
            local vel = sticky:EstimateAbsVelocity()
            if vel:Length() < 1 then
                available_count = available_count + 1
            end
        end
    end
    
    local title = string.format("Sticky Security Camera - %s: %s (%.1fs) [%d/%d]", 
        targetStatus, playerName, timeRemaining, 
        math.min(#visited_stickies, available_count), available_count)
        
    local w, h = draw.GetTextSize(title)
    draw.Text(
        math.floor(camera_x_position + camera_width * 0.5 - w * 0.5),
        math.floor(camera_y_position - 16),
        title
    )
    
    -- Draw controls text
    draw.Color(255, 255, 255, 200)
    draw.Text(
        math.floor(camera_x_position + 5),
        math.floor(camera_y_position + camera_height + 5),
        "TAB - Cycle stickies"
    )
end)

callbacks.Register("CreateMove", function(cmd)
    -- Handle user input first
    UpdateUserInput()
    
    -- Regular sticky updates
    UpdateStickies()
    
    if current_sticky and current_sticky:IsValid() and not current_sticky:IsDormant() then
        local stickyPos = current_sticky:GetAbsOrigin()
        local normal = GetStickyNormal(current_sticky)
        local cameraPos = CalculateCameraOffset(stickyPos, normal)
        
        current_target = FindNearestVisiblePlayer(cameraPos)
        
        if current_target and target_visible then
            local targetPos = current_target:GetAbsOrigin() + Vector3(0, 0, 50)
            local targetAngles = CalculateAngles(cameraPos, targetPos)
            smoothed_angles = LerpAngles(smoothed_angles, targetAngles, ANGLE_INTERPOLATION_SPEED)
        end
    else
        current_target = nil
        target_visible = false
    end
end)

-- Update PostRenderView to use new camera positioning
callbacks.Register("PostRenderView", function(view)
    if not materials_initialized and not InitializeMaterials() then
        return
    end
    
    if not current_sticky or not current_target or not cameraMaterial or not cameraTexture or not target_visible then 
        return 
    end
    
    local customView = view
    local normal = GetStickyNormal(current_sticky)
    local stickyPos = current_sticky:GetAbsOrigin()
    local cameraOrigin = CalculateCameraOffset(stickyPos, normal)
    customView.origin = cameraOrigin
    customView.angles = smoothed_angles

    if not IsCameraViewClear(cameraOrigin, smoothed_angles) then
        return
    end
    
    render.Push3DView(customView, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, cameraTexture)
    render.ViewDrawScene(true, true, customView)
    render.PopView()
    
    render.DrawScreenSpaceRectangle(
        cameraMaterial, 
        camera_x_position, camera_y_position,
        camera_width, camera_height,
        0, 0, camera_width, camera_height,
        camera_width, camera_height
    )
end)

callbacks.Register("Draw", function()
    if not current_sticky or not current_target then return end
    
    draw.Color(235, 64, 52, 255)
    draw.OutlinedRect(
        camera_x_position,
        camera_y_position,
        camera_x_position + camera_width,
        camera_y_position + camera_height
    )
    
    draw.OutlinedRect(
        camera_x_position,
        camera_y_position - 20,
        camera_x_position + camera_width,
        camera_y_position
    )
    
    draw.Color(130, 26, 17, 255)
    draw.FilledRect(
        camera_x_position + 1,
        camera_y_position - 19,
        camera_x_position + camera_width - 1,
        camera_y_position - 1
    )
    
    draw.SetFont(font)
    draw.Color(255, 255, 255, 255)
    local playerName = current_target:GetName() or "Unknown"
    local timeRemaining = math.max(0, TARGET_LOCK_DURATION - (globals.RealTime() - target_lock_time))
    local targetStatus = target_visible and "Tracking" or "Target Lost"
    local title = string.format("Sticky Security Camera - %s: %s (%.1fs) [%d/%d]", 
        targetStatus, playerName, timeRemaining, #visited_stickies, #stickies)
    
    local w, h = draw.GetTextSize(title)
    draw.Text(
        math.floor(camera_x_position + camera_width * 0.5 - w * 0.5),
        math.floor(camera_y_position - 16),
        title
    )
end)

callbacks.Register("DrawModel", function(ctx)
    if not current_sticky or not invisibleMaterial then return end
    
    local ent = ctx:GetEntity()
    if not ent then return end

    if ent == current_sticky then
        ctx:ForcedMaterialOverride(invisibleMaterial)
    end
end)

-- Initialize materials when script loads
InitializeMaterials()

callbacks.Register("Unload", function()
    materials_initialized = false
    stickies = {}
    current_sticky = nil
    current_target = nil
    target_visible = false
    
    if cameraTexture then
        draw.DeleteTexture(cameraTexture)
        cameraTexture = nil
    end
    
    invisibleMaterial = nil
    cameraMaterial = nil
end)
