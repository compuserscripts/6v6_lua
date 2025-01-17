-- Create a font at the beginning of the script
local font = draw.CreateFont("Arial", 14, 400)

-- Constants 
local MAX_MESSAGES_PER_PLAYER = 3
local MAX_GLOBAL_MESSAGES = 10
local MESSAGE_LIFETIME = 10
local FADE_START_TIME = 7
local BUBBLE_MAX_WIDTH = 250
local BUBBLE_PADDING = 5
local SMOOTHING_FACTOR = 0.1

-- Voice menu data
local VOICE_MENU = {
    [0] = {
        [0] = "MEDIC!",
        [1] = "Thanks!",
        [2] = "Go! Go! Go!",
        [3] = "Move Up!",
        [4] = "Go Left",
        [5] = "Go Right",
        [6] = "Yes",
        [7] = "No"
    },
    [1] = {
        [0] = "Incoming",
        [1] = "Spy!",
        [2] = "Sentry Ahead!",
        [3] = "Teleporter Here",
        [4] = "Dispenser Here",
        [5] = "Sentry Here",
        [6] = "Activate Charge!",
        [7] = "MEDIC: ÜberCharge Ready"
    },
    [2] = {
        [0] = "Help!",
        [1] = "Cheers",
        [2] = "Jeers",
        [3] = "Positive",
        [4] = "Negative",
        [5] = "Nice Shot",
        [6] = "Good Job",
        [7] = "Battle Cry"
    }
}

-- Global state
local chatLog = {}
local globalChatLog = {}
local voiceTimers = {}
local screenW, screenH = 0, 0

-- Local utility functions
local function updateScreenSize()
    screenW, screenH = draw.GetScreenSize()
end

local function calculateOpacity(messageAge)
    if messageAge <= FADE_START_TIME then
        return 255
    end
    local fadeProgress = (messageAge - FADE_START_TIME) / (MESSAGE_LIFETIME - FADE_START_TIME)
    -- Ensure we never return 0, and handle very small values
    local opacity = math.floor(255 * math.max(0.01, 1 - fadeProgress))
    if opacity < 2 then
        return 0  -- If we're below 2, just return 0 instead
    end
    return opacity
end

local function getVoiceCommandSubtitle(iMenu, iItem)
    return VOICE_MENU[iMenu] and VOICE_MENU[iMenu][iItem] or "Unknown Command"
end

local function measureText(text)
    draw.SetFont(font)
    draw.Color(255, 255, 255, 255)
    local width = draw.GetTextSize(text)
    return width
end

local function ensureDrawState()
    draw.SetFont(font)
    draw.Color(255, 255, 255, 255)
end

local function measureTextSize(text)
    draw.SetFont(font)
    draw.Color(255, 255, 255, 255)
    local width, height = draw.GetTextSize(text)
    return width, height
end

local function wrapText(text, maxWidth)
    local words = {}
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end

    local lines = {}
    local currentLine = ""
    
    for _, word in ipairs(words) do
        local testLine = currentLine ~= "" and (currentLine .. " " .. word) or word
        local width = measureTextSize(testLine)
        
        if width > maxWidth then
            if currentLine ~= "" then
                table.insert(lines, currentLine)
                currentLine = word
            else
                table.insert(lines, word)
            end
        else
            currentLine = testLine
        end
    end
    
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    
    return lines
end

local function addChatMessage(message, playerName, entityIndex, isVoice)
    if entityIndex then
        chatLog[entityIndex] = chatLog[entityIndex] or {}
        table.insert(chatLog[entityIndex], 1, {
            message = message,
            time = globals.RealTime(),
            playerName = playerName,
            isVoice = isVoice,
            smoothPos = nil
        })
        
        while #chatLog[entityIndex] > MAX_MESSAGES_PER_PLAYER do
            table.remove(chatLog[entityIndex])
        end
    end

    table.insert(globalChatLog, 1, {
        message = message,
        time = globals.RealTime(),
        playerName = playerName,
        isVoice = isVoice
    })

    while #globalChatLog > MAX_GLOBAL_MESSAGES do
        table.remove(globalChatLog)
    end
end

local function handleChatMessage(msg)
    if msg:GetID() ~= 4 then return end

    local bf = msg:GetBitBuffer()
    if not bf then return end

    local entityIndex = bf:ReadByte()
    bf:ReadByte() -- Skip chat type
    local content = bf:ReadString(256)
    local name = bf:ReadString(256)
    local message = bf:ReadString(256)
    local param3 = bf:ReadString(256)
    local param4 = bf:ReadString(256)

    if content:match("TF_Chat") then
        if name and message and name ~= "" and message ~= "" then
            addChatMessage(message, name, entityIndex, false)
            return
        end
    end

    local playerName, chatText
    local parts = {content, name, message, param3, param4}
    
    for _, part in ipairs(parts) do
        if part and part ~= "" then
            local n, m = part:match("(.+): (.+)")
            if n and m then
                playerName = n:gsub("%*DEAD%*", ""):gsub("%*TEAM%*", ""):gsub("^%s*(.-)%s*$", "%1")
                chatText = m
                break
            end
        end
    end

    if playerName and chatText then
        local modifiedMessage = chatText:sub(2)
        addChatMessage(modifiedMessage, playerName, entityIndex, false)
    end
end

local function handleVoiceMessage(msg)
    if msg:GetID() ~= 25 then return end

    local bf = msg:GetBitBuffer()
    if not bf then return end

    local entityIndex = bf:ReadByte()
    local iMenu = bf:ReadByte()
    local iItem = bf:ReadByte()

    local currentTime = globals.RealTime()
    if voiceTimers[entityIndex] and currentTime - voiceTimers[entityIndex] <= 1 then
        return
    end

    local player = entities.GetByIndex(entityIndex)
    if not player then return end

    local playerName = player:GetName() or "Unknown Player"
    local voiceCommand = getVoiceCommandSubtitle(iMenu, iItem)
    
    addChatMessage(voiceCommand, playerName, entityIndex, true)
    voiceTimers[entityIndex] = currentTime
end

-- Drawing functions
local function drawChatbox()
    local boxWidth = 300
    local boxHeight = 200
    local padding = 10
    local lineHeight = 20
    local currentTime = globals.RealTime()

    -- Draw background
    draw.Color(0, 0, 0, 150)
    draw.FilledRect(
        screenW - boxWidth - padding,
        padding,
        screenW - padding,
        boxHeight + padding
    )

    -- Draw messages
    draw.Color(255, 255, 255, 255)
    for i, entry in ipairs(globalChatLog) do
        if currentTime - entry.time <= MESSAGE_LIFETIME then
            local yPos = padding + (i - 1) * lineHeight
            local text = entry.playerName and 
                        (entry.playerName .. ": " .. entry.message) or 
                        entry.message
            if entry.isVoice then
                text = "(Voice) " .. text
            end
            draw.Text(screenW - boxWidth, yPos, text)
        end
    end
end

local function measureBubbleDimensions(wrappedLines)
    local bubbleWidth, bubbleHeight = 0, 0
    
    draw.SetFont(font)
    draw.Color(255, 255, 255, 255)
    
    for _, line in ipairs(wrappedLines) do
        local lineWidth, lineHeight = draw.GetTextSize(line)
        bubbleWidth = math.max(bubbleWidth, lineWidth)
        bubbleHeight = bubbleHeight + lineHeight
    end
    
    bubbleWidth = math.min(bubbleWidth + (BUBBLE_PADDING * 2), BUBBLE_MAX_WIDTH)
    bubbleHeight = bubbleHeight + (BUBBLE_PADDING * 2) + (#wrappedLines - 1) * 2
    
    return bubbleWidth, bubbleHeight
end

local function drawChatBubble(entry, screenPos, yOffset, opacity)
    draw.SetFont(font)

    local displayText = entry.isVoice and ("(Voice) " .. entry.message) or entry.message
    local wrappedLines = wrapText(displayText, BUBBLE_MAX_WIDTH - (BUBBLE_PADDING * 2))
    
    local bubbleWidth, bubbleHeight = measureBubbleDimensions(wrappedLines)
    
    -- Skip drawing entirely if opacity is 2
    if opacity <= 2 then
        return bubbleHeight + 5  -- Now bubbleHeight is defined
    end
    
    local bubbleX = math.max(bubbleWidth/2, math.min(screenW - bubbleWidth/2, screenPos[1]))
    local bubbleY = math.max(bubbleHeight, math.min(screenH - 20, screenPos[2] - bubbleHeight - 20 - yOffset))

    if not entry.smoothPos then
        entry.smoothPos = {x = bubbleX, y = bubbleY}
    else
        entry.smoothPos.x = entry.smoothPos.x + (bubbleX - entry.smoothPos.x) * SMOOTHING_FACTOR
        entry.smoothPos.y = entry.smoothPos.y + (bubbleY - entry.smoothPos.y) * SMOOTHING_FACTOR
    end

    -- Draw background - explicitly set color before drawing
    draw.Color(0, 0, 0, opacity)
    draw.FilledRect(
        math.floor(entry.smoothPos.x - bubbleWidth/2),
        math.floor(entry.smoothPos.y - bubbleHeight),
        math.floor(entry.smoothPos.x + bubbleWidth/2),
        math.floor(entry.smoothPos.y)
    )

    -- Draw text - reset font and color for each line
    local yTextOffset = 0
    for _, line in ipairs(wrappedLines) do
        -- Set states before each text draw
        draw.SetFont(font)
        draw.Color(255, 255, 255, opacity)
        
        local width, height = draw.GetTextSize(line)
        draw.TextShadow(
            math.floor(entry.smoothPos.x - bubbleWidth/2 + BUBBLE_PADDING),
            math.floor(entry.smoothPos.y - bubbleHeight + BUBBLE_PADDING + yTextOffset),
            line
        )
        yTextOffset = yTextOffset + height + 2
    end

    return bubbleHeight + 5
end

local function drawChatBubbles()
    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    local currentTime = globals.RealTime()

    for _, player in ipairs(players) do
        if not player:IsValid() or player == localPlayer then goto continue end

        local origin = player:GetAbsOrigin()
        if not origin then goto continue end
        
        local headPos = origin + Vector3(0, 0, 75)
        local screenPos = client.WorldToScreen(headPos)
        if not screenPos then goto continue end

        local playerIndex = player:GetIndex()
        local messages = chatLog[playerIndex]
        if not messages then goto continue end
        
        local yOffset = 0
        for _, entry in ipairs(messages) do
            local messageAge = currentTime - entry.time
            if messageAge > MESSAGE_LIFETIME then goto nextMessage end

            local opacity = calculateOpacity(messageAge)
            yOffset = yOffset + drawChatBubble(entry, screenPos, yOffset, opacity)
            
            ::nextMessage::
        end
        
        ::continue::
    end
end

local function onDraw()
    updateScreenSize()
    --drawChatbox()
    drawChatBubbles()
end

local function cleanup()
    callbacks.Unregister("DispatchUserMessage", "ChatDisplayMessage")
    callbacks.Unregister("DispatchUserMessage", "ChatDisplayVoice") 
    callbacks.Unregister("Draw", "ChatDisplayDraw")
    chatLog = nil
    globalChatLog = nil
    voiceTimers = nil
    font = nil
end

callbacks.Register("DispatchUserMessage", "ChatDisplayMessage", handleChatMessage)
callbacks.Register("DispatchUserMessage", "ChatDisplayVoice", handleVoiceMessage)
callbacks.Register("Draw", "ChatDisplayDraw", onDraw)
callbacks.Register("Unload", "ChatDisplayCleanup", cleanup) 
