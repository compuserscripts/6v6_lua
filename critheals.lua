-- Visual Customization
local TEXT_CONFIG = {
    -- Font settings
    FONT_NAME = "Verdana",
    FONT_SIZE = 14,
    FONT_WEIGHT = 800,
    FONT_FLAGS = 0, -- Can use FONTFLAG constants like FONTFLAG_ANTIALIAS
    
    -- Color (RGBA format)
    COLOR = {255, 200, 0, 255}, -- Yellow warning text
    
    -- Position
    POSITION = {
        X_OFFSET = 20,  -- Distance from right edge of screen
        Y_OFFSET = 20   -- Distance from top of screen
    },
    
    -- The actual warning text
    MESSAGE = "Reduced Uber Build Rate!",
    
    -- Screen anchor point
    ANCHOR = "TOP_RIGHT" -- Valid options: "TOP_LEFT", "TOP_RIGHT", "BOTTOM_LEFT", "BOTTOM_RIGHT"
}

-- Triangle Indicator Customization
local TRIANGLE_CONFIG = {
    SIZE = 12,
    VERTICAL_OFFSET = 100,
    OUTLINE_THICKNESS = 2,
    COLORS = {
        FRIEND = {50, 255, 50, 255},   -- Green
        ENEMY = {255, 50, 50, 255},    -- Red
        OUTLINE = {0, 0, 0, 255}       -- Black
    }
}

-- Game Logic Constants
local CRIT_HEAL_TIME = 10.0
local MAX_DISTANCE = 800  -- Maximum distance to show indicator for teammates
local MAX_OVERHEAL_MULTIPLIER = 1.5  -- Maximum overheal is 150% of base max health
local UBER_PENALTY_THRESHOLD = 1.425  -- 142.5% health for uber build penalty
local BUFF_THRESHOLD = 0.9  -- Consider a player "buffed" if they were recently above 90% of max buff
local BUFF_FADE_THRESHOLD = 0.33  -- Consider buff "faded" when below 33% of possible buff amount

-- Feature Toggles
local FEATURES = {
    UBER_BUILD_WARNING = true,
    SHOW_ON_ENEMIES = false
}

-- Create font using config
local warningFont = draw.CreateFont(
    TEXT_CONFIG.FONT_NAME, 
    TEXT_CONFIG.FONT_SIZE, 
    TEXT_CONFIG.FONT_WEIGHT, 
    TEXT_CONFIG.FONT_FLAGS
)

-- Track last damage times and buff times for each player
local lastDamageTimes = {}
local lastBuffTimes = {}

-- Helper function to get screen position based on anchor point
local function getScreenPosition(textWidth, textHeight)
    local screenWidth, screenHeight = draw.GetScreenSize()
    local x, y = 0, 0
    
    if TEXT_CONFIG.ANCHOR == "TOP_RIGHT" then
        x = screenWidth - textWidth - TEXT_CONFIG.POSITION.X_OFFSET
        y = TEXT_CONFIG.POSITION.Y_OFFSET
    elseif TEXT_CONFIG.ANCHOR == "TOP_LEFT" then
        x = TEXT_CONFIG.POSITION.X_OFFSET
        y = TEXT_CONFIG.POSITION.Y_OFFSET
    elseif TEXT_CONFIG.ANCHOR == "BOTTOM_RIGHT" then
        x = screenWidth - textWidth - TEXT_CONFIG.POSITION.X_OFFSET
        y = screenHeight - textHeight - TEXT_CONFIG.POSITION.Y_OFFSET
    elseif TEXT_CONFIG.ANCHOR == "BOTTOM_LEFT" then
        x = TEXT_CONFIG.POSITION.X_OFFSET
        y = screenHeight - textHeight - TEXT_CONFIG.POSITION.Y_OFFSET
    end
    
    return x, y
end

-- Function to draw a filled triangle with black outline
local function drawTriangle(x, y, isEnemy)
    local centerX = x
    local centerY = y
    
    -- Calculate sizes for outer and inner triangles
    local outerSize = TRIANGLE_CONFIG.SIZE
    local innerSize = TRIANGLE_CONFIG.SIZE - TRIANGLE_CONFIG.OUTLINE_THICKNESS
    
    -- Draw the black outline triangle first
    local outlineColor = TRIANGLE_CONFIG.COLORS.OUTLINE
    draw.Color(outlineColor[1], outlineColor[2], outlineColor[3], outlineColor[4])
    
    for i = 0, outerSize do
        local width = (outerSize - i) * 2
        local xPos = centerX - width/2
        local yPos = centerY - outerSize + i
        draw.FilledRect(xPos, yPos, xPos + width, yPos + 1)
    end
    
    -- Draw the colored inner triangle
    local color = isEnemy and TRIANGLE_CONFIG.COLORS.ENEMY or TRIANGLE_CONFIG.COLORS.FRIEND
    draw.Color(color[1], color[2], color[3], color[4])
    
    -- Calculate offset to center the inner triangle
    local offsetY = (outerSize - innerSize) / 2
    
    for i = 0, innerSize do
        local width = (innerSize - i) * 2
        local xPos = centerX - width/2
        local yPos = centerY - outerSize + offsetY + i
        draw.FilledRect(xPos, yPos, xPos + width, yPos + 1)
    end
end

local function IsVisible(entity, localPlayer)
    if not entity or not localPlayer then return false end
    
    local eyePos = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
    local targetPos = entity:GetAbsOrigin()
    
    local isTeammate = entity:GetTeamNumber() == localPlayer:GetTeamNumber()
    local mask = isTeammate and MASK_SHOT_HULL or MASK_VISIBLE
    local trace = engine.TraceLine(eyePos, targetPos, mask)
    
    return isTeammate and trace.fraction > 0.97 or trace.entity == entity
end

-- Update damage times when players take damage
callbacks.Register("FireGameEvent", "CritHealDamageTracker", function(event)
    if event:GetName() ~= "player_hurt" then return end
    
    local victim = entities.GetByUserID(event:GetInt("userid"))
    if victim then
        lastDamageTimes[victim:GetIndex()] = globals.CurTime()
    end
end)

local function onDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or not localPlayer:IsAlive() then return end
    
    -- Only run for medics
    if localPlayer:GetPropInt("m_iClass") ~= 5 then return end -- 5 is TF2_Medic
    
    -- Handle uber build warning
    if FEATURES.UBER_BUILD_WARNING then
        local activeWeapon = localPlayer:GetPropEntity("m_hActiveWeapon")
        if activeWeapon then
            local healTarget = localPlayer:GetPropEntity("m_Shared", "m_hHealingTarget")
            if not healTarget and activeWeapon:IsMedigun() then
                healTarget = activeWeapon:GetPropEntity("m_hHealingTarget")
            end

            if healTarget and healTarget:IsAlive() then
                local health = healTarget:GetPropInt("m_iHealth")
                local baseMaxHealth = healTarget:GetMaxHealth()
                
                if health and baseMaxHealth then
                    local healthRatio = health / baseMaxHealth
                    
                    if healthRatio >= UBER_PENALTY_THRESHOLD then
                        draw.SetFont(warningFont)
                        local color = TEXT_CONFIG.COLOR
                        draw.Color(color[1], color[2], color[3], color[4])
                        
                        local textW, textH = draw.GetTextSize(TEXT_CONFIG.MESSAGE)
                        local x, y = getScreenPosition(textW, textH)
                        draw.Text(x, y, TEXT_CONFIG.MESSAGE)
                    end
                end
            end
        end
    end
    
    local localPos = localPlayer:GetAbsOrigin()
    local currentTime = globals.CurTime()
    
    local players = entities.FindByClass("CTFPlayer")
    for _, player in pairs(players) do
        if player:IsAlive() and 
           not player:IsDormant() and 
           player ~= localPlayer then
            
            local isEnemy = player:GetTeamNumber() ~= localPlayer:GetTeamNumber()
            
            -- Skip enemies if feature is disabled
            if isEnemy and not FEATURES.SHOW_ON_ENEMIES then goto continue end
            
            local playerPos = player:GetAbsOrigin()
            
            -- Distance check only for teammates
            if not isEnemy then
                local dx = playerPos.x - localPos.x
                local dy = playerPos.y - localPos.y
                local dz = playerPos.z - localPos.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist > MAX_DISTANCE then goto continue end
            end
            
            -- Visibility check
            if not IsVisible(player, localPlayer) then goto continue end
            
            -- Get player's health info using GetPropInt to avoid nil values
            local health = player:GetPropInt("m_iHealth")
            local baseMaxHealth = player:GetMaxHealth()
            
            -- Skip if we couldn't get valid health values
            if not health or not baseMaxHealth then goto continue end
            
            local maxBuffedHealth = math.floor(baseMaxHealth * MAX_OVERHEAL_MULTIPLIER)
            local bufferAmount = maxBuffedHealth - baseMaxHealth
            local currentBuffAmount = health - baseMaxHealth
            
            -- Track when player was last well-buffed
            local playerIndex = player:GetIndex()
            if currentBuffAmount > (bufferAmount * BUFF_THRESHOLD) then
                lastBuffTimes[playerIndex] = currentTime
            end
            
            -- Determine if player should be considered still buffed
            local wasRecentlyBuffed = false
            local lastBuffTime = lastBuffTimes[playerIndex] or 0
            if lastBuffTime > 0 and currentBuffAmount > (bufferAmount * BUFF_FADE_THRESHOLD) then
                wasRecentlyBuffed = true
            end
            
            -- Only show indicator if:
            -- 1. Player hasn't taken damage in last 10 seconds
            -- 2. Player isn't at max buffed health
            -- 3. Player wasn't recently well-buffed
            local lastDamageTime = lastDamageTimes[playerIndex] or 0
            local timeSinceLastDamage = currentTime - lastDamageTime
            
            if timeSinceLastDamage >= CRIT_HEAL_TIME and 
               health < maxBuffedHealth and 
               not wasRecentlyBuffed then
                -- Convert player position to screen coordinates and add vertical offset
                local headPos = Vector3(playerPos.x, playerPos.y, playerPos.z + TRIANGLE_CONFIG.VERTICAL_OFFSET)
                local screenPos = client.WorldToScreen(headPos)
                if screenPos then
                    drawTriangle(screenPos[1], screenPos[2], isEnemy)
                end
            end
        end
        ::continue::
    end
end

callbacks.Register("Draw", "crithealsindicator", onDraw)

-- Cleanup on unload
callbacks.Register("Unload", function()
    lastDamageTimes = {}
    lastBuffTimes = {}
end)
