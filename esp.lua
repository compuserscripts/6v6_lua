local ALPHA = 70
local BAR_HEIGHT = 10
local BAR_WIDTH = 90  -- Fixed width for the non-wobble mode
local OVERHEAL_COLOR = {71, 166, 255}
local MAX_DISTANCE_SQR = 3500 * 3500
local MEDIC_MODE = true -- Toggle for showing teammate health bars when playing medic

-- Configuration
local config = {
    fixedHealthBars = true -- When true, health bars won't wobble with player models
}

-- Visibility check caching
local nextVisCheck = {}
local visibilityCache = {}
local vecCache = {
    eyePos = Vector3(0, 0, 0),
    viewOffset = Vector3(0, 0, 0)
}

-- Optimized visibility check
local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end
    
    local pos = entity:GetAbsOrigin()
    local id = math.floor(pos.x) .. math.floor(pos.y) .. math.floor(pos.z)
    local curTick = globals.TickCount()
    
    if nextVisCheck[id] and curTick < nextVisCheck[id] then
        return visibilityCache[id]
    end
    
    vecCache.viewOffset = localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    vecCache.eyePos = localPlayer:GetAbsOrigin()
    vecCache.eyePos.x = vecCache.eyePos.x + vecCache.viewOffset.x
    vecCache.eyePos.y = vecCache.eyePos.y + vecCache.viewOffset.y 
    vecCache.eyePos.z = vecCache.eyePos.z + vecCache.viewOffset.z
    
    local isTeammate = entity:GetTeamNumber() == localPlayer:GetTeamNumber()
    local mask = isTeammate and MASK_SHOT_HULL or MASK_VISIBLE
    local trace = engine.TraceLine(vecCache.eyePos, pos, mask)
    
    visibilityCache[id] = isTeammate and trace.fraction > 0.97 or trace.entity == entity
    nextVisCheck[id] = curTick + 3
    
    return visibilityCache[id]
end

local function Get2DBoundingBox(entity)
    local hitbox = entity:HitboxSurroundingBox()
    local corners = {
        Vector3(hitbox[1].x, hitbox[1].y, hitbox[1].z),
        Vector3(hitbox[1].x, hitbox[2].y, hitbox[1].z),
        Vector3(hitbox[2].x, hitbox[2].y, hitbox[1].z),
        Vector3(hitbox[2].x, hitbox[1].y, hitbox[1].z),
        Vector3(hitbox[2].x, hitbox[2].y, hitbox[2].z),
        Vector3(hitbox[1].x, hitbox[2].y, hitbox[2].z),
        Vector3(hitbox[1].x, hitbox[1].y, hitbox[2].z),
        Vector3(hitbox[2].x, hitbox[1].y, hitbox[2].z)
    }
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, corner in pairs(corners) do
        local onScreen = client.WorldToScreen(corner)
        if onScreen then
            minX, minY = math.min(minX, onScreen[1]), math.min(minY, onScreen[2])
            maxX, maxY = math.max(maxX, onScreen[1]), math.max(maxY, onScreen[2])
        else
            return nil
        end
    end
    return minX, minY, maxX, maxY
end

local function GetHealthBarColor(health, maxHealth)
    local ratio = health / maxHealth
    local invertedAlpha = math.floor(255 * (1 - ratio))
    invertedAlpha = math.max(invertedAlpha, ALPHA)
    
    if health > maxHealth then
        return OVERHEAL_COLOR[1], OVERHEAL_COLOR[2], OVERHEAL_COLOR[3], invertedAlpha
    else
        return math.floor(255 * (1 - ratio)), math.floor(255 * ratio), 0, invertedAlpha
    end
end

local function IsMedic(player)
    return player:GetPropInt("m_iClass") == 5
end

local function DrawHealthBar(x, y, width, health, maxHealth)
    local healthBarSize = math.floor(width * (math.min(health, maxHealth) / maxHealth))
    local overhealSize = health > maxHealth and math.floor(width * ((health - maxHealth) / maxHealth)) or 0

    healthBarSize = math.floor(healthBarSize)
    overhealSize = math.floor(overhealSize)

    -- Background
    draw.Color(0, 0, 0, ALPHA)
    draw.FilledRect(x, y, x + width, y + BAR_HEIGHT)

    -- Main health bar
    draw.Color(GetHealthBarColor(math.min(health, maxHealth), maxHealth))
    draw.FilledRect(x + 1, y + 1, x + healthBarSize - 1, y + BAR_HEIGHT - 1)

    -- Overheal bar
    if overhealSize > 0 then
        draw.Color(GetHealthBarColor(health, maxHealth))
        draw.FilledRect(x + healthBarSize, y + 1, x + healthBarSize + overhealSize - 1, y + BAR_HEIGHT - 1)
    end
end

callbacks.Register("Draw", "HealthBarESP", function()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    local localPos = localPlayer:GetAbsOrigin()
    if not localPos then return end

    local isLocalPlayerMedic = IsMedic(localPlayer)
    local showTeammates = MEDIC_MODE and isLocalPlayerMedic

    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player:IsAlive() and not player:IsDormant() and player ~= localPlayer and
           (showTeammates and player:GetTeamNumber() == localPlayer:GetTeamNumber() or
           not showTeammates and player:GetTeamNumber() ~= localPlayer:GetTeamNumber()) and 
           not player:InCond(4) then

            local playerPos = player:GetAbsOrigin()
            if not playerPos then goto continue end

            local dx = playerPos.x - localPos.x
            local dy = playerPos.y - localPos.y
            local dz = playerPos.z - localPos.z
            local distSqr = dx * dx + dy * dy + dz * dz
            if distSqr > MAX_DISTANCE_SQR then goto continue end

            if not IsVisible(player, localPlayer) then goto continue end

            local health = player:GetHealth()
            local maxHealth = player:GetMaxHealth()

            if config.fixedHealthBars then
                -- Simple fixed position like your example
                local basePos = client.WorldToScreen(playerPos)
                if basePos then
                    DrawHealthBar(basePos[1] - BAR_WIDTH/2, basePos[2] + 30, BAR_WIDTH, health, maxHealth)
                end
            else
                -- Wobble mode using bounding box
                local x, y, x2, y2 = Get2DBoundingBox(player)
                if x then
                    DrawHealthBar(x, y2 + 2, x2 - x, health, maxHealth)
                end
            end
        end
        ::continue::
    end
end)

-- Cleanup on script unload
callbacks.Register("Unload", function()
    nextVisCheck = {}
    visibilityCache = {}
    vecCache = {
        eyePos = Vector3(0, 0, 0),
        viewOffset = Vector3(0, 0, 0)
    }
end)
