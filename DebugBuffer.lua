-- Custom bit manipulation functions
local bit = {}

function bit.band(a, b) local result = 0 local bitval = 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then result = result + bitval end bitval = bitval * 2 a = math.floor(a/2) b = math.floor(b/2) end return result end
function bit.bor(a, b) local result = 0 local bitval = 1 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then result = result + bitval end bitval = bitval * 2 a = math.floor(a/2) b = math.floor(b/2) end return result end
function bit.lshift(a, b) return a * (2 ^ b) end
function bit.rshift(a, b) return math.floor(a / (2 ^ b)) end

-- Message type definitions
local MESSAGE_DEFS = {
    [0] = {name = "Geiger", size = 1},
    [1] = {name = "Train", size = 1},
    [2] = {name = "HudText", size = -1},
    [3] = {name = "SayText", size = -1},
    [4] = {name = "SayText2", size = -1},
    [5] = {name = "TextMsg", size = -1},
    [6] = {name = "ResetHUD", size = 1},
    [7] = {name = "GameTitle", size = 0},
    [8] = {name = "ItemPickup", size = -1},
    [9] = {name = "ShowMenu", size = -1},
    [10] = {name = "Shake", size = 13},
    [11] = {name = "Fade", size = 10},
    [12] = {name = "VGUIMenu", size = -1},
    [13] = {name = "Rumble", size = 3},
    [14] = {name = "CloseCaption", size = -1},
    [15] = {name = "SendAudio", size = -1},
    [16] = {name = "VoiceMask", size = 17},
    [17] = {name = "RequestState", size = 0},
    [18] = {name = "Damage", size = -1},
    [19] = {name = "HintText", size = -1},
    [20] = {name = "KeyHintText", size = -1},
    [21] = {name = "HudMsg", size = -1},
    [22] = {name = "AmmoDenied", size = 2},
    [23] = {name = "AchievementEvent", size = -1},
    [24] = {name = "UpdateRadar", size = -1},
    [25] = {name = "VoiceSubtitle", size = 3},
    [26] = {name = "HudNotify", size = 2},
    [27] = {name = "HudNotifyCustom", size = -1},
    [28] = {name = "PlayerStatsUpdate", size = -1},
    [29] = {name = "MapStatsUpdate", size = -1},
    [30] = {name = "PlayerIgnited", size = 3},
    [31] = {name = "PlayerIgnitedInv", size = 3},
    [32] = {name = "HudArenaNotify", size = 2},
    [33] = {name = "UpdateAchievement", size = -1},
    [34] = {name = "TrainingMsg", size = -1},
    [35] = {name = "TrainingObjective", size = -1},
    [36] = {name = "DamageDodged", size = -1},
    [37] = {name = "PlayerJarated", size = 2},
    [38] = {name = "PlayerExtinguished", size = 2},
    [39] = {name = "PlayerJaratedFade", size = 2},
    [40] = {name = "PlayerShieldBlocked", size = 2},
    [41] = {name = "BreakModel", size = -1},
    [42] = {name = "CheapBreakModel", size = -1},
    [43] = {name = "BreakModel_Pumpkin", size = -1},
    [44] = {name = "BreakModelRocketDud", size = -1},
    [45] = {name = "CallVoteFailed", size = -1},
    [46] = {name = "VoteStart", size = -1},
    [47] = {name = "VotePass", size = -1},
    [48] = {name = "VoteFailed", size = 2},
    [49] = {name = "VoteSetup", size = -1},
    [50] = {name = "PlayerBonusPoints", size = 3},
    [51] = {name = "RDTeamPointsChanged", size = 4},
    [52] = {name = "SpawnFlyingBird", size = -1},
    [53] = {name = "PlayerGodRayEffect", size = -1},
    [54] = {name = "PlayerTeleportHomeEffect", size = -1},
    [55] = {name = "MVMStatsReset", size = -1},
    [56] = {name = "MVMPlayerEvent", size = -1},
    [57] = {name = "MVMResetPlayerStats", size = -1},
    [58] = {name = "MVMWaveFailed", size = 0},
    [59] = {name = "MVMAnnouncement", size = 2},
    [60] = {name = "MVMPlayerUpgradedEvent", size = 9},
    [61] = {name = "MVMVictory", size = 2},
    [62] = {name = "MVMWaveChange", size = 15},
    [63] = {name = "MVMLocalPlayerUpgradesClear", size = 1},
    [64] = {name = "MVMLocalPlayerUpgradesValue", size = 6},
    [65] = {name = "MVMResetPlayerWaveSpendingStats", size = 1},
    [66] = {name = "MVMLocalPlayerWaveSpendingValue", size = 12},
    [67] = {name = "MVMResetPlayerUpgradeSpending", size = -1},
    [68] = {name = "MVMServerKickTimeUpdate", size = 1},
    [69] = {name = "PlayerLoadoutUpdated", size = -1},
    [70] = {name = "PlayerTauntSoundLoopStart", size = -1},
    [71] = {name = "PlayerTauntSoundLoopEnd", size = -1},
    [72] = {name = "ForcePlayerViewAngles", size = -1},
    [73] = {name = "BonusDucks", size = 2},
    [74] = {name = "EOTLDuckEvent", size = 7},
    [75] = {name = "PlayerPickupWeapon", size = -1},
    [76] = {name = "QuestObjectiveCompleted", size = 14},
    [77] = {name = "SPHapWeapEvent", size = 4},
    [78] = {name = "HapDmg", size = -1},
    [79] = {name = "HapPunch", size = -1},
    [80] = {name = "HapSetDrag", size = -1},
    [81] = {name = "HapSetConst", size = -1},
    [82] = {name = "HapMeleeContact", size = 0}
}

-- Enhanced BitBuffer implementation
local function createBuffer()
    local buffer = {
        data = {},
        position = 1,
        bitPosition = 0
    }
    
    -- Write functions
    function buffer:writeByte(byte)
        -- Convert negative bytes to unsigned
        if byte < 0 then
            byte = byte + 256
        end
        table.insert(self.data, byte)
    end
    
    -- Read functions
    function buffer:readBit()
        if self.position > #self.data then return 0 end
        
        local byte = self.data[self.position]
        local bit = bit.band(bit.rshift(byte, 7 - self.bitPosition), 1)
        
        self.bitPosition = self.bitPosition + 1
        if self.bitPosition == 8 then
            self.bitPosition = 0
            self.position = self.position + 1
        end
        
        return bit
    end
    
    function buffer:readByte()
        if self.position > #self.data then return nil end
        
        if self.bitPosition == 0 then
            local byte = self.data[self.position]
            self.position = self.position + 1
            return byte
        else
            -- Handle unaligned reads
            local firstPart = bit.lshift(bit.band(self.data[self.position], bit.lshift(1, 8 - self.bitPosition) - 1), self.bitPosition)
            self.position = self.position + 1
            
            if self.position > #self.data then return firstPart end
            
            local secondPart = bit.rshift(self.data[self.position], 8 - self.bitPosition)
            return bit.bor(firstPart, secondPart)
        end
    end
    
    function buffer:readUInt(width)
        local value = 0
        for i = 1, width do
            value = bit.bor(bit.lshift(value, 1), self:readBit())
        end
        return value
    end
    
    function buffer:readInt(width)
        local value = self:readUInt(width)
        local sign = bit.band(value, bit.lshift(1, width - 1))
        if sign ~= 0 then
            value = value - bit.lshift(1, width)
        end
        return value
    end
    
    function buffer:readVarInt32()
        local result = 0
        local shift = 0
        while true do
            local b = self:readByte()
            if not b then break end
            result = bit.bor(result, bit.lshift(bit.band(b, 0x7F), shift))
            if bit.band(b, 0x80) == 0 then
                return result
            end
            shift = shift + 7
        end
        return result
    end

    -- UTF-8 aware string reading
    function buffer:readUTF8String()
        local result = {}
        local savedPos = self.position
        
        while self.position <= #self.data do
            local byte = self:readByte()
            if not byte or byte == 0 then break end
            
            -- UTF-8 sequence detection
            if byte >= 0xF0 then -- 4 bytes
                local b2, b3, b4 = self:readByte(), self:readByte(), self:readByte()
                if b2 and b3 and b4 then
                    local char = string.char(byte, b2, b3, b4)
                    table.insert(result, char)
                end
            elseif byte >= 0xE0 then -- 3 bytes
                local b2, b3 = self:readByte(), self:readByte()
                if b2 and b3 then
                    local char = string.char(byte, b2, b3)
                    table.insert(result, char)
                end
            elseif byte >= 0xC0 then -- 2 bytes
                local b2 = self:readByte()
                if b2 then
                    local char = string.char(byte, b2)
                    table.insert(result, char)
                end
            elseif byte >= 0x20 and byte <= 0x7E then -- ASCII printable
                table.insert(result, string.char(byte))
            end
        end
        
        -- Reset position if no valid string found
        if #result == 0 then
            self.position = savedPos
        end
        
        return table.concat(result)
    end

    function buffer:findStrings(minLength)
        local strings = {}
        local savedPosition = self.position
        self:reset()

        -- Track complete message sections
        local sections = {}
        local currentSection = {}
        local inSection = false
        
        while self.position <= #self.data do
            local byte = self:readByte()
            if not byte then break end
            
            -- Start or continue section on printable chars
            if (byte >= 0x20 and byte <= 0x7E) or byte >= 0x80 then
                if not inSection then
                    currentSection = {
                        start = self.position - 1,
                        bytes = {}
                    }
                    inSection = true
                end
                table.insert(currentSection.bytes, byte)
            else
                -- End section on non-printable chars
                if inSection and #currentSection.bytes >= (minLength or 3) then
                    currentSection.endPos = self.position - 1
                    -- Convert bytes to string safely
            local chars = {}
            for _, byte in ipairs(currentSection.bytes) do
                table.insert(chars, string.char(byte))
            end
            currentSection.str = table.concat(chars)
                    table.insert(sections, currentSection)
                end
                inSection = false
            end
        end
        
        -- Handle last section
        if inSection and #currentSection.bytes >= (minLength or 3) then
            currentSection.endPos = self.position - 1
            -- Convert bytes to string safely
            local chars = {}
            for _, byte in ipairs(currentSection.bytes) do
                table.insert(chars, string.char(byte))
            end
            currentSection.str = table.concat(chars)
            table.insert(sections, currentSection)
        end
        
        -- Filter out subsequences
        for i = 1, #sections do
            local isSubsequence = false
            for j = 1, #sections do
                if i ~= j and 
                   sections[i].start >= sections[j].start and 
                   sections[i].endPos <= sections[j].endPos then
                    isSubsequence = true
                    break
                end
            end
            if not isSubsequence then
                table.insert(strings, sections[i].str)
            end
        end
        
        self.position = savedPosition
        return strings
    end

    -- Format byte for display
    function buffer:formatByte(byte)
        if not byte then return "nil", "." end
        
        local char = "."
        -- Only show ASCII printable chars directly
        if byte >= 0x20 and byte <= 0x7E then
            char = string.char(byte)
        -- For UTF-8 lead bytes, show •
        -- For UTF-8 continuation bytes, show ·
        elseif byte >= 0xF0 then  -- 4-byte lead
            char = "•4"
        elseif byte >= 0xE0 then  -- 3-byte lead
            char = "•3"
        elseif byte >= 0xC0 then  -- 2-byte lead
            char = "•2"
        elseif byte >= 0x80 then  -- continuation
            char = "·"
        end
        
        return string.format("0x%02X", byte), char
    end

    -- Get binary representation of a byte
    function buffer:getBitPattern(byte)
        if not byte then return "00000000" end
        local pattern = ""
        for i = 7, 0, -1 do
            pattern = pattern .. (bit.band(byte, bit.lshift(1, i)) ~= 0 and "1" or "0")
        end
        return pattern
    end

    function buffer:reset()
        self.position = 1
        self.bitPosition = 0
    end
    
    function buffer:getSize()
        return #self.data
    end

    return buffer
end

local function analyzeBuffer(buffer, msgType)
    local output = {}
    local msgDef = MESSAGE_DEFS[msgType]
    
    -- Print header
    print("\n=== New Message Received ===")
    print(string.format("Message Type: %d (%s)", msgType, msgDef and msgDef.name or "Unknown"))
    print(string.format("Expected Size: %s", msgDef and (msgDef.size == -1 and "Variable" or msgDef.size) or "Unknown"))
    
    -- Analyze byte types in the message
    local byteTypes = {
        control = 0,
        ascii = 0,
        utf8_lead = 0,
        utf8_cont = 0
    }
    
    buffer:reset()
    local byte = buffer:readByte()
    while byte do
        if byte < 0x20 then
            byteTypes.control = byteTypes.control + 1
        elseif byte <= 0x7E then
            byteTypes.ascii = byteTypes.ascii + 1
        elseif byte >= 0xC0 and byte <= 0xF7 then
            byteTypes.utf8_lead = byteTypes.utf8_lead + 1
        elseif byte >= 0x80 then
            byteTypes.utf8_cont = byteTypes.utf8_cont + 1
        end
        byte = buffer:readByte()
    end
    
    -- Print encoding analysis if we found any non-ASCII bytes
    if byteTypes.utf8_lead > 0 or byteTypes.utf8_cont > 0 then
        print("\nByte Encoding Analysis:")
        print(string.format("- ASCII text (0x20-0x7E): %d bytes", byteTypes.ascii))
        print(string.format("- UTF-8 sequences: %d sequences (%d lead + %d continuation bytes)", 
            byteTypes.utf8_lead, byteTypes.utf8_lead, byteTypes.utf8_cont))
        print(string.format("- Control bytes: %d", byteTypes.control))
    end
    
    -- Find strings
    local strings = buffer:findStrings(3)
    if #strings > 0 then
        print("\nStrings found:")
        for i, str in ipairs(strings) do
            print(string.format("%2d: \"%s\"", i, str))
        end
    end
    
    -- Check for VarInt32
    buffer:reset()
    if msgDef and msgDef.size == -1 then
        local varInt = buffer:readVarInt32()
        if varInt then
            print(string.format("\nLeading VarInt32: %d", varInt))
        end
    end

    -- Print byte analysis
    print("\nByte analysis:")
    buffer:reset()
    local byteCount = 0
    
    while true do
        local byte = buffer:readByte()
        if not byte then break end
        byteCount = byteCount + 1
        
        local hexByte, char = buffer:formatByte(byte)
        local prefix = string.format("Byte %3d: %s  Bits: %s  Char: %s", 
            byteCount,
            hexByte,
            buffer:getBitPattern(byte),
            char
        )
        
        -- Color based on byte type
        if byte < 0x20 then
            printc(255, 0, 255, 255, prefix)  -- Control bytes in purple
        elseif byte <= 0x7E then
            printc(0, 255, 0, 255, prefix)    -- ASCII in green
        elseif byte >= 0xC0 and byte <= 0xF7 then
            printc(255, 0, 0, 255, prefix)    -- UTF-8 lead bytes in red
        elseif byte >= 0x80 then
            printc(0, 0, 255, 255, prefix)    -- UTF-8 continuation bytes in blue
        else
            print(prefix)                      -- Default white
        end
    end
    
    -- Print hex dump with color legend
    print("\nHex dump with color coding:")
    printc(255, 0, 255, 255, "- Purple: Control bytes (0x00-0x1F)")
    printc(0, 255, 0, 255, "- Green: ASCII text (0x20-0x7E)")
    printc(255, 0, 0, 255, "- Red: UTF-8 lead bytes")
    printc(0, 0, 255, 255, "- Blue: UTF-8 continuation bytes")
    
    print("\nHex dump:")
    buffer:reset()
    local hexLine = {}
    byteCount = 0
    
    while true do
        local byte = buffer:readByte()
        if not byte then break end
        byteCount = byteCount + 1
        
        if byte < 0x20 then
            printc(255, 0, 255, 255, string.format("0x%02X ", byte))
        elseif byte <= 0x7E then
            printc(0, 255, 0, 255, string.format("0x%02X ", byte))
        elseif byte >= 0xC0 and byte <= 0xF7 then
            printc(255, 0, 0, 255, string.format("0x%02X ", byte))
        elseif byte >= 0x80 then
            printc(0, 0, 255, 255, string.format("0x%02X ", byte))
        else
            print(string.format("0x%02X ", byte))
        end
        
        if byteCount % 16 == 0 then
            print("")  -- New line every 16 bytes
        end
    end
    print("") -- Final newline
end

-- Debug hook for messages
local function debugMessageHook(msg)
    print("\n=== New Message Received ===")
    
    local status, err = pcall(function()
        local bitbuf = msg:GetBitBuffer()
        if not bitbuf then 
            print("Error: No bit buffer in message")
            return
        end
        
        -- Get message type from the message itself
        local msgType = msg:GetID()
        
        -- Create our buffer
        local buffer = createBuffer()
        local byteLength = bitbuf:GetDataBytesLength()
        
        -- Copy bytes from message buffer
        for i = 1, byteLength do
            local byte = bitbuf:ReadByte()
            buffer:writeByte(byte)
        end
        
        -- Analyze and print the buffer contents
        print(analyzeBuffer(buffer, msgType))
    end)
    
    if not status then
        print("Error analyzing message: " .. tostring(err))
    end
end

-- Register the debug hook
callbacks.Register("DispatchUserMessage", "messageAnalyzer", debugMessageHook)

-- Cleanup function
local function cleanup()
    callbacks.Unregister("DispatchUserMessage", "messageAnalyzer")
    print("Message Analyzer script unloaded")
end

-- Register cleanup on script unload
callbacks.Register("Unload", "messageAnalyzerCleanup", cleanup)

print("Lmaobox-Compatible BitBuffer Debug Script loaded. Check console for detailed message analysis.")
