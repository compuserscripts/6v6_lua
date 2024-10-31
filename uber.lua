local font = draw.CreateFont("Tahoma", -11, 500, FONTFLAG_OUTLINE | FONTFLAG_CUSTOM)
local advantageFont = draw.CreateFont("Tahoma", -18, 700, FONTFLAG_OUTLINE | FONTFLAG_CUSTOM)

local prevUber = {[2] = 0, [3] = 0}
local status = {[2] = "", [3] = ""}
local uberDecreasing = {[2] = false, [3] = false}
local medDeathTime = {[2] = 0, [3] = 0}
local MED_DIED_DURATION = 3 -- Duration to display "MED DIED" in seconds

local function onDraw()
    local lineoffset = 0
    if engine.IsGameUIVisible() == false then
        local players = entities.FindByClass("CTFPlayer")
        local medics = {[2] = {}, [3] = {}} -- Initialize tables for RED (2) and BLU (3) teams
        local localPlayer = entities.GetLocalPlayer()
        local localTeam = localPlayer:GetTeamNumber()
        local currentTime = globals.CurTime()

        for idx, entity in pairs(players) do
            if entity:GetTeamNumber() and entity:GetPropInt("m_iClass") == 5 then 
                local teamNumber = entity:GetTeamNumber()
                local isAlive = entity:IsAlive()
                local medigun = entity:GetEntityForLoadoutSlot(1)
                if medigun ~= nil then
                    local itemDefinitionIndex = medigun:GetPropInt("m_iItemDefinitionIndex")
                    local itemDefinition = itemschema.GetItemDefinitionByID(itemDefinitionIndex)
                    local weaponName = itemDefinition:GetID()
                    if weaponName == 29 or weaponName == 211 or weaponName == 663 then
                        weaponName = "UBER"
                    elseif weaponName == 35 then
                        weaponName = "KRITZ"
                    elseif weaponName == 411 then
                        weaponName = "QUICKFIX"
                    elseif weaponName == 998 then
                        weaponName = "VACCINATOR"
                    else
                        weaponName = "UBER"
                    end
                    
                    local uber = medigun:GetPropFloat("LocalTFWeaponMedigunData", "m_flChargeLevel")
                    local percentageValue = math.floor(uber * 100)
                    
                    table.insert(medics[teamNumber], {
                        name = entity:GetName(),
                        weaponName = weaponName,
                        uber = percentageValue,
                        isAlive = isAlive
                    })
                    
                    -- Update status
                    if not isAlive and status[teamNumber] ~= "MED DIED" then
                        status[teamNumber] = "MED DIED"
                        medDeathTime[teamNumber] = currentTime
                        uberDecreasing[teamNumber] = false
                    elseif status[teamNumber] == "MED DIED" and isAlive then
                        status[teamNumber] = ""
                    elseif isAlive and percentageValue < prevUber[teamNumber] then
                        if status[teamNumber] ~= "THEY USED" and status[teamNumber] ~= "WE USED" then
                            status[teamNumber] = teamNumber == localTeam and "WE USED" or "THEY USED"
                        end
                        uberDecreasing[teamNumber] = true
                    elseif isAlive and percentageValue > prevUber[teamNumber] and uberDecreasing[teamNumber] then
                        status[teamNumber] = ""
                        uberDecreasing[teamNumber] = false
                    end
                    
                    prevUber[teamNumber] = percentageValue

                    draw.SetFont(font)
                    draw.Color(255, 255, 255, 255)
                    draw.Text(math.floor(22*6), 115, "Team Ubercharge Info")

                    if not isAlive then
                        draw.Color(170, 170, 170, 255) -- white for dead medic
                    elseif percentageValue == 0 then
                        draw.Color(170, 170, 170, 255) -- white
                    elseif percentageValue > 40 then
                        draw.Color(255, 255, 0, 255) -- yellow
                    elseif percentageValue > 70 then
                        draw.Color(0, 255, 0, 255) -- green
                    else
                        draw.Color(255, 0, 0, 255) -- red
                    end
                    
                    draw.Text(20, math.floor(130+(lineoffset*15)), entity:GetName().." -> "..weaponName)
                    draw.Text(math.floor(22*15), math.floor(130+(lineoffset*15)), isAlive and (percentageValue.."%") or "DEAD")
                    lineoffset = lineoffset + 1
                end
            end
        end
        
        draw.Color(0, 0, 0, 100)
        draw.FilledRect(5, 110, math.floor(24*15), math.floor(140 + (lineoffset*15)))
        
        -- Display uber advantage/disadvantage or status message
        if #medics[2] == 1 and #medics[3] == 1 then
            local redUber = medics[2][1].isAlive and medics[2][1].uber or 0
            local bluUber = medics[3][1].isAlive and medics[3][1].uber or 0
            local enemyTeam = localTeam == 2 and 3 or 2
            local friendlyTeam = localTeam
            local difference = (localTeam == 2) and (redUber - bluUber) or (bluUber - redUber)
            
            local displayText
            local textColor

            if status[friendlyTeam] == "MED DIED" then
                if currentTime - medDeathTime[friendlyTeam] <= MED_DIED_DURATION then
                    displayText = "OUR MED DIED"
                    textColor = {255, 0, 0, 255} -- Red for MED DIED
                else
                    displayText = "FULL DISAD"
                    textColor = {255, 0, 0, 255} -- Red for FULL DISAD
                end
            elseif status[enemyTeam] == "MED DIED" and currentTime - medDeathTime[enemyTeam] <= MED_DIED_DURATION then
                displayText = "THEIR MED DIED"
                textColor = {0, 255, 0, 255} -- Red for MED DIED
            elseif not medics[enemyTeam][1].isAlive then
                displayText = "FULL AD"
                textColor = {0, 255, 0, 255} -- Green for FULL AD
            elseif not medics[friendlyTeam][1].isAlive then
                displayText = "FULL DISAD"
                textColor = {255, 0, 0, 255} -- Red for FULL DISAD
            elseif medics[friendlyTeam][1].uber == 100 and medics[enemyTeam][1].uber < 100 then
                --displayText = "FULL AD"
                displayText = string.format("FULL AD: %d%%", difference)
                textColor = {0, 255, 0, 255} -- Green for FULL AD
            elseif medics[enemyTeam][1].uber == 100 and medics[friendlyTeam][1].uber < 100 then
                --displayText = "FULL DISAD"
                displayText = string.format("FULL DISAD: %d%%", math.abs(difference))
                textColor = {255, 0, 0, 255} -- Red for FULL DISAD
            elseif status[enemyTeam] == "THEY USED" then
                displayText = "THEY USED"
                textColor = {255, 165, 0, 255} -- Orange for THEY USED
            elseif status[friendlyTeam] == "WE USED" then
                displayText = "WE USED"
                textColor = {0, 191, 255, 255} -- Deep Sky Blue for WE USED
            elseif math.abs(difference) <= 5 then
                displayText = "EVEN"
                textColor = {128, 128, 128, 255} -- Gray color
            elseif difference > 0 then
                displayText = string.format("AD: %d%%", difference)
                textColor = {0, 255, 0, 255} -- Green color
            else
                displayText = string.format("DISAD: %d%%", math.abs(difference))
                textColor = {255, 0, 0, 255} -- Red color
            end
            
            draw.SetFont(advantageFont)
            
            local screenWidth, screenHeight = draw.GetScreenSize()
            local textWidth, textHeight = draw.GetTextSize(displayText)
            
            draw.Color(table.unpack(textColor))
            draw.Text(math.floor(screenWidth / 2 - textWidth / 2), math.floor(screenHeight / 2 + 50), displayText)
        end
    end
end

callbacks.Unregister("Draw", "medigunDraw")
callbacks.Register("Draw", "medigunDraw", onDraw)