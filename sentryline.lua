-- Configuration
local CONFIG = {
    lineColor = {r = 255, g = 0, b = 0, a = 255},  -- Red line
    lineLength = 500,  -- Length of aim line in hammer units
    showFriendly = false,  -- Whether to show friendly sentry aim lines
}

-- Cache frequently used functions
local WorldToScreen = client.WorldToScreen
local Color = draw.Color
local Line = draw.Line

-- Helper function to get position from bone matrix
local function GetPositionFromMatrix(matrix)
    return Vector3(
        matrix[1][4],
        matrix[2][4],
        matrix[3][4]
    )
end

-- Helper function to get angles from bone matrix
local function GetAnglesFromMatrix(matrix)
    -- Use the third column for forward direction (TF2 matrix orientation)
    local forward = Vector3(matrix[1][3], matrix[2][3], matrix[3][3])
    return forward:Angles()
end

-- Helper function to get sentry muzzle position and angles
local function GetSentryAimData(sentry)
    -- Get bone matrices
    local boneMatrices = sentry:SetupBones()
    if not boneMatrices then return nil, nil end
    
    -- Get turret bone index based on level
    local level = sentry:GetPropInt("m_iUpgradeLevel") or 0
    local turretBoneIndex = 1 -- Default to first bone
    
    if level == 1 then
        turretBoneIndex = 2  -- Level 2 turret bone
    elseif level == 2 then
        turretBoneIndex = 3  -- Level 3 turret bone
    end
    
    -- Get turret bone matrix
    local turretMatrix = boneMatrices[turretBoneIndex]
    if not turretMatrix then return nil, nil end
    
    -- Get position and angles from matrix
    local muzzlePos = GetPositionFromMatrix(turretMatrix)
    local aimAngles = GetAnglesFromMatrix(turretMatrix)
    
    -- If sentry has a target, use direction to target instead
    local target = sentry:GetPropEntity("m_hEnemy")
    if target and target:IsValid() and not target:IsDormant() then
        local targetPos = target:GetAbsOrigin()
        targetPos.z = targetPos.z + 40  -- Aim at chest height
        local direction = targetPos - muzzlePos
        aimAngles = direction:Angles()
    end
    
    return muzzlePos, aimAngles
end

-- Helper function to get end position of aim line
local function GetAimLineEndPos(startPos, angles)
    if not startPos or not angles then return nil end
    local forward = angles:Forward()
    return startPos + (forward * CONFIG.lineLength)
end

local function OnDraw()
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    local sentries = entities.FindByClass("CObjectSentrygun")
    for _, sentry in pairs(sentries) do
        -- Skip if sentry is invalid or dormant
        if not sentry:IsValid() or sentry:IsDormant() then goto continue end
        
        -- Skip if sentry is not built yet
        if sentry:GetPropBool("m_bBuilding") then goto continue end
        
        -- Skip if sentry is friendly and we don't want to show friendly sentries
        if not CONFIG.showFriendly and sentry:GetTeamNumber() == localPlayer:GetTeamNumber() then 
            goto continue 
        end
        
        -- Get sentry muzzle position and angles
        local muzzlePos, angles = GetSentryAimData(sentry)
        if not muzzlePos or not angles then goto continue end
        
        -- Calculate end position of aim line
        local endPos = GetAimLineEndPos(muzzlePos, angles)
        if not endPos then goto continue end
        
        -- Convert positions to screen coordinates
        local startScreen = WorldToScreen(muzzlePos)
        local endScreen = WorldToScreen(endPos)
        
        -- Draw line if both points are on screen
        if startScreen and endScreen then
            Color(CONFIG.lineColor.r, CONFIG.lineColor.g, CONFIG.lineColor.b, CONFIG.lineColor.a)
            Line(startScreen[1], startScreen[2], endScreen[1], endScreen[2])
        end
        
        ::continue::
    end
end

-- Register callback
callbacks.Register("Draw", "SentryAimline", OnDraw)
