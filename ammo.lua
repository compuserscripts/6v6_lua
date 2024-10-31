-- Cache commonly used functions 
local FIND_BY_CLASS = entities.FindByClass
local WORLD_TO_SCREEN = client.WorldToScreen
local COLOR = draw.Color
local LINE = draw.Line
local TRACE_LINE = engine.TraceLine
local CUR_TIME = globals.CurTime
local POLYGON = draw.TexturedPolygon
local CROSS = (function(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) end)
local VECTOR_LENGTH = (function(v1, v2) return math.sqrt((v2.x - v1.x) ^ 2 + (v2.y - v1.y) ^ 2 + (v2.z - v1.z) ^ 2) end)
local TICK_COUNT = globals.TickCount

local floor = math.floor
local min = math.min
local max = math.max
local cos = math.cos
local sin = math.sin
local rad = math.rad
local format = string.format

-- Add update interval control
local lastUpdateTick = 0
local UPDATE_INTERVAL = 2 -- Update positions every 2 ticks

-- Optimization: Add caches
local nextVisCheck = {}
local visibilityCache = {}
local modelCache = {}
local vecCache = {
    eyePos = Vector3(0, 0, 0),
    viewOffset = Vector3(0, 0, 0)
}

-- Debug mode
local DEBUG = false

-- Configuration (all RGB/Alpha values are 0-255)
local config = {
    -- Toggles
    showGroundPieChart = false,    
    showScreenPieChart = true,     
    showSeconds = false,            
    showMilliseconds = false,      
    scaleWithDistance = true,      
    scaleTextWithDistance = true,  
    
    -- Distances
    maxDistances = {
        groundPieChart = 1000,     
        screenPieChart = 1000,     
        text = 1000               
    },
    
    -- Sizes and segments
    pieChartSize = 20,            
    pieChartSegments = 32,        
    minScreenChartSize = 5,      
    maxScreenChartSize = 20,      
    maxScaleDistance = 1000,      
    
    -- Text sizes
    textSize = {
        min = 12,                  
        max = 20,                  
        default = 16              
    },
    
    -- Colors
    healthColor = {
        r = 155, g = 200, b = 155, 
        polygonAlpha = 200         
    },
    ammoColor = {
        r = 255, g = 255, b = 155, 
        polygonAlpha = 200         
    },
    secondsColor = {
        r = 255, g = 255, b = 255, 
        alpha = 255               
    }
}

-- Create default font
local font = draw.CreateFont("Verdana", config.textSize.default, 800)

-- Cache fonts for different sizes
local fontCache = {}
local function GetFont(size)
    size = math.floor(size)
    if not fontCache[size] then
        fontCache[size] = draw.CreateFont("Verdana", size, 800)
    end
    return fontCache[size]
end

-- Create textures
local clockTexture = draw.CreateTextureRGBA(string.char(255, 255, 255, 255), 1, 1)
local fillTextureHealth = draw.CreateTextureRGBA(string.char(
    config.healthColor.r, config.healthColor.g, config.healthColor.b, config.healthColor.polygonAlpha,
    config.healthColor.r, config.healthColor.g, config.healthColor.b, config.healthColor.polygonAlpha,
    config.healthColor.r, config.healthColor.g, config.healthColor.b, config.healthColor.polygonAlpha,
    config.healthColor.r, config.healthColor.g, config.healthColor.b, config.healthColor.polygonAlpha
), 2, 2)

local fillTextureAmmo = draw.CreateTextureRGBA(string.char(
    config.ammoColor.r, config.ammoColor.g, config.ammoColor.b, config.ammoColor.polygonAlpha,
    config.ammoColor.r, config.ammoColor.g, config.ammoColor.b, config.ammoColor.polygonAlpha,
    config.ammoColor.r, config.ammoColor.g, config.ammoColor.b, config.ammoColor.polygonAlpha,
    config.ammoColor.r, config.ammoColor.g, config.ammoColor.b, config.ammoColor.polygonAlpha
), 2, 2)

-- Standard respawn time
local RESPAWN_TIME = 10.0

-- Store initial positions of supplies
local supplyPositions = {}

-- Optimization: Cached model check
local function GetPickupType(entity)
    if not entity then return nil end
    
    local model = entity:GetModel()
    if not model then return nil end
    
    local modelName = models.GetModelName(model)
    if not modelName then return nil end
    
    if modelCache[modelName] then
        return modelCache[modelName]
    end
    
    modelName = string.lower(modelName)
    
    if string.find(modelName, "ammopack") then
        modelCache[modelName] = "ammo"
        return "ammo"
    elseif string.find(modelName, "medkit") or string.find(modelName, "healthkit") then
        modelCache[modelName] = "health"
        return "health"
    end
    
    modelCache[modelName] = nil
    return nil
end

-- Calculate screen chart size
local function GetScreenChartSize(distance)
    if not config.scaleWithDistance then
        return config.pieChartSize
    end
    
    local scale = 1 - math.min(distance / config.maxScaleDistance, 1)
    local size = config.minScreenChartSize + (config.maxScreenChartSize - config.minScreenChartSize) * scale
    return math.max(config.minScreenChartSize, math.min(config.maxScreenChartSize, size))
end

-- Get text size
local function GetTextSize(distance)
    if not config.scaleTextWithDistance then
        return config.textSize.default
    end
    
    local scale = 1 - math.min(distance / config.maxScaleDistance, 1)
    return math.max(config.textSize.min,
                   math.min(config.textSize.max,
                           config.textSize.min + (config.textSize.max - config.textSize.min) * scale))
end

-- Function to create a filled clock polygon
local function DrawClockFill(centerX, centerY, radius, percentage, vertices, colorTable)
    if percentage <= 0 or percentage > 1 then return end
    
    local points = {}
    table.insert(points, {centerX, centerY, 0, 0})
    
    local startAngle = -90
    local endAngle = startAngle + (360 * percentage)
    local step = (endAngle - startAngle) / vertices
    
    for i = 0, vertices do
        local angle = rad(startAngle + (i * step))
        local x = centerX + cos(angle) * radius
        local y = centerY + sin(angle) * radius
        table.insert(points, {x, y, 0, 0})
    end
    
    COLOR(colorTable.r, colorTable.g, colorTable.b, colorTable.polygonAlpha)
    POLYGON(clockTexture, points)
end

-- Ground polygon drawing
local function DrawFilledProgress(pos, radius, percentage, segments, colorTable, fillTexture)
    local positions = {}
    local screenPositions = {}
    local offsetZ = 1

    for i = 1, segments do
        local ang = i * (2 * math.pi / segments)
        local worldPos = Vector3(
            pos.x + radius * cos(ang),
            pos.y + radius * sin(ang),
            pos.z + offsetZ
        )
        local screenPos = WORLD_TO_SCREEN(worldPos)
        if screenPos then
            table.insert(positions, screenPos)
        else
            return
        end
    end

    local centerScreen = WORLD_TO_SCREEN(Vector3(pos.x, pos.y, pos.z + offsetZ))
    if not centerScreen then return end

    local visibleVerts = floor((1 - percentage) * segments)
    if visibleVerts <= 0 then return end

    local coords = {}
    local reverseCoords = {}
    local totalVerts = visibleVerts + 1

    table.insert(coords, {centerScreen[1], centerScreen[2], 0, 0})
    reverseCoords[totalVerts] = {centerScreen[1], centerScreen[2], 0, 0}

    for i = 1, visibleVerts do
        local pos = positions[i]
        local coordEntry = {pos[1], pos[2], 0, 0}
        table.insert(coords, coordEntry)
        reverseCoords[totalVerts - i] = coordEntry
    end

    COLOR(colorTable.r, colorTable.g, colorTable.b, colorTable.polygonAlpha)
    local sum = 0
    for i = 1, #coords - 1 do
        sum = sum + CROSS(coords[i], coords[i + 1], coords[1])
    end
    
    POLYGON(fillTexture, sum < 0 and reverseCoords or coords, true)
end

-- Optimization: Cached visibility check
local function IsVisible(pos)
    local id = math.floor(pos.x) .. math.floor(pos.y) .. math.floor(pos.z)
    local curTick = TICK_COUNT()
    
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
    
    local trace = TRACE_LINE(vecCache.eyePos, pos, MASK_SHOT_HULL)
    
    visibilityCache[id] = trace.fraction > 0.99
    nextVisCheck[id] = curTick + 3
    
    return visibilityCache[id]
end

-- Update supply positions
local function UpdateSupplyPositions()
    local currentTick = TICK_COUNT()
    if currentTick - lastUpdateTick < UPDATE_INTERVAL then return end
    lastUpdateTick = currentTick
    
    local currentSupplies = {} -- Declare it here
    local currentTime = CUR_TIME() -- Also need this
    
    local entities = FIND_BY_CLASS("CBaseAnimating")
    
    for _, entity in pairs(entities) do
        if entity:IsValid() and not entity:IsDormant() then
            local pickupType = GetPickupType(entity)
            if pickupType then
                local pos = entity:GetAbsOrigin()
                local key = format("%.0f_%.0f_%.0f", pos.x, pos.y, pos.z)
                currentSupplies[key] = true
                
                if not supplyPositions[key] then
                    supplyPositions[key] = {
                        pos = pos,
                        type = pickupType,
                        respawning = false,
                        disappearTime = 0
                    }
                end
            end
        end
    end
    
    for key, info in pairs(supplyPositions) do
        if not currentSupplies[key] and not info.respawning then
            info.respawning = true
            info.disappearTime = currentTime
        elseif currentSupplies[key] and info.respawning then
            info.respawning = false
            info.disappearTime = 0
        end
    end
end

-- Main ESP callback
callbacks.Register("Draw", "SupplyRespawnESP", function()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end
    draw.SetFont(font)
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not localPlayer:IsAlive() then return end
    
    UpdateSupplyPositions()
    
    local currentTime = CUR_TIME()
    local playerPos = localPlayer:GetAbsOrigin()
    
    for _, info in pairs(supplyPositions) do
        if info.respawning and IsVisible(info.pos) then
            local screenPos = WORLD_TO_SCREEN(info.pos)
            if screenPos then
                local timeLeft = math.max(0, RESPAWN_TIME - (currentTime - info.disappearTime))
                local timePercent = timeLeft / RESPAWN_TIME
                
                local colorConfig = info.type == "health" and config.healthColor or config.ammoColor
                local fillTexture = info.type == "health" and fillTextureHealth or fillTextureAmmo
                
                local distance = VECTOR_LENGTH(playerPos, info.pos)
                
                if config.showGroundPieChart and distance <= config.maxDistances.groundPieChart then
                    DrawFilledProgress(info.pos, config.pieChartSize, timePercent, config.pieChartSegments, colorConfig, fillTexture)
                end
                
                if config.showScreenPieChart and distance <= config.maxDistances.screenPieChart then
                    local screenChartSize = GetScreenChartSize(distance)
                    DrawClockFill(screenPos[1], screenPos[2], screenChartSize, timePercent, config.pieChartSegments, colorConfig)
                end
                
                if config.showSeconds and distance <= config.maxDistances.text then
                    local timerText = config.showMilliseconds and 
                        string.format("%.1fs", timeLeft) or 
                        string.format("%ds", math.ceil(timeLeft))
                    
                    local scaledFont = GetFont(GetTextSize(distance))
                    draw.SetFont(scaledFont)
                    
                    local width = select(1, draw.GetTextSize(timerText)) or 0
                    
                    COLOR(
                        config.secondsColor.r,
                        config.secondsColor.g,
                        config.secondsColor.b,
                        config.secondsColor.alpha
                    )
                    
                    draw.TextShadow(math.floor(screenPos[1] - width/2), math.floor(screenPos[2] - 15), timerText)
                    draw.SetFont(font)
                end
            end
        end
    end
end)

-- Cleanup
callbacks.Register("Unload", function()
    draw.DeleteTexture(clockTexture)
    draw.DeleteTexture(fillTextureHealth)
    draw.DeleteTexture(fillTextureAmmo)
    fontCache = {}
    nextVisCheck = nil
    visibilityCache = nil
    modelCache = nil
    vecCache = nil
    supplyPositions = {}
end)