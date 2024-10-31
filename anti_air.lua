-- Configuration
local CONFIG = {
    showTracers = true,
    showBoxes = true,
    showChams = false, -- Disabled by default because of chams being bugged in lbox
    tracerOnlyWhenNotVisible = false,
    boxOnlyWhenNotVisible = false,
    chamsOnlyWhenNotVisible = false
}

-- Constants
local SOLDIER_CLASS = 3
local BLAST_JUMPING_COND = 81
local MAX_DISTANCE_SQR = 3500 * 3500

-- Colors
local COLOR_VISIBLE = {0, 255, 0, 125}
local COLOR_HIDDEN = {255, 0, 0, 255}
local COLOR_TRACER = {255, 0, 255, 255}

-- Pre-cache functions
local floor = math.floor
local unpack = unpack or table.unpack  -- For compatibility
local RealTime = globals.RealTime
local WorldToScreen = client.WorldToScreen
local TraceLine = engine.TraceLine
local GetScreenSize = draw.GetScreenSize
local Color = draw.Color
local Line = draw.Line
local OutlinedRect = draw.OutlinedRect

-- Chams material
local chamsMaterial = materials.Create("soldier_chams", [[
    "VertexLitGeneric"
    {
        "$basetexture" "vgui/white_additive"
        "$ignorez" "1"
    }
]])

-- Main drawing function
local function OnDraw()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    local players = entities.FindByClass("CTFPlayer")
    local screenW, screenH = GetScreenSize()
    local centerX, centerY = floor(screenW / 2), floor(screenH / 2)

    for idx, player in pairs(players) do
        if player:IsAlive() and
           player:GetTeamNumber() ~= localPlayer:GetTeamNumber() and
           player:GetPropInt("m_iClass") == SOLDIER_CLASS and
           player:InCond(BLAST_JUMPING_COND) then

            -- Check if player is within distance
            local playerPos = player:GetAbsOrigin()
            local localPos = localPlayer:GetAbsOrigin()
            if not playerPos or not localPos then goto continue end

            local dx = playerPos.x - localPos.x
            local dy = playerPos.y - localPos.y
            local dz = playerPos.z - localPos.z
            local distSqr = dx * dx + dy * dy + dz * dz

            if distSqr > MAX_DISTANCE_SQR then goto continue end

            -- Visibility check
            local isVisible = false
            local eyePos = localPos + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
            local trace = TraceLine(eyePos, playerPos, MASK_VISIBLE)
            if trace.entity and trace.entity:GetIndex() == player:GetIndex() then
                isVisible = true
            end

            -- 2D Box drawing
            if CONFIG.showBoxes and (not CONFIG.boxOnlyWhenNotVisible or not isVisible) then
                local mins = player:GetMins()
                local maxs = player:GetMaxs()

                if not mins or not maxs then goto continue end

                -- Using Vector3 directly for positions
                local bottomPos = Vector3(playerPos.x, playerPos.y, playerPos.z + mins.z)
                local topPos = Vector3(playerPos.x, playerPos.y, playerPos.z + maxs.z)

                local screenBottom = WorldToScreen(bottomPos)
                local screenTop = WorldToScreen(topPos)

                if screenBottom and screenTop then
                    local height = screenBottom[2] - screenTop[2]
                    local width = height * 0.75

                    local x1 = floor(screenBottom[1] - width / 2)
                    local y1 = floor(screenTop[2])
                    local x2 = floor(screenBottom[1] + width / 2)
                    local y2 = floor(screenBottom[2])

                    Color(unpack(isVisible and COLOR_VISIBLE or COLOR_HIDDEN))
                    OutlinedRect(x1, y1, x2, y2)
                end
            end

            -- Tracer drawing
            if CONFIG.showTracers and (not CONFIG.tracerOnlyWhenNotVisible or not isVisible) then
                local screenPos = WorldToScreen(playerPos)
                if screenPos then
                    Color(unpack(COLOR_TRACER))
                    Line(centerX, screenH, screenPos[1], screenPos[2])
                end
            end
        end
        ::continue::
    end
end

-- Chams function
local function OnDrawModel(ctx)
    if not CONFIG.showChams then return end

    local entity = ctx:GetEntity()
    if not entity or not entity:IsPlayer() then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or entity:GetTeamNumber() == localPlayer:GetTeamNumber() then return end

    if entity:GetPropInt("m_iClass") == SOLDIER_CLASS and
       entity:InCond(BLAST_JUMPING_COND) then

        -- Visibility check
        local isVisible = false
        local eyePos = localPlayer:GetAbsOrigin() + localPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")
        local playerPos = entity:GetAbsOrigin()
        local trace = TraceLine(eyePos, playerPos, MASK_VISIBLE)
        if trace.entity and trace.entity:GetIndex() == entity:GetIndex() then
            isVisible = true
        end

        if not CONFIG.chamsOnlyWhenNotVisible or not isVisible then
            ctx:ForcedMaterialOverride(chamsMaterial)
        end
    end
end

-- Register callbacks
callbacks.Register("Draw", "SimplifiedSoldierESP", OnDraw)
callbacks.Register("DrawModel", "SimplifiedSoldierChams", OnDrawModel)