-- User Options
local ENABLE_ENEMY_SIMULATION = false     -- Simulates enemy uber building patterns
local IGNORE_KRITZ = false              -- Replace kritz percentage with fake uber
local SHOW_TOP_LEFT_BOX = true          -- Show the top-left information box
local SHOW_CENTER_TEXT = true           -- Show the uber advantage text

local CONFIG = {
    showTopLeftBox = SHOW_TOP_LEFT_BOX,
    topLeftBox = {
        x = 22 * 6,
        y = 115,
        backgroundColor = {0, 0, 0, 100},
        font = {
            name = "Tahoma",
            size = -11,
            weight = 500,
            flags = FONTFLAG_OUTLINE | FONTFLAG_CUSTOM
        }
    },
    
    advantageText = {
        enabled = SHOW_CENTER_TEXT,
        positionMode = "center",
        centerOffset = {
            x = 0,
            y = 50
        },
        position = {
            x = 500,
            y = 500
        },
        font = {
            name = "Tahoma",
            size = -18,
            weight = 700,
            flags = FONTFLAG_OUTLINE | FONTFLAG_CUSTOM
        }
    },
    
    ignoreKritz = IGNORE_KRITZ,
    approximation = {
        enabled = ENABLE_ENEMY_SIMULATION,
        buildStates = {
            regular = {
                rate = 2.5, -- Base uber build rate (2.5% per second)
                duration = {
                    min = 8,
                    max = 15
                }
            },
            critHeals = {
                rate = 5.0, -- Fast build on injured players
                duration = {
                    min = 3,
                    max = 8
                }
            },
            overheal = {
                rate = 1.25, -- Slower build on overhealed players
                duration = {
                    min = 5,
                    max = 12
                }
            },
            noTarget = {
                rate = 0, -- No building when not healing
                duration = {
                    min = 2,
                    max = 5
                }
            }
        },
        stateTransitions = {
            regular = {
                critHeals = 0.3,
                overheal = 0.5,
                noTarget = 0.2
            },
            critHeals = {
                regular = 0.7,
                overheal = 0.2,
                noTarget = 0.1
            },
            overheal = {
                regular = 0.6,
                critHeals = 0.3,
                noTarget = 0.1
            },
            noTarget = {
                regular = 0.7,
                critHeals = 0.3
            }
        },
        maxErrorMargin = 8,
        correctionRate = 0.5,
        stabilization = {
            minUberDifferenceForUse = 10,    -- Minimum uber difference to consider it used
            flickerPreventionDelay = 0.5,    -- Time in seconds to prevent rapid state changes
            smoothingFactor = 0.1,           -- How smooth the uber changes should be (0-1)
            minTicksBetweenUpdates = 5       -- Minimum ticks between uber updates
        }
    },
    medDeathDuration = 3,
    evenThresholdRange = 5,
    
    colors = {
        dead = {170, 170, 170, 255},
        lowUber = {255, 0, 0, 255},
        midUber = {255, 255, 0, 255},
        highUber = {0, 255, 0, 255},
        fullAd = {0, 255, 0, 255},
        fullDisad = {255, 0, 0, 255},
        even = {128, 128, 128, 255},
        theyUsed = {255, 165, 0, 255},
        weUsed = {0, 191, 255, 255}
    },
    
    uberThresholds = {
        mid = 40,
        high = 70
    }
}

-- Initialize fonts
local mainFont = draw.CreateFont(CONFIG.topLeftBox.font.name, CONFIG.topLeftBox.font.size, CONFIG.topLeftBox.font.weight, CONFIG.topLeftBox.font.flags)
local advantageFont = draw.CreateFont(CONFIG.advantageText.font.name, CONFIG.advantageText.font.size, CONFIG.advantageText.font.weight, CONFIG.advantageText.font.flags)

-- State tracking variables
local prevUber = {[2] = 0, [3] = 0}
local status = {[2] = "", [3] = ""}
local uberDecreasing = {[2] = false, [3] = false}
local medDeathTime = {[2] = 0, [3] = 0}
local buildingState = {
    [2] = {
        currentState = "regular",
        ticksInState = 0,
        stateDuration = 0,
        totalBuilt = 0,
        lastUpdate = 0,
        lastReal = 0,
        lastStateChange = 0,
        smoothedValue = 0
    },
    [3] = {
        currentState = "regular",
        ticksInState = 0,
        stateDuration = 0,
        totalBuilt = 0,
        lastUpdate = 0,
        lastReal = 0,
        lastStateChange = 0,
        smoothedValue = 0
    }
}

-- Check if game is in pregame
local function isInPregame()
    return gamerules.GetRoundState() == 1 -- ROUND_PREGAME
end

local function getNextBuildState(currentState)
    local transitions = CONFIG.approximation.stateTransitions[currentState]
    if not transitions then return "regular", 10 end
    
    local roll = math.random()
    local cumulative = 0
    
    for nextState, chance in pairs(transitions) do
        cumulative = cumulative + chance
        if roll <= cumulative then
            local stateConfig = CONFIG.approximation.buildStates[nextState]
            local duration = math.random(stateConfig.duration.min, stateConfig.duration.max)
            return nextState, duration
        end
    end
    
    return "regular", 10 -- Fallback
end

local function simulateEnemyUber(realUber, teamNumber, currentTick)
    if not CONFIG.approximation.enabled then return realUber end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer or teamNumber == localPlayer:GetTeamNumber() then
        return realUber
    end
    
    local state = buildingState[teamNumber]
    if not state then return realUber end
    
    -- Initialize state if needed
    if state.lastUpdate == 0 then
        state.lastUpdate = currentTick
        state.lastReal = realUber
        state.totalBuilt = realUber
        state.currentState = "regular"
        state.stateDuration = 10
        state.lastStateChange = currentTick
        state.smoothedValue = realUber
        return realUber
    end

    -- Prevent too frequent updates
    if currentTick - state.lastUpdate < CONFIG.approximation.stabilization.minTicksBetweenUpdates then
        return math.floor(state.smoothedValue)
    end
    
    local ticksPassed = currentTick - state.lastUpdate
    state.lastUpdate = currentTick

    -- Detect uber usage with improved stability
    if realUber < state.lastReal - CONFIG.approximation.stabilization.minUberDifferenceForUse and
       currentTick - state.lastStateChange > CONFIG.approximation.stabilization.flickerPreventionDelay * 66 then
        if state.lastReal > 95 then  -- Likely actual uber usage
            state.totalBuilt = realUber
            state.lastReal = realUber
            state.currentState = "noTarget"
            state.stateDuration = math.random(2, 4)
            state.ticksInState = 0
            state.lastStateChange = currentTick
            state.smoothedValue = realUber
            return realUber
        end
    end
    
    state.lastReal = realUber
    
    -- Update state with stability check
    state.ticksInState = state.ticksInState + ticksPassed
    if state.ticksInState >= state.stateDuration * 66 and
       currentTick - state.lastStateChange > CONFIG.approximation.stabilization.flickerPreventionDelay * 66 then
        state.currentState, state.stateDuration = getNextBuildState(state.currentState)
        state.ticksInState = 0
        state.lastStateChange = currentTick
    end
    
    -- Build uber based on current state with smoothing
    local buildRate = CONFIG.approximation.buildStates[state.currentState].rate
    local targetValue = math.min(100, state.totalBuilt + (buildRate * ticksPassed / 66))
    
    -- Apply smoothing to prevent rapid fluctuations
    state.smoothedValue = state.smoothedValue + (targetValue - state.smoothedValue) * 
                         CONFIG.approximation.stabilization.smoothingFactor
    
    -- Ensure we don't drift too far from real uber
    local difference = state.smoothedValue - realUber
    if math.abs(difference) > CONFIG.approximation.maxErrorMargin then
        state.smoothedValue = state.smoothedValue - difference * CONFIG.approximation.correctionRate
    end
    
    state.totalBuilt = state.smoothedValue
    
    return math.floor(state.smoothedValue)
end

local function getWeaponType(itemDefinitionIndex)
    if not itemDefinitionIndex then return "UBER", false end
    
    if CONFIG.ignoreKritz and itemDefinitionIndex == 35 then
        return "UBER", true
    end
    
    local types = {
        [29] = "UBER",
        [211] = "UBER",
        [663] = "UBER",
        [35] = "KRITZ",
        [411] = "QUICKFIX",
        [998] = "VACCINATOR"
    }
    return types[itemDefinitionIndex] or "UBER", false
end

local function getColorForUber(percentage, isAlive)
    if not isAlive then return CONFIG.colors.dead end
    if percentage == 0 then return CONFIG.colors.dead end
    if percentage > CONFIG.uberThresholds.high then return CONFIG.colors.highUber end
    if percentage > CONFIG.uberThresholds.mid then return CONFIG.colors.midUber end
    return CONFIG.colors.lowUber
end

local function drawWithColor(color, func)
    if color and func then
        draw.Color(table.unpack(color))
        func()
    end
end

local function getAdvantageTextPosition(textWidth, textHeight)
    if CONFIG.advantageText.positionMode == "center" then
        local screenWidth, screenHeight = draw.GetScreenSize()
        return math.floor(screenWidth / 2 - textWidth / 2 + CONFIG.advantageText.centerOffset.x),
               math.floor(screenHeight / 2 + CONFIG.advantageText.centerOffset.y)
    else
        return CONFIG.advantageText.position.x,
               CONFIG.advantageText.position.y
    end
end

local function onDraw()
    if engine.IsGameUIVisible() or isInPregame() then return end

    local lineoffset = 0
    local players = entities.FindByClass("CTFPlayer")
    local medics = {[2] = {}, [3] = {}}
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    local localTeam = localPlayer:GetTeamNumber()
    if not localTeam then return end
    
    local currentTime = globals.CurTime()
    local currentTick = globals.TickCount()

    if CONFIG.showTopLeftBox then
        drawWithColor(CONFIG.topLeftBox.backgroundColor, function()
            draw.FilledRect(5, CONFIG.topLeftBox.y - 5, math.floor(24 * 15), 
                          math.floor(CONFIG.topLeftBox.y + 25 + (lineoffset * 15)))
        end)
    end

    -- Find and process medics
    for _, entity in pairs(players) do
        if entity and entity:GetTeamNumber() and entity:GetPropInt("m_iClass") == 5 then
            local teamNumber = entity:GetTeamNumber()
            local isAlive = entity:IsAlive()
            local medigun = entity:GetEntityForLoadoutSlot(1)
            
            if medigun then
                local chargeLevel = medigun:GetPropFloat("LocalTFWeaponMedigunData", "m_flChargeLevel") or 0
                local itemDefinitionIndex = medigun:GetPropInt("m_iItemDefinitionIndex")
                local weaponName, isKritzOverride = getWeaponType(itemDefinitionIndex)
                local percentageValue = math.floor(chargeLevel * 100)
                
                if isKritzOverride then
                    percentageValue = math.floor((currentTime % 100) + 1)
                end

                -- Apply simulation
                percentageValue = simulateEnemyUber(percentageValue, teamNumber, currentTick)
                
                table.insert(medics[teamNumber], {
                    name = entity:GetName() or "Unknown",
                    weaponName = weaponName,
                    uber = percentageValue,
                    isAlive = isAlive
                })

                if not isAlive and status[teamNumber] ~= "MED DIED" then
                    status[teamNumber] = "MED DIED"
                    medDeathTime[teamNumber] = currentTime
                    uberDecreasing[teamNumber] = false
                elseif status[teamNumber] == "MED DIED" and isAlive then
                    status[teamNumber] = ""
                elseif isAlive and percentageValue < (prevUber[teamNumber] or 0) - CONFIG.approximation.stabilization.minUberDifferenceForUse then
                    if status[teamNumber] ~= "THEY USED" and status[teamNumber] ~= "WE USED" and
                       currentTick - (buildingState[teamNumber].lastStateChange or 0) > CONFIG.approximation.stabilization.flickerPreventionDelay * 66 then
                        status[teamNumber] = teamNumber == localTeam and "WE USED" or "THEY USED"
                    end
                    uberDecreasing[teamNumber] = true
                elseif isAlive and percentageValue > (prevUber[teamNumber] or 0) and uberDecreasing[teamNumber] then
                    status[teamNumber] = ""
                    uberDecreasing[teamNumber] = false
                end
                
                prevUber[teamNumber] = percentageValue

                if CONFIG.showTopLeftBox then
                    draw.SetFont(mainFont)
                    local color = getColorForUber(percentageValue, isAlive)
                    drawWithColor(color, function()
                        local name = entity:GetName() or "Unknown"
                        draw.Text(20, math.floor(CONFIG.topLeftBox.y + 15 + (lineoffset * 15)),
                                name .. " -> " .. weaponName)
                        draw.Text(math.floor(22 * 15), math.floor(CONFIG.topLeftBox.y + 15 + (lineoffset * 15)),
                                isAlive and (percentageValue .. "%") or "DEAD")
                    end)
                    lineoffset = lineoffset + 1
                end
            end
        end
    end

    -- Draw advantage text only if we have medics on both teams
    if CONFIG.advantageText.enabled then
        -- First verify we have valid medic data
        local redMedic = medics[2][1]
        local bluMedic = medics[3][1]
        
        if redMedic and bluMedic then -- Only proceed if we have both medics
            local redUber = redMedic.isAlive and redMedic.uber or 0
            local bluUber = bluMedic.isAlive and bluMedic.uber or 0
            local enemyTeam = localTeam == 2 and 3 or 2
            local friendlyTeam = localTeam
            local difference = (localTeam == 2) and (redUber - bluUber) or (bluUber - redUber)
            
            -- Make sure we have valid medic data for both teams before accessing properties
            local friendlyMedic = medics[friendlyTeam][1]
            local enemyMedic = medics[enemyTeam][1]
            
            if not friendlyMedic or not enemyMedic then return end
            
            local displayText, textColor
            
            if status[friendlyTeam] == "MED DIED" then
                if currentTime - (medDeathTime[friendlyTeam] or 0) <= CONFIG.medDeathDuration then
                    displayText = "OUR MED DIED"
                    textColor = CONFIG.colors.fullDisad
                else
                    displayText = "FULL DISAD"
                    textColor = CONFIG.colors.fullDisad
                end
            elseif status[enemyTeam] == "MED DIED" and 
                currentTime - (medDeathTime[enemyTeam] or 0) <= CONFIG.medDeathDuration then
                displayText = "THEIR MED DIED"
                textColor = CONFIG.colors.fullAd
            elseif not enemyMedic.isAlive then
                displayText = "FULL AD"
                textColor = CONFIG.colors.fullAd
            elseif not friendlyMedic.isAlive then
                displayText = "FULL DISAD"
                textColor = CONFIG.colors.fullDisad
            elseif friendlyMedic.uber == 100 and enemyMedic.uber < 100 then
                displayText = string.format("FULL AD: %d%%", difference)
                textColor = CONFIG.colors.fullAd
            elseif enemyMedic.uber == 100 and friendlyMedic.uber < 100 then
                displayText = string.format("FULL DISAD: %d%%", math.abs(difference))
                textColor = CONFIG.colors.fullDisad
            elseif status[enemyTeam] == "THEY USED" then
                displayText = "THEY USED"
                textColor = CONFIG.colors.theyUsed
            elseif status[friendlyTeam] == "WE USED" then
                displayText = "WE USED"
                textColor = CONFIG.colors.weUsed
            elseif math.abs(difference) <= CONFIG.evenThresholdRange then
                displayText = "EVEN"
                textColor = CONFIG.colors.even
            elseif difference > 0 then
                displayText = string.format("AD: %d%%", difference)
                textColor = CONFIG.colors.fullAd
            else
                displayText = string.format("DISAD: %d%%", math.abs(difference))
                textColor = CONFIG.colors.fullDisad
            end
            
            if displayText and textColor then
                draw.SetFont(advantageFont)
                local textWidth, textHeight = draw.GetTextSize(displayText)
                local x, y = getAdvantageTextPosition(textWidth, textHeight)
                drawWithColor(textColor, function()
                    draw.Text(x, y, displayText)
                end)
            end
        end
    end
end

-- Clean up any previous instances and register the new callback
callbacks.Unregister("Draw", "medigunDraw")
callbacks.Register("Draw", "medigunDraw", onDraw)
