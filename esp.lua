local ALPHA = 70
local BAR_HEIGHT = 10
local OVERHEAL_COLOR = {71, 166, 255}
local MAX_DISTANCE_SQR = 3500 * 3500
local SHOW_TEAMMATE_HEALTH = true -- Toggle for showing teammate health bars when playing medic

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

local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end
    local source = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = entity:GetAbsOrigin()
    local trace = engine.TraceLine(source, targetPos, MASK_VISIBLE)
    return trace.entity == entity
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

callbacks.Register("Draw", "HealthBarESP", function()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    local localPos = localPlayer:GetAbsOrigin()
    if not localPos then return end

    local isLocalPlayerMedic = IsMedic(localPlayer)
    local showTeammates = SHOW_TEAMMATE_HEALTH and isLocalPlayerMedic

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

            -- Only do visibility check when showing enemy health bars
            local eyePos = localPos + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
            if not showTeammates then
                local trace = engine.TraceLine(eyePos, playerPos, MASK_VISIBLE)
                if trace.entity ~= player then goto continue end
            end

            local x, y, x2, y2 = Get2DBoundingBox(player)
            if x then
                local w = x2 - x
                local health = player:GetHealth()
                local maxHealth = player:GetMaxHealth()
                local healthBarSize = math.floor(w * (math.min(health, maxHealth) / maxHealth))
                local overhealSize = health > maxHealth and math.floor(w * ((health - maxHealth) / maxHealth)) or 0

                x, y, x2, y2 = math.floor(x), math.floor(y), math.ceil(x2), math.ceil(y2)
                healthBarSize = math.floor(healthBarSize)
                overhealSize = math.floor(overhealSize)

                draw.Color(0, 0, 0, ALPHA)
                draw.FilledRect(x, y2 + 2, x2, y2 + 2 + BAR_HEIGHT)

                draw.Color(GetHealthBarColor(math.min(health, maxHealth), maxHealth))
                draw.FilledRect(x + 1, y2 + 3, x + healthBarSize - 1, y2 + 1 + BAR_HEIGHT)

                if overhealSize > 0 then
                    draw.Color(GetHealthBarColor(health, maxHealth))
                    draw.FilledRect(x + healthBarSize, y2 + 3, x + healthBarSize + overhealSize - 1, y2 + 1 + BAR_HEIGHT)
                end
            end
        end
        ::continue::
    end
end)
