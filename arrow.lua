-- Configuration for Medic Arrow ESP
local enemy_only = true
local max_dist = 2800 -- hammer units

local box_3d = false  -- Toggle for 3D box ESP
local box_2d = true  -- Toggle for 2D box ESP
local box_color_visible = { 0, 255, 0, 255 }  -- Green for visible arrows
local box_color_invisible = { 255, 255, 0, 255 }  -- Yellow for not visible arrows

local box_2d_size = 20 -- Size of the 2D box in pixels
local boxOnlyWhenVisible = false

-- Chams settings
local chamsOn = true
local chamsOnlyWhenVisible = false

-- Cache system configuration
local visibilityCheckInterval = 0.1  -- Check visibility every 0.1 seconds
local cacheCleanupInterval = 1.0     -- Clean caches every 1.0 seconds
local nextCleanupTime = 0
local hitboxCacheLifetime = 0.2      -- Hitbox cache lifetime in seconds

-- Centralized cache tables
local visibilityCache = {}
local hitboxCache = {}
local cachedArrows = {}
local lastArrowUpdate = 0
local arrowUpdateInterval = 0.1

-- Heal tracer configuration
local max_records = 5
local disappear_time = 3
local show_heal_box = true
local show_tracer = true
local show_heal_marker = true
local visible_only = false
local heal_box_color = {0, 255, 0, 128}
local tracer_color = {0, 255, 255, 255}
local heal_marker_color = {0, 128, 255, 255}

-- Heal information storage
local healInfo = {}

-- Cham material definitions
local visibleMaterial = materials.Create("VisibleArrow", [[
"VertexLitGeneric"
{
    $basetexture "vgui/white_additive"
    $bumpmap "models/player/shared/shared_normal"
    $phong "1"
    $phongexponent "10"
    $phongboost "1"
    $phongfresnelranges "[0 0 0]"
    $basemapalphaphongmask "1"
    $color2 "[0 1 0]"
}
]])

local invisibleMaterial = materials.Create("InvisibleArrow", [[
"VertexLitGeneric"
{
    $basetexture "vgui/white_additive"
    $bumpmap "models/player/shared/shared_normal"
    $phong "1"
    $phongexponent "10"
    $phongboost "1"
    $phongfresnelranges "[0 0 0]"
    $basemapalphaphongmask "1"
    $color2 "[1 1 0]"
    $ignorez "1"
}
]])

local function cleanCaches()
    local currentTime = globals.RealTime()
    if currentTime < nextCleanupTime then return end
    
    for entityIndex, data in pairs(visibilityCache) do
        if (currentTime - data.time) > visibilityCheckInterval * 2 then
            visibilityCache[entityIndex] = nil
        end
    end
    
    for entityIndex, data in pairs(hitboxCache) do
        if (currentTime - data.time) > hitboxCacheLifetime * 2 then
            hitboxCache[entityIndex] = nil
        end
    end
    
    for i = #healInfo, 1, -1 do
        if (currentTime - healInfo[i].time) > disappear_time then
            table.remove(healInfo, i)
        end
    end
    
    nextCleanupTime = currentTime + cacheCleanupInterval
end

local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end
    
    local currentTime = globals.RealTime()
    local entityIndex = entity:GetIndex()
    
    if visibilityCache[entityIndex] and 
       (currentTime - visibilityCache[entityIndex].time) < visibilityCheckInterval then
        return visibilityCache[entityIndex].visible
    end
    
    local source = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = entity:GetAbsOrigin()
    
    local trace = engine.TraceLine(source, targetPos, MASK_VISIBLE)
    local isVisible = trace.fraction > 0.99 or trace.entity == entity
    
    visibilityCache[entityIndex] = {
        time = currentTime,
        visible = isVisible
    }
    
    return isVisible
end

local function getHitboxWithCache(entity)
    if not entity then return nil end
    
    local currentTime = globals.RealTime()
    local entityIndex = entity:GetIndex()
    
    if hitboxCache[entityIndex] and 
       (currentTime - hitboxCache[entityIndex].time) < hitboxCacheLifetime then
        return hitboxCache[entityIndex].hitbox
    end
    
    local hitbox = entity:HitboxSurroundingBox()
    if hitbox then
        hitboxCache[entityIndex] = {
            time = currentTime,
            hitbox = hitbox
        }
    end
    
    return hitbox
end

local function draw_3d_box(vertices, color)
    draw.Color(table.unpack(color))
    local edges = {
        {1,2}, {2,3}, {3,4}, {4,1},
        {5,6}, {6,7}, {7,8}, {8,5},
        {1,5}, {2,6}, {3,7}, {4,8}
    }
    
    for _, edge in ipairs(edges) do
        local v1, v2 = vertices[edge[1]], vertices[edge[2]]
        if v1 and v2 then
            draw.Line(v1.x, v1.y, v2.x, v2.y)
        end
    end
end

local function draw_2d_box(x, y, size, color)
    draw.Color(table.unpack(color))
    local half_size = size / 2
    local x1, y1 = x - half_size, y - half_size
    local x2, y2 = x + half_size, y + half_size
    
    draw.Line(x1, y1, x2, y1)
    draw.Line(x1, y2, x2, y2)
    draw.Line(x1, y1, x1, y2)
    draw.Line(x2, y1, x2, y2)
end

local function medic_arrow_esp()
    local currentTime = globals.RealTime()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    if (currentTime - lastArrowUpdate) > arrowUpdateInterval then
        cachedArrows = entities.FindByClass("CTFProjectile_HealingBolt")
        lastArrowUpdate = currentTime
    end
    
    cleanCaches()
    
    for _, arrow in pairs(cachedArrows) do
        if arrow:IsValid() and not arrow:IsDormant() then
            local arrow_pos = arrow:GetAbsOrigin()
            
            if vector.Distance(localPlayer:GetAbsOrigin(), arrow_pos) > max_dist then
                goto continue
            end
            
            if enemy_only and arrow:GetTeamNumber() == localPlayer:GetTeamNumber() then
                goto continue
            end
            
            local arrow_screen = client.WorldToScreen(arrow_pos)
            if not arrow_screen then goto continue end
            
            local isVisible = IsVisible(arrow, localPlayer)
            if boxOnlyWhenVisible and not isVisible then
                goto continue
            end
            
            local color = isVisible and box_color_visible or box_color_invisible
            
            if box_2d then
                draw_2d_box(arrow_screen[1], arrow_screen[2], box_2d_size, color)
            end
            
            if box_3d then
                local hitboxes = getHitboxWithCache(arrow)
                if hitboxes then
                    local min, max = hitboxes[1], hitboxes[2]
                    local vertices = {
                        Vector3(min.x, min.y, min.z), Vector3(min.x, max.y, min.z),
                        Vector3(max.x, max.y, min.z), Vector3(max.x, min.y, min.z),
                        Vector3(min.x, min.y, max.z), Vector3(min.x, max.y, max.z),
                        Vector3(max.x, max.y, max.z), Vector3(max.x, min.y, max.z)
                    }
                    
                    local screenVertices = {}
                    local allValid = true
                    for j, vertex in ipairs(vertices) do
                        local screenPos = client.WorldToScreen(vertex)
                        if screenPos then
                            screenVertices[j] = {x = screenPos[1], y = screenPos[2]}
                        else
                            allValid = false
                            break
                        end
                    end
                    
                    if allValid then
                        draw_3d_box(screenVertices, color)
                    end
                end
            end
        end
        ::continue::
    end
end

local function onDrawModel(ctx)
    if not chamsOn then return end

    local entity = ctx:GetEntity()
    if entity and entity:IsValid() and entity:GetClass() == "CTFProjectile_HealingBolt" then
        local localPlayer = entities.GetLocalPlayer()
        if not localPlayer then return end

        if enemy_only and entity:GetTeamNumber() == localPlayer:GetTeamNumber() then
            ctx:ForcedMaterialOverride(nil)
            return
        end

        local isVisible = IsVisible(entity, localPlayer)

        if isVisible then
            ctx:ForcedMaterialOverride(visibleMaterial)
        else
            if not chamsOnlyWhenVisible then
                ctx:ForcedMaterialOverride(invisibleMaterial)
            else
                ctx:ForcedMaterialOverride(nil)
            end
        end
    end
end

local function DrawBox(min, max, color)
    local vertices = {
        Vector3(min.x, min.y, min.z), Vector3(min.x, max.y, min.z),
        Vector3(max.x, max.y, min.z), Vector3(max.x, min.y, min.z),
        Vector3(min.x, min.y, max.z), Vector3(min.x, max.y, max.z),
        Vector3(max.x, max.y, max.z), Vector3(max.x, min.y, max.z)
    }
    
    local screenVertices = {}
    for _, v in ipairs(vertices) do
        local screenPos = client.WorldToScreen(v)
        if screenPos then
            table.insert(screenVertices, {x = screenPos[1], y = screenPos[2]})
        end
    end
    
    if #screenVertices == 8 then
        draw.Color(table.unpack(color))
        for _, edge in ipairs({{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}) do
            local v1, v2 = screenVertices[edge[1]], screenVertices[edge[2]]
            draw.Line(v1.x, v1.y, v2.x, v2.y)
        end
    end
end

local function DrawHealMarker(pos, color)
    local screenPos = client.WorldToScreen(pos)
    if screenPos then
        draw.Color(table.unpack(color))
        local size = 5
        draw.Line(screenPos[1] - size, screenPos[2] - size, screenPos[1] + size, screenPos[2] + size)
        draw.Line(screenPos[1] - size, screenPos[2] + size, screenPos[1] + size, screenPos[2] - size)
    end
end

local function PlayerHealedEvent(event)
    if (event:GetName() == 'player_healed') then
        local localPlayer = entities.GetLocalPlayer()
        if not localPlayer then return end

        local patient = entities.GetByUserID(event:GetInt("patient"))
        local healer = entities.GetByUserID(event:GetInt("healer"))

        -- Skip if healer is invalid or if healer is healing themselves
        if not healer or not healer:IsValid() or healer:GetIndex() == patient:GetIndex() then
            return
        end

        -- Look for healing bolts that belong to this healer
        local arrows = entities.FindByClass("CTFProjectile_HealingBolt")
        local foundArrow = false
        for _, arrow in pairs(arrows) do
            if arrow:IsValid() and arrow:GetPropEntity("m_hOwnerEntity") == healer then
                foundArrow = true
                break
            end
        end

        -- Only proceed if we found a healing bolt from this healer
        if not foundArrow then return end

        if not enemy_only or patient:GetTeamNumber() ~= localPlayer:GetTeamNumber() then
            local startPos = healer:GetAbsOrigin() + healer:GetPropVector("localdata", "m_vecViewOffset[0]")
            local endPos = patient:GetAbsOrigin()
            local box = getHitboxWithCache(patient)

            table.insert(healInfo, 1, {
                startPos = startPos,
                endPos = endPos,
                healPos = endPos,
                box = box,
                time = globals.RealTime(),
                visible = not visible_only or IsVisible(patient, localPlayer)
            })

            if #healInfo > max_records then 
                table.remove(healInfo)
            end
        end
    end
end

local function HealTracerESP()
    for i, info in ipairs(healInfo) do
        if show_heal_box and info.box then
            DrawBox(info.box[1], info.box[2], heal_box_color)
        end

        if show_tracer then
            local w2s_startPos = client.WorldToScreen(info.startPos)
            local w2s_endPos = client.WorldToScreen(info.endPos)
            if w2s_startPos and w2s_endPos then
                draw.Color(table.unpack(tracer_color))
                draw.Line(w2s_startPos[1], w2s_startPos[2], w2s_endPos[1], w2s_endPos[2])
            end
        end

        if show_heal_marker then
            DrawHealMarker(info.healPos, heal_marker_color)
        end
    end
end

callbacks.Register("Draw", "medic_arrow_esp", medic_arrow_esp)
callbacks.Register("DrawModel", "ArrowChams", onDrawModel)
callbacks.Register("FireGameEvent", "PlayerHealedEvent", PlayerHealedEvent)
callbacks.Register("Draw", "HealTracerESP", HealTracerESP)
