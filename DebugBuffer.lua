-- Custom bit manipulation functions
local bit = {}

function bit.band(a, b) local result = 0 local bitval = 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then result = result + bitval end bitval = bitval * 2 a = math.floor(a/2) b = math.floor(b/2) end return result end
function bit.bor(a, b) local result = 0 local bitval = 1 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then result = result + bitval end bitval = bitval * 2 a = math.floor(a/2) b = math.floor(b/2) end return result end
function bit.lshift(a, b) return a * (2 ^ b) end
function bit.rshift(a, b) return math.floor(a / (2 ^ b)) end

local buffer = {}

local function createBuffer(data)
    local buf = {
        data = data,
        cursor = {
            byte = 1,
            bit = 0
        }
    }

    function buf.cursor:advance(bits)
        self.byte = self.byte + math.floor((self.bit + bits) / 8)
        self.bit = (self.bit + bits) % 8
    end
    
    function buf.cursor:ceil()
        if self.bit > 0 then 
            self.byte = self.byte + 1
        end
        self.bit = 0
    end

    function buf:toString()
        local t = {}
        for i, v in ipairs(self.data) do
            t[i] = string.char(v % 256)
        end
        return table.concat(t)
    end

    return buf
end

function buffer.read(data)
    local buf = createBuffer(data)

    function buf:readBit()
        if self.cursor.byte > #self.data then return 0 end
        local byte = self.data[self.cursor.byte]
        local bit = bit.band(bit.rshift(byte, 7 - self.cursor.bit), 1)
        self.cursor:advance(1)
        return bit
    end

    function buf:readByte()
        if self.cursor.byte > #self.data then return 0 end
        local byte = self.data[self.cursor.byte]
        self.cursor:advance(8)
        return byte
    end

    function buf:readUInt(width)
        local value = 0
        for i = 1, width do
            value = bit.bor(bit.lshift(value, 1), self:readBit())
        end
        return value
    end

    function buf:readInt(width)
        local value = self:readUInt(width)
        local sign = bit.band(value, bit.lshift(1, width - 1))
        if sign ~= 0 then
            value = value - bit.lshift(1, width)
        end
        return value
    end

    function buf:readFloat()
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

    function buf:readString()
        local result = {}
        while self.cursor.byte <= #self.data do
            local byte = self:readByte()
            if byte == 0 then break end
            table.insert(result, string.char(byte % 256))
        end
        return table.concat(result)
    end

    function buf:readVarInt32()
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

    return buf
end

-- User message name mapping
local umsg_name = {
    [0] = 'Geiger', 'Train', 'HudText', 'SayText', 'SayText2', 'TextMsg', 'ResetHUD', 'GameTitle', 'ItemPickup', 'ShowMenu', 'Shake', 'Fade', 'VGUIMenu', 'Rumble', 'CloseCaption', 'SendAudio', 'VoiceMask', 'RequestState', 'Damage', 'HintText', 'KeyHintText', 'HudMsg', 'AmmoDenied', 'AchievementEvent', 'UpdateRadar', 'VoiceSubtitle', 'HudNotify', 'HudNotifyCustom', 'PlayerStatsUpdate', 'MapStatsUpdate', 'PlayerIgnited', 'PlayerIgnitedInv', 'HudArenaNotify', 'UpdateAchievement', 'TrainingMsg', 'TrainingObjective', 'DamageDodged', 'PlayerJarated', 'PlayerExtinguished', 'PlayerJaratedFade', 'PlayerShieldBlocked', 'BreakModel', 'CheapBreakModel', 'BreakModel_Pumpkin', 'BreakModelRocketDud', 'CallVoteFailed', 'VoteStart', 'VotePass', 'VoteFailed', 'VoteSetup', 'PlayerBonusPoints', 'RDTeamPointsChanged', 'SpawnFlyingBird', 'PlayerGodRayEffect', 'PlayerTeleportHomeEffect', 'MVMStatsReset', 'MVMPlayerEvent', 'MVMResetPlayerStats', 'MVMWaveFailed', 'MVMAnnouncement', 'MVMPlayerUpgradedEvent', 'MVMVictory', 'MVMWaveChange', 'MVMLocalPlayerUpgradesClear', 'MVMLocalPlayerUpgradesValue', 'MVMResetPlayerWaveSpendingStats', 'MVMLocalPlayerWaveSpendingValue', 'MVMResetPlayerUpgradeSpending', 'MVMServerKickTimeUpdate', 'PlayerLoadoutUpdated', 'PlayerTauntSoundLoopStart', 'PlayerTauntSoundLoopEnd', 'ForcePlayerViewAngles', 'BonusDucks', 'EOTLDuckEvent', 'PlayerPickupWeapon', 'QuestObjectiveCompleted', 'SPHapWeapEvent', 'HapDmg', 'HapPunch', 'HapSetDrag', 'HapSetConst', 'HapMeleeContact'
}

-- Function to analyze buffer contents
local function analyzeBuffer(bf)
    local output = {}
    
    -- Read message type
    local msgType = bf:readVarInt32()
    table.insert(output, string.format("Message Type: %d (%s)", msgType, umsg_name[msgType] or "Unknown"))
    
    -- Read message size (if available)
    local msgSize = bf:readVarInt32()
    table.insert(output, string.format("Message Size: %d bytes", msgSize))
    
    -- Read all remaining data
    table.insert(output, "\n--- Message Content ---")
    while bf.cursor.byte <= #bf.data do
        local byte = bf:readByte()
        table.insert(output, string.format("Byte: %d (0x%02X)", byte, byte))
    end
    
    return table.concat(output, "\n")
end

-- Debug hook for messages
local function debugMessageHook(msg)
    print("Debug: Message hook triggered")

    local status, err = pcall(function()
        local bitbuf = msg:GetBitBuffer()
        
        -- Convert BitBuffer to integer array
        local bufferData = {}
        for i = 1, bitbuf:GetDataBytesLength() do
            bufferData[i] = bitbuf:ReadByte()
        end
        
        print(string.format("Debug: Buffer length: %d bytes", #bufferData))
        
        -- Create our buffer object
        local bf = buffer.read(bufferData)
        
        print("=== Message Analysis ===")
        print(analyzeBuffer(bf))
        print("=========================")
    end)

    if not status then
        print("Error in debugMessageHook: " .. tostring(err))
    end
end

-- Register the debug hook for all message types
callbacks.Register("DispatchUserMessage", "debugMessageHook", debugMessageHook)

-- Cleanup function
local function cleanup()
    callbacks.Unregister("DispatchUserMessage", "debugMessageHook")
    print("Debug: Script unloaded")
end

-- Register cleanup on script unload
callbacks.Register("Unload", "CleanupBitBufferDebug", cleanup)

print("Lmaobox-Compatible BitBuffer Debug Script loaded. Check chat for detailed message analysis.")