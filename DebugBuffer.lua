-- Custom bit manipulation functions
local bit = {}

function bit.band(a, b) local result = 0 local bitval = 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then result = result + bitval end bitval = bitval * 2 a = math.floor(a/2) b = math.floor(b/2) end return result end
function bit.bor(a, b) local result = 0 local bitval = 1 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then result = result + bitval end bitval = bitval * 2 a = math.floor(a/2) b = math.floor(b/2) end return result end
function bit.lshift(a, b) return a * (2 ^ b) end
function bit.rshift(a, b) return math.floor(a / (2 ^ b)) end

-- Enhanced BitBuffer implementation
local function createBuffer()
    local buffer = {
        data = {},
        position = 1,
        bitPosition = 0
    }
    
    -- Write functions
    function buffer:writeByte(byte)
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
            result = bit.bor(result, bit.lshift(bit.band(b, 0x7F), shift))
            if bit.band(b, 0x80) == 0 then
                return result
            end
            shift = shift + 7
        end
    end
    
    function buffer:readFloat()
        local bytes = {self:readByte(), self:readByte(), self:readByte(), self:readByte()}
        local int = bytes[1] + bytes[2] * 256 + bytes[3] * 65536 + bytes[4] * 16777216
        local sign = bit.band(int, 0x80000000) ~= 0
        local exp = bit.band(bit.rshift(int, 23), 0xFF)
        local frac = bit.band(int, 0x7FFFFF)
        
        if exp == 0 and frac == 0 then return 0 end
        if exp == 0xFF then
            if frac == 0 then return sign and -math.huge or math.huge end
            return 0/0  -- NaN
        end
        
        local value = 1 + frac / 0x800000
        value = value * (2 ^ (exp - 127))
        if sign then value = -value end
        return value
    end
    
    -- Utility functions
    function buffer:reset()
        self.position = 1
        self.bitPosition = 0
    end
    
    function buffer:getSize()
        return #self.data
    end
    
    -- Get binary representation of a byte
    function buffer:getBitPattern(byte)
        local pattern = ""
        for i = 7, 0, -1 do
            pattern = pattern .. (bit.band(byte, bit.lshift(1, i)) ~= 0 and "1" or "0")
        end
        return pattern
    end

    return buffer
end

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

-- Enhanced analysis function
local function analyzeBuffer(buffer, msgType)
    local output = {}
    local msgDef = MESSAGE_DEFS[msgType]
    
    -- Basic message info
    if not msgDef then
        table.insert(output, "Unknown Message Type: " .. msgType)
        return table.concat(output, "\n")
    end
    
    table.insert(output, string.format("Message Type: %d (%s)", msgType, msgDef.name))
    table.insert(output, string.format("Expected Size: %s", msgDef.size == -1 and "Variable" or msgDef.size))
    
    -- Analyze all bytes
    local totalBytes = {}
    local byteStrings = {}
    local strings = {}
    local currentString = {}
    
    -- Read all bytes
    buffer:reset()
    local byteCount = 0
    local byte = buffer:readByte()
    
    while byte do
        byteCount = byteCount + 1
        
        -- Store raw byte
        table.insert(totalBytes, byte)
        
        -- Format byte info with binary pattern
        table.insert(byteStrings, string.format("Byte %3d: 0x%02X  Bits: %s  Char: %s", 
            byteCount,
            byte,
            buffer:getBitPattern(byte),
            byte >= 32 and byte <= 126 and string.char(byte) or "."
        ))
        
        -- Collect printable characters
        if byte >= 32 and byte <= 126 then
            table.insert(currentString, string.char(byte))
        elseif #currentString > 0 then
            if #currentString >= 3 then
                table.insert(strings, table.concat(currentString))
            end
            currentString = {}
        end
        
        byte = buffer:readByte()
    end
    
    if #currentString >= 3 then
        table.insert(strings, table.concat(currentString))
    end
    
    table.insert(output, string.format("Actual Size: %d bytes", byteCount))
    
    -- Add found strings
    if #strings > 0 then
        table.insert(output, "\nStrings found:")
        for i, str in ipairs(strings) do
            table.insert(output, string.format("%2d: \"%s\"", i, str))
        end
    end
    
    -- Add byte analysis
    table.insert(output, "\nByte analysis:")
    table.insert(output, table.concat(byteStrings, "\n"))
    
    -- Add raw hex dump
    table.insert(output, "\nRaw hex dump:")
    local hexDump = {}
    for i, b in ipairs(totalBytes) do
        table.insert(hexDump, string.format("%02X", b))
        if i % 16 == 0 then
            table.insert(hexDump, "\n")
        else
            table.insert(hexDump, " ")
        end
    end
    table.insert(output, table.concat(hexDump))
    
    return table.concat(output, "\n")
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
