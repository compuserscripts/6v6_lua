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
    local eyePos = localPos + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")

    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if not player:IsAlive() or player:IsDormant() or player == localPlayer then goto continue end
        if player:InCond(4) or player:InCond(3) then goto continue end -- Skip if cloaked or disguised
        
        local isFriendly = player:GetTeamNumber() == localPlayer:GetTeamNumber()
        if not (showTeammates and isFriendly or not showTeammates and not isFriendly) then goto continue end

        local playerPos = player:GetAbsOrigin()
        if not playerPos then goto continue end

        local dx = playerPos.x - localPos.x
        local dy = playerPos.y - localPos.y
        local dz = playerPos.z - localPos.z
        local distSqr = dx * dx + dy * dy + dz * dz
        if distSqr > MAX_DISTANCE_SQR then goto continue end

        -- Visibility check
        local mask = isFriendly and MASK_SHOT_HULL or MASK_VISIBLE
        local trace = engine.TraceLine(eyePos, playerPos, mask)
        if isFriendly then
            if trace.fraction <= 0.97 then goto continue end
        else
            if trace.entity ~= player then goto continue end
        end

        local health = player:GetHealth()
        local maxHealth = player:GetMaxHealth()

        if config.fixedHealthBars then
            local basePos = client.WorldToScreen(playerPos)
            if basePos then
                DrawHealthBar(basePos[1] - BAR_WIDTH/2, basePos[2] + 30, BAR_WIDTH, health, maxHealth)
            end
        else
            local x, y, x2, y2 = Get2DBoundingBox(player)
            if x then
                DrawHealthBar(x, y2 + 2, x2 - x, health, maxHealth)
            end
        end

        ::continue::
    end
end)
