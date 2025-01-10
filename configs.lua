local function decode_json(str)
    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end

    local space_chars = {}
    for _, c in ipairs{" ", "\t", "\r", "\n"} do space_chars[c] = true end
    
    local delim_chars = {[" "] = true, ["\t"] = true, ["\r"] = true, ["\n"] = true, 
                        ["]"] = true, ["}"] = true, [","] = true}
    
    local escape_chars = {["\\"] = true, ["/"] = true, ['"'] = true, ["b"] = true,
                         ["f"] = true, ["n"] = true, ["r"] = true, ["t"] = true, ["u"] = true}
    
    local literals = {["true"] = true, ["false"] = true, ["null"] = true}

    local literal_map = {["true"] = true, ["false"] = false, ["null"] = nil}

    local escape_char_map = {
        ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
        ["b"] = "\b", ["f"] = "\f", ["n"] = "\n", ["r"] = "\r", ["t"] = "\t"
    }

    local function decode_error(str, idx, msg)
        local line_count, col_count = 1, 1
        for i = 1, idx - 1 do
            col_count = col_count + 1
            if str:sub(i, i) == "\n" then
                line_count = line_count + 1
                col_count = 1
            end
        end
        error(string.format("%s at line %d col %d", msg, line_count, col_count))
    end

    local function next_char(str, idx, set, negate)
        for i = idx, #str do
            if set[str:sub(i, i)] ~= negate then return i end
        end
        return #str + 1
    end

    local function codepoint_to_utf8(n)
        local f = math.floor
        if n <= 0x7f then
            return string.char(n)
        elseif n <= 0x7ff then
            return string.char(f(n / 64) + 192, n % 64 + 128)
        elseif n <= 0xffff then
            return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
        elseif n <= 0x10ffff then
            return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                             f(n % 4096 / 64) + 128, n % 64 + 128)
        end
        error(string.format("invalid unicode codepoint '%x'", n))
    end

    local function parse_unicode_escape(s)
        local n1 = tonumber(s:sub(1, 4), 16)
        local n2 = tonumber(s:sub(7, 10), 16)
        if n2 then
            return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
        else
            return codepoint_to_utf8(n1)
        end
    end

    local function parse_string(str, i)
        local res = ""
        local j = i + 1
        local k = j

        while j <= #str do
            local x = str:byte(j)

            if x < 32 then
                decode_error(str, j, "control character in string")
            elseif x == 92 then -- `\`: Escape
                res = res .. str:sub(k, j - 1)
                j = j + 1
                local c = str:sub(j, j)
                if c == "u" then
                    local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                             or str:match("^%x%x%x%x", j + 1)
                             or decode_error(str, j - 1, "invalid unicode escape in string")
                    res = res .. parse_unicode_escape(hex)
                    j = j + #hex
                else
                    if not escape_chars[c] then
                        decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
                    end
                    res = res .. escape_char_map[c]
                end
                k = j + 1
            elseif x == 34 then -- `"`: End of string
                res = res .. str:sub(k, j - 1)
                return res, j + 1
            end
            j = j + 1
        end
        decode_error(str, i, "expected closing quote for string")
    end

    local function parse_number(str, i)
        local x = next_char(str, i, delim_chars)
        local s = str:sub(i, x - 1)
        local n = tonumber(s)
        if not n then decode_error(str, i, "invalid number '" .. s .. "'") end
        return n, x
    end

    local function parse_literal(str, i)
        local x = next_char(str, i, delim_chars)
        local word = str:sub(i, x - 1)
        if not literals[word] then decode_error(str, i, "invalid literal '" .. word .. "'") end
        return literal_map[word], x
    end

    -- Forward declaration for recursive parsing
    local parse

    local function parse_array(str, i)
        local res = {}
        local n = 1
        i = i + 1
        while 1 do
            local x
            i = next_char(str, i, space_chars, true)
            if str:sub(i, i) == "]" then
                i = i + 1
                break
            end
            x, i = parse(str, i)
            res[n] = x
            n = n + 1
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i)
            i = i + 1
            if chr == "]" then break end
            if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
        end
        return res, i
    end

    local function parse_object(str, i)
        local res = {}
        i = i + 1
        while 1 do
            local key, val
            i = next_char(str, i, space_chars, true)
            if str:sub(i, i) == "}" then
                i = i + 1
                break
            end
            if str:sub(i, i) ~= '"' then
                decode_error(str, i, "expected string for key")
            end
            key, i = parse(str, i)
            i = next_char(str, i, space_chars, true)
            if str:sub(i, i) ~= ":" then
                decode_error(str, i, "expected ':' after key")
            end
            i = next_char(str, i + 1, space_chars, true)
            val, i = parse(str, i)
            res[key] = val
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i)
            i = i + 1
            if chr == "}" then break end
            if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
        end
        return res, i
    end

    local char_func_map = {
        ['"'] = parse_string,
        ["0"] = parse_number, ["1"] = parse_number, ["2"] = parse_number,
        ["3"] = parse_number, ["4"] = parse_number, ["5"] = parse_number,
        ["6"] = parse_number, ["7"] = parse_number, ["8"] = parse_number,
        ["9"] = parse_number, ["-"] = parse_number,
        ["t"] = parse_literal, ["f"] = parse_literal, ["n"] = parse_literal,
        ["["] = parse_array, ["{"] = parse_object,
    }

    parse = function(str, idx)
        local chr = str:sub(idx, idx)
        local f = char_func_map[chr]
        if f then return f(str, idx) end
        decode_error(str, idx, "unexpected character '" .. chr .. "'")
    end

    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then
        decode_error(str, idx, "trailing garbage")
    end
    return res
end

-- Basic UI state management
local LastMouseState = false 
local MouseReleased = false
local isDragging = false
local dragOffsetX = 0
local dragOffsetY = 0
local isDraggingScrollbar = false
local wasScrollbarDragging = false
local conWasOpen = engine.Con_IsVisible()
local lastKeyState = false
local lastScrollTime = 0
local SCROLL_DELAY = 0.08
local hasSeenMousePress = false  -- Add flag for first press cycle
-- Function forward declarations
local fetchPage
local prefetchAdjacentPages
local refreshConfigs
local navigateToPage
-- Font management
local menuFont = nil
local lastFontSetting = nil

local cachedHash = nil
local lastKnownName = nil
local lastCheckTime = 0
local CHECK_INTERVAL = 5  -- Check every 5 seconds

local responseQueue = {}
local PRINT_DELAY = 0.1 -- seconds to wait after clear

local state = {
    -- UI State
    menuOpen = true,
    windowX = 100,
    windowY = 100,
    windowWidth = 400,
    windowHeight = 0,  -- Calculated based on other dimensions
    desiredItems = 17,
    titleBarHeight = 30,
    itemHeight = 25,
    footerHeight = 30,
    
    -- Content State
    configs = {},
    currentPage = 0,
    totalPages = 1,
    totalItems = 0,
    itemsPerPage = 20,
    scrollOffset = 0,
    
    -- Cache Management
    pageCache = {},
    isInitialLoad = true,
    isFetching = false,
    lastFetchTime = 0,
    FETCH_COOLDOWN = 0.5,
    CACHE_SIZE = 3,
    
    -- Interaction State
    clickStartedInMenu = false,
    clickStartedInTitleBar = false,
    clickStartedInScrollbar = false,
    clickStartX = 0,
    clickStartY = 0,
    interactionState = nil,  -- 'none', 'dragging', 'scrolling', 'clicking'
    clickStartRegion = nil,  -- 'titlebar', 'list', 'footer', nil
    
    -- Captcha State
    pendingCaptcha = nil,
    captchaExpiry = 0,
    pendingConfigId = nil,
    pendingConfigDesc = nil,
    pendingUname = nil,

    -- Version Management
    clientVersion = "1.0.0",
    serverVersion = nil,
    isVersionMismatch = false,

    consoleState = {
        wasOpen = false,
        pendingRestore = false,
        inMainMenu = false,
    }
}

-- Function to calculate window height based on current number of items
local function calculateWindowHeight()
    local actualItems = math.min(state.desiredItems, #state.configs)
    -- If no configs, show at least 1 row for the empty state message
    actualItems = math.max(actualItems, 1)
    return state.titleBarHeight + (actualItems * state.itemHeight) + state.footerHeight
end

state.windowHeight = calculateWindowHeight()

local function updateFont()
    local currentFont = gui.GetValue("font")
    if currentFont ~= lastFontSetting then
        menuFont = draw.CreateFont(currentFont, 14, 400) -- Create our own instance of the font
        lastFontSetting = currentFont
    end
    draw.SetFont(menuFont) -- Always set our font before drawing
end

-- UI Scale management
local originalScaleFactor = client.GetConVar("vgui_ui_scale_factor")
if originalScaleFactor ~= 1 then
    client.SetConVar("vgui_ui_scale_factor", "1")
end

local function GetMousePos()
    local mousePos = input.GetMousePos()
    return mousePos[1], mousePos[2]
end

local function MouseInBounds(pX, pY, pX2, pY2)
    local mX, mY = GetMousePos()
    return (mX >= pX and mX <= pX2 and mY >= pY and mY <= pY2)  -- Changed to >= and <=
end

-- Update UpdateMouseState function
local function UpdateMouseState()
    local mouseState = input.IsButtonDown(MOUSE_LEFT)
    
    -- Handle new click
    if mouseState and not LastMouseState then
        hasSeenMousePress = true  -- We've now seen a proper mouse press
        -- Reset all states on new click
        state.clickStartedInMenu = false
        state.clickStartedInTitleBar = false
        state.clickStartedInScrollbar = false
        state.interactionState = 'none'
        
        local mX, mY = GetMousePos()
        state.clickStartX = mX
        state.clickStartY = mY
        
        local menuX = state.windowX
        local menuY = state.windowY 
        local menuRight = menuX + state.windowWidth
        local menuBottom = menuY + state.windowHeight
        
        -- Check if click started in menu
        if MouseInBounds(menuX, menuY, menuRight, menuBottom) then
            state.clickStartedInMenu = true
                
            -- Track where the click started
            if MouseInBounds(menuX, menuY, menuRight, menuY + state.titleBarHeight) then
                state.clickStartedInTitleBar = true
                state.interactionState = 'dragging'
                state.clickStartRegion = 'titlebar'
            elseif MouseInBounds(menuX, menuY + state.windowHeight - state.footerHeight, menuRight, menuBottom) then
                state.clickStartRegion = 'footer'
            elseif #state.configs > 0 and MouseInBounds(
                menuRight - 16, 
                menuY + state.titleBarHeight,
                menuRight,
                menuBottom - state.footerHeight
            ) then
                state.clickStartedInScrollbar = true
                state.interactionState = 'scrolling'
                state.clickStartRegion = 'scrollbar'
            else
                state.interactionState = 'clicking'
                state.clickStartRegion = 'list'
            end
        end
    end
    
    -- Update MouseReleased state
    MouseReleased = (LastMouseState and not mouseState)
    LastMouseState = mouseState
    
    -- Reset states on release
    if MouseReleased then
        if isDraggingScrollbar then
            wasScrollbarDragging = false
            isDraggingScrollbar = false
            state.interactionState = 'none'
            state.clickStartRegion = nil  -- Reset the region on mouse release
            return true
        end
        
        -- Important: Reset interaction state when releasing mouse
        isDragging = false
        state.clickStartedInTitleBar = false
        state.interactionState = 'none'
    end
    
    return false
end

-- Function to calculate combined text width with config ID
local function getIdDisplayText(configId)
    return string.format(" [%s]", configId)
end

-- Modified truncateText function that accounts for potential ID display
local function truncateText(text, maxWidth, hasScrollbar, isHovered, configId)
    local padding = 20 -- 10px padding on each side
    local scrollbarWidth = hasScrollbar and 16 or 0
    local actualMaxWidth = maxWidth - padding - scrollbarWidth
    
    -- If hovering, we need to account for the ID text
    if isHovered then
        local idText = getIdDisplayText(configId)
        local idWidth = draw.GetTextSize(idText)
        actualMaxWidth = actualMaxWidth - idWidth
    end
    
    local fullWidth = draw.GetTextSize(text)
    if fullWidth <= actualMaxWidth then
        return text
    end
    
    -- Binary search for truncation point
    local left, right = 1, #text
    while left <= right do
        local mid = math.floor((left + right) / 2)
        local truncated = text:sub(1, mid) .. "..."
        local width = draw.GetTextSize(truncated)
        
        if width == actualMaxWidth then
            return truncated
        elseif width < actualMaxWidth then
            left = mid + 1
        else
            right = mid - 1
        end
    end
    
    return text:sub(1, right) .. "..."
end

-- Helper function to properly reverse a string (including UTF-8 characters)
local function reverseString(str)
    -- Ensure we're working with a string
    str = tostring(str)
    
    -- Convert to table of UTF-8 characters
    local t = {}
    for char in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        table.insert(t, char)
    end
    -- Reverse and concatenate
    local reversed = ""
    for i = #t, 1, -1 do
        reversed = reversed .. t[i]
    end
    return reversed
end

-- Pure Lua implementation of right shift
local function rshift(x, by)
    return math.floor(x / 2^by)
end

local function hashString(str)
    -- Ensure input is a string
    str = tostring(str or "")
    local salt = "cfg.lmao.mx"
    str = str .. salt
    
    -- Start with a prime number
    local hash = 2166136261
    
    for i = 1, #str do
        hash = hash ~ string.byte(str, i)
        hash = (hash * 16777619) % 0xFFFFFF
        
        -- Additional mixing using pure math operations
        hash = ((hash ~ rshift(hash, 8)) * 0x2127599bf4325) % 0xFFFFFF
    end
    
    -- Final mix
    hash = ((hash ~ rshift(hash, 4)) * 0x880355f21e6d1625) % 0xFFFFFF
    
    return string.format("%06x", hash)
end

local function getUname()
    -- Get current name
    local _, _, currentName = client.GetConVar("name")
    currentName = tostring(currentName or "")
    
    -- Periodic check for name changes
    local currentTime = globals.RealTime()
    if currentTime - lastCheckTime >= CHECK_INTERVAL then
        lastCheckTime = currentTime
        if currentName ~= lastKnownName then
            --print("Debug - Name change detected in periodic check")
            --print("Debug - Old name:", lastKnownName)
            --print("Debug - New name:", currentName)
            
            lastKnownName = currentName
            cachedHash = hashString(reverseString(currentName))
            
            --print("Debug - New hash calculated:", cachedHash)
        end
    end
    
    -- Calculate hash if we don't have one
    if cachedHash == nil then
        --print("Debug - Initial hash calculation")
        lastKnownName = currentName
        cachedHash = hashString(reverseString(currentName))
        --print("Debug - Hash calculated:", cachedHash)
    end
    
    return cachedHash
end

-- Helper function to check if a page is cached
local function isPageCached(page)
    return state.pageCache[page] ~= nil
end

-- Helper function to get cached configs for current page
local function getCurrentPageConfigs()
    return state.pageCache[state.currentPage] or {}
end

-- Modified mergePaginationData to be more selective
local function mergePaginationData(data, isPrefetch)
    if not data.pagination then return end
    
    --print("[Debug] Merging pagination data:")
    --print("  isInitialLoad:", state.isInitialLoad)
    --print("  isPrefetch:", isPrefetch)
    --print("  Current page:", state.currentPage)
    --print("  API page:", data.pagination.currentPage)
    
    -- Always update these metadata values if not a prefetch
    if not isPrefetch then
        state.totalPages = data.pagination.totalPages
        state.totalItems = data.pagination.totalItems
        state.itemsPerPage = data.pagination.itemsPerPage
    end
end

-- Modified fetchPage to handle pagination updates properly
fetchPage = function(page, callback, retryCount)
    retryCount = retryCount or 0
    local maxRetries = 3
    local retryDelay = 1 -- seconds between retries
    
    if state.isFetching then 
        --print("[Debug] Skipping fetch for page", page, "- already fetching")
        return 
    end
    
    local isPrefetch = not state.isInitialLoad and not callback
    
    if isPageCached(page) then
        --print("[Debug] Page", page, "found in cache, returning immediately")
        if callback then
            callback(state.pageCache[page])
        end
        return
    end
    
    state.isFetching = true
    --print("[Debug] Fetching page", page, isPrefetch and "(prefetch)" or "")

    local response = http.Get("https://cfg.lmao.mx/api/configs?p=" .. page)

    -- Test conditions
    --[[local response
    if page == 2 then
        -- JSON parse error test
        response = '{"this": "is", "invalid": json missing a bracket'
    elseif page == 3 then
        -- Network error test
        response = nil
    else
        response = http.Get("https://cfg.lmao.mx/api/configs?p=" .. page)
    end]]--
    
    -- Handle network failures
    if not response or response == "" then
        state.isFetching = false
        
        if retryCount < maxRetries then
            print(string.format("[Debug] Network request failed for page %d (attempt %d/%d) - retrying in %d seconds", 
                page, retryCount + 1, maxRetries, retryDelay))
                
            local retryId = string.format("retry_fetch_%d_%d_%s", page, retryCount, tostring(globals.RealTime()))
            callbacks.Register("Draw", retryId, function()
                if globals.RealTime() >= state.lastFetchTime + retryDelay then
                    callbacks.Unregister("Draw", retryId)
                    fetchPage(page, callback, retryCount + 1)
                end
            end)
        else
            print(string.format("[Error] Network request failed for page %d after %d attempts", page, retryCount + 1))
            if not isPrefetch then
                state.lastError = {
                    type = "network",
                    message = string.format("Failed to load page %d. Network error.", page),
                    page = page,
                    retries = retryCount + 1
                }
            end
        end
        return
    end
    
    -- Only try to parse if we have a response
    local parseSuccess, data = pcall(function() return decode_json(response) end)
    
    if not parseSuccess or not data then
        state.isFetching = false
        print(string.format("[Error] JSON parsing failed for page %d: Invalid response format", page))
        
        if not isPrefetch then
            state.lastError = {
                type = "parse",
                message = "Error loading page data. Invalid JSON format.",
                page = page,
                retries = retryCount + 1
            }
        end
        return
    end
    
    -- Clear any previous error state on successful fetch
    state.lastError = nil
    
    -- Version check should happen immediately after successful decode
    if data.apiVersion then
        state.serverVersion = data.apiVersion
        state.isVersionMismatch = (state.serverVersion ~= state.clientVersion)
        
        -- If version mismatch, clear configs and return
        if state.isVersionMismatch then
            state.configs = {}
            state.isFetching = false
            return
        end
    end
    
    local pageConfigs = {}
    if data.configs then
        for id, info in pairs(data.configs) do
            table.insert(pageConfigs, {
                id = id,
                description = info.description,
                createdAt = info.createdAt
            })
        end
        table.sort(pageConfigs, function(a, b)
            return a.createdAt > b.createdAt
        end)
    end
    
    -- Only update cache and state if versions match
    if not state.isVersionMismatch then
        state.pageCache[page] = pageConfigs
        --print("[Debug] Cached page", page)
        
        if state.isInitialLoad then
            if page == 0 then
                -- Initial load updates
                mergePaginationData(data, false)
                state.currentPage = 0
                state.configs = pageConfigs
                state.isInitialLoad = false
                if callback then callback(pageConfigs) end
                
                -- Setup prefetch with unique identifiers
                local prefetchCallbackName = "InitialPrefetch_" .. tostring(globals.RealTime())
                callbacks.Register("Draw", prefetchCallbackName, function()
                    --print("[Debug] Starting prefetch sequence")
                    fetchPage(1)
                    -- Use unique name for second prefetch
                    local secondPrefetchName = "Page2Prefetch_" .. tostring(globals.RealTime())
                    callbacks.Register("Draw", secondPrefetchName, function()
                        fetchPage(2)
                        callbacks.Unregister("Draw", secondPrefetchName)
                    end)
                    callbacks.Unregister("Draw", prefetchCallbackName)
                end)
            end
        else
            if not isPrefetch then
                mergePaginationData(data, false)
                state.currentPage = page
                state.configs = pageConfigs
                if callback then callback(pageConfigs) end
            end
        end
        
        -- Cache cleanup
        local cachePages = {}
        for k in pairs(state.pageCache) do
            table.insert(cachePages, k)
        end
        
        if #cachePages > state.CACHE_SIZE then
            table.sort(cachePages)
            local keepPages = {
                state.currentPage - 1,
                state.currentPage,
                state.currentPage + 1,
                state.currentPage + 2
            }
            for _, p in ipairs(cachePages) do
                if not table.includes(keepPages, p) then
                    state.pageCache[p] = nil
                    break
                end
            end
        end
    end
    
    state.isFetching = false
    --print("[Debug] Fetch complete for page", page)
end

-- Modify prefetchAdjacentPages to be more aggressive
prefetchAdjacentPages = function()
    local currentPage = state.currentPage
    
    -- Prefetch next two pages
    if currentPage < state.totalPages - 1 then
        if not isPageCached(currentPage + 1) then
            fetchPage(currentPage + 1)
        end
        if currentPage < state.totalPages - 2 and not isPageCached(currentPage + 2) then
            fetchPage(currentPage + 2)
        end
    end
    
    -- Prefetch previous page
    if currentPage > 0 and not isPageCached(currentPage - 1) then
        fetchPage(currentPage - 1)
    end
end

-- Modify navigateToPage to be more aggressive about prefetching
navigateToPage = function(newPage)
    if newPage < 0 or newPage >= state.totalPages then
        return
    end
    
    --print("[Debug] Navigating to page", newPage)
    
    -- Reset scroll offset when changing pages
    state.scrollOffset = 0
    
    if isPageCached(newPage) then
        --print("[Debug] Using cached page", newPage)
        state.currentPage = newPage
        state.configs = state.pageCache[newPage]
        
        -- Use unique name for navigation prefetch callback
        local navPrefetchName = "NavigationPrefetch_" .. tostring(globals.RealTime())
        callbacks.Register("Draw", navPrefetchName, function()
            prefetchAdjacentPages()
            callbacks.Unregister("Draw", navPrefetchName)
        end)
    else
        fetchPage(newPage, function(configs)
            state.currentPage = newPage
            state.configs = configs
            prefetchAdjacentPages()
        end)
    end
end

-- Helper function to check if value exists in table
function table.includes(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

-- Refresh function
refreshConfigs = function()
    if state.isInitialLoad then
        fetchPage(0)
    else
        if not isPageCached(state.currentPage) then
            fetchPage(state.currentPage, function(configs)
                state.configs = configs
            end)
        else
            state.configs = getCurrentPageConfigs()
        end
        prefetchAdjacentPages()
    end
end

-- Helper function to check if we should allow hover effects
local function shouldAllowHover()
    return state.interactionState ~= 'dragging' and 
           state.interactionState ~= 'scrolling' and
           not isDraggingScrollbar
end

-- Update handleCloseButton to use consistent hover check
local function handleCloseButton()
    local closeText = "×"
    local closeWidth = draw.GetTextSize(closeText)
    local closeX = state.windowX + state.windowWidth - closeWidth - 10
    local closeY = state.windowY + 8
    local closeButtonBounds = MouseInBounds(closeX - 5, closeY - 5, closeX + closeWidth + 5, closeY + 15)

    if closeButtonBounds and shouldAllowHover() then
        draw.Color(255, 100, 100, 255)
        if MouseReleased and state.clickStartedInMenu and (state.clickStartRegion == 'titlebar' or state.clickStartRegion == nil) then
            state.menuOpen = false
            return true
        end
    else
        draw.Color(255, 255, 255, 255)
    end
    draw.Text(closeX, closeY, closeText)
    return false
end

-- Update handleListItemClick to consider global interaction state
local function handleListItemClick(config, itemY, itemRight)
    -- Only consider hover if we're not dragging or scrolling
    local shouldAllowHover = state.interactionState ~= 'dragging' and state.interactionState ~= 'scrolling'
    local isHovered = shouldAllowHover and MouseInBounds(state.windowX, itemY, itemRight, itemY + state.itemHeight)

    if isHovered then
        if MouseReleased and state.clickStartedInMenu and state.clickStartRegion == 'list' then
            state.menuOpen = false
            client.Command("showconsole", true)
            client.Command("clear", true)
            client.Command(string.format('echo "%s"', config.id), true)
            return true
        end
        return false, true  -- Return isHovered as second parameter
    end
    return false, false
end

-- Update renderPaginationControls to use consistent hover check
local function renderPaginationControls()
    local footerY = math.floor(state.windowY + state.windowHeight - state.footerHeight)
    
    -- Draw footer background
    draw.Color(30, 30, 30, 255)
    draw.FilledRect(state.windowX, footerY, state.windowX + state.windowWidth, state.windowY + state.windowHeight)

    -- Draw version in bottom left corner
    draw.Color(100, 100, 100, 255)  -- Same grey as disabled buttons
    local versionText = string.format("%s", state.clientVersion)
    draw.Text(state.windowX + 10, footerY + 8, versionText)
    
    -- Calculate positions for perfect centering
    local centerX = math.floor(state.windowX + (state.windowWidth / 2))
    local pageText = string.format("Page %d of %d", state.currentPage + 1, state.totalPages)
    local pageTextWidth = draw.GetTextSize(pageText)
    local prevText = "< Prev"
    local nextText = "Next >"
    local prevWidth = draw.GetTextSize(prevText)
    local nextWidth = draw.GetTextSize(nextText)
    local totalWidth = prevWidth + pageTextWidth + nextWidth + 40
    
    local startX = math.floor(centerX - (totalWidth / 2))
    
    -- Previous page button
    local prevEnabled = state.currentPage > 0
    local prevX = math.floor(startX)
    local prevY = math.floor(footerY + 8)
    
    -- Draw prev button with consistent hover check
    if prevEnabled then
        local prevHovered = MouseInBounds(prevX, prevY, prevX + prevWidth, prevY + 15) and shouldAllowHover()
        if prevHovered then
            draw.Color(150, 150, 255, 255)
            if MouseReleased and state.clickStartedInMenu and (state.clickStartRegion == 'footer' or state.clickStartRegion == nil) then
                navigateToPage(state.currentPage - 1)
            end
        else
            draw.Color(255, 255, 255, 255)
        end
    else
        draw.Color(100, 100, 100, 255)
    end
    draw.Text(prevX, prevY, prevText)
    
    -- Center page counter text
    draw.Color(255, 255, 255, 255)
    local pageX = math.floor(startX + prevWidth + 20)
    draw.Text(pageX, math.floor(footerY + 8), pageText)
    
    -- Next page button
    local nextEnabled = state.currentPage < state.totalPages - 1
    local nextX = math.floor(startX + prevWidth + pageTextWidth + 40)
    local nextY = math.floor(footerY + 8)
    
    -- Draw next button with consistent hover check
    if nextEnabled then
        local nextHovered = MouseInBounds(nextX, nextY, nextX + nextWidth, nextY + 15) and shouldAllowHover()
        if nextHovered then
            draw.Color(150, 150, 255, 255)
            if MouseReleased and state.clickStartedInMenu and (state.clickStartRegion == 'footer' or state.clickStartRegion == nil) then
                navigateToPage(state.currentPage + 1)
            end
        else
            draw.Color(255, 255, 255, 255)
        end
    else
        draw.Color(100, 100, 100, 255)
    end
    draw.Text(nextX, nextY, nextText)
    
    -- Draw selection feedback for buttons, using consistent hover check
    if (prevEnabled or nextEnabled) and shouldAllowHover() then
        if MouseInBounds(prevX, prevY, prevX + prevWidth, prevY + 15) and prevEnabled then
            draw.Color(255, 255, 255, 50)
            draw.FilledRect(math.floor(prevX - 2), math.floor(prevY - 2), 
                          math.floor(prevX + prevWidth + 2), math.floor(prevY + 15))
        elseif MouseInBounds(nextX, nextY, nextX + nextWidth, nextY + 15) and nextEnabled then
            draw.Color(255, 255, 255, 50)
            draw.FilledRect(math.floor(nextX - 2), math.floor(nextY - 2), 
                          math.floor(nextX + nextWidth + 2), math.floor(nextY + 15))
        end
    end
end

-- Update drawConfigItem for consistency (though it was already working correctly)
local function drawConfigItem(config, itemY, hasScrollbar)
    local itemRight = state.windowX + state.windowWidth - (hasScrollbar and 16 or 0)
    
    -- Check hover with consistent logic
    local isHovered = MouseInBounds(state.windowX, itemY, itemRight, itemY + state.itemHeight) and shouldAllowHover()
    
    -- Draw item background with hover effect
    if isHovered then
        draw.Color(40, 40, 40, 255)
    else
        draw.Color(25, 25, 25, 255)
    end
    draw.FilledRect(state.windowX + 1, itemY, itemRight - 1, itemY + state.itemHeight - 1)
    
    -- Draw item text
    draw.Color(255, 255, 255, 255)
    local truncatedText = truncateText(config.description, state.windowWidth, hasScrollbar, isHovered, config.id)
    draw.Text(state.windowX + 10, itemY + 5, truncatedText)
    
    -- If hovering, draw the config ID
    if isHovered then
        local idText = getIdDisplayText(config.id)
        local descWidth = draw.GetTextSize(truncatedText)
        draw.Text(state.windowX + 10 + descWidth, itemY + 5, idText)
    end
    
    -- Handle clicks
    if isHovered and MouseReleased and state.clickStartedInMenu and state.clickStartRegion == 'list' then
        state.menuOpen = false
        client.Command("showconsole", true)
        client.Command("clear", true)
        client.Command(string.format('echo "%s"', config.id), true)
        return true
    end
    
    return false
end

-- Modified renderWindow function with clear version mismatch display
local function renderEmptyState(contentStart, contentEnd)
    draw.Color(180, 180, 180, 255)  -- Slightly gray color that blends well
    local message = state.isVersionMismatch and "Please update script" or "(╥﹏╥)"
    local textWidth = draw.GetTextSize(message)
    local contentWidth = state.windowWidth
    local contentHeight = contentEnd - contentStart
    
    -- Calculate center position
    local centerX = state.windowX + math.floor((contentWidth - textWidth) / 2)
    local centerY = contentStart + math.floor((contentHeight - 15) / 2)  -- 15 is approximate text height
    
    -- Debug info
    if state.isVersionMismatch then
        local debugInfo = string.format("Client: %s, Server: %s", 
            state.clientVersion or "unknown", 
            state.serverVersion or "unknown")
        local debugWidth = draw.GetTextSize(debugInfo)
        local debugX = state.windowX + math.floor((contentWidth - debugWidth) / 2)
        draw.Text(debugX, centerY + 20, debugInfo)
    end
    
    draw.Text(centerX, centerY, message)
end

-- Function to render window with list of configs
local function renderWindow()
    -- Update window height based on current number of items
    state.windowHeight = calculateWindowHeight()
    
    -- Update mouse state and check if we should skip processing
    if UpdateMouseState() then
        return
    end

    -- Handle dragging - only if started in title bar
    if isDragging then
        if input.IsButtonDown(MOUSE_LEFT) and state.clickStartedInTitleBar then
            local mouseX, mouseY = GetMousePos()
            state.windowX = mouseX - dragOffsetX
            state.windowY = mouseY - dragOffsetY
        else
            isDragging = false
            state.interactionState = 'none'
            state.clickStartedInTitleBar = false
        end
    elseif state.clickStartedInTitleBar and not isDragging and input.IsButtonDown(MOUSE_LEFT) then
        local mouseX, mouseY = GetMousePos()
        dragOffsetX = mouseX - state.windowX
        dragOffsetY = mouseY - state.windowY
        isDragging = true
        state.interactionState = 'dragging'
    end
    
    -- Draw window border
    draw.Color(50, 50, 50, 255)
    draw.OutlinedRect(state.windowX - 1, state.windowY - 1, state.windowX + state.windowWidth + 1, state.windowY + state.windowHeight + 1)
    
    -- Background
    draw.Color(20, 20, 20, 255)
    draw.FilledRect(state.windowX, state.windowY, state.windowX + state.windowWidth, state.windowY + state.windowHeight)
    
    -- Title bar
    draw.Color(30, 30, 30, 255)
    draw.FilledRect(state.windowX, state.windowY, state.windowX + state.windowWidth, state.windowY + state.titleBarHeight)
    
    -- Title text
    draw.Color(255, 255, 255, 255)
    local titleText = string.format("Config Browser - %s", getUname())
    local titleWidth = draw.GetTextSize(titleText)
    draw.Text(state.windowX + 10, state.windowY + 8, titleText)
    
    -- Handle close button using helper function
    if handleCloseButton() then
        return
    end
    
    -- Calculate content area
    local contentStart = state.windowY + state.titleBarHeight
    local contentEnd = state.windowY + state.windowHeight - state.footerHeight
    local contentHeight = contentEnd - contentStart
    local visibleItems = math.floor(contentHeight / state.itemHeight)
    local maxScroll = math.max(0, #state.configs - visibleItems)
    state.scrollOffset = math.min(state.scrollOffset, maxScroll)
    
    -- Handle scrolling (update bounds check)
    if state.interactionState ~= 'dragging' and MouseInBounds(state.windowX, contentStart, state.windowX + state.windowWidth, contentEnd) then
        local currentTime = globals.RealTime()
        if currentTime - lastScrollTime >= SCROLL_DELAY then
            if input.IsButtonPressed(MOUSE_WHEEL_UP) and state.scrollOffset > 0 then
                state.scrollOffset = state.scrollOffset - 1
                lastScrollTime = currentTime
            elseif input.IsButtonPressed(MOUSE_WHEEL_DOWN) and state.scrollOffset < maxScroll then
                state.scrollOffset = state.scrollOffset + 1
                lastScrollTime = currentTime
            end
        end
    end

    -- Show sad kaomoji if no items to display
    renderEmptyState(contentStart, contentEnd)

    -- Draw config items (update item rendering to respect footer)
    for i = 1, visibleItems do
        local configIndex = i + state.scrollOffset
        local config = state.configs[configIndex]
        if config then
            local itemY = contentStart + (i-1) * state.itemHeight
            -- Don't render items that would overlap with footer
            if itemY + state.itemHeight <= contentEnd then
                -- Determine if scrollbar is needed
                local hasScrollbar = #state.configs > visibleItems
                drawConfigItem(config, itemY, hasScrollbar, isHovered)
            end
        end
    end
    
    -- Update scrollbar to respect footer
    if #state.configs > visibleItems then
        local scrollbarWidth = 16
        local scrollbarHeight = contentHeight
        local thumbHeight = math.floor(math.max(20, (visibleItems / #state.configs) * scrollbarHeight))
        local thumbPosition = math.floor((state.scrollOffset / (#state.configs - visibleItems)) * (scrollbarHeight - thumbHeight))
        
        -- Scrollbar track and thumb positions
        local scrollbarX = math.floor(state.windowX + state.windowWidth - scrollbarWidth)
        local scrollbarRight = math.floor(state.windowX + state.windowWidth)
        local thumbTop = math.floor(contentStart + thumbPosition)
        local thumbBottom = math.floor(contentStart + thumbPosition + thumbHeight)
        
        -- Check hover state
        local isHoveringScrollbar = MouseInBounds(
            scrollbarX,
            contentStart,
            scrollbarRight,
            contentEnd
        ) and shouldAllowHover()
        
        -- Draw scrollbar background (track)
        if isHoveringScrollbar then
            draw.Color(50, 50, 50, 255)  -- Lighter background when hovering
        else
            draw.Color(40, 40, 40, 255)  -- Default background
        end
        draw.FilledRect(
            scrollbarX,
            math.floor(contentStart),
            scrollbarRight,
            math.floor(contentEnd)
        )
        
        -- Draw scrollbar thumb with hover effect
        local isHoveringThumb = MouseInBounds(
            scrollbarX,
            thumbTop,
            scrollbarRight,
            thumbBottom
        ) and shouldAllowHover()
        
        if isDraggingScrollbar then
            draw.Color(120, 120, 120, 255)  -- Active/dragging color
        elseif isHoveringThumb then
            draw.Color(100, 100, 100, 255)  -- Hover color
        else
            draw.Color(80, 80, 80, 255)     -- Default color
        end
        
        -- Draw thumb with rounded corners
        draw.FilledRect(
            scrollbarX,
            thumbTop,
            scrollbarRight,
            thumbBottom
        )
        
        -- Handle scrollbar dragging (update bounds)
        if state.interactionState == 'scrolling' then
            if input.IsButtonDown(MOUSE_LEFT) then
                local mouseY = math.floor(input.GetMousePos()[2])
                local scrollableHeight = scrollbarHeight - thumbHeight
                local relativeY = math.max(0, math.min(mouseY - contentStart - math.floor(thumbHeight/2), scrollableHeight))
                state.scrollOffset = math.floor((relativeY / scrollableHeight) * (#state.configs - visibleItems))
                isDraggingScrollbar = true
                wasScrollbarDragging = true
            else
                isDraggingScrollbar = false
                state.interactionState = 'none'
                MouseReleased = false
            end
        elseif state.clickStartedInScrollbar and not isDraggingScrollbar and input.IsButtonDown(MOUSE_LEFT) then
            isDraggingScrollbar = true
            state.interactionState = 'scrolling'
            wasScrollbarDragging = true
        end
    end
    renderPaginationControls()
end

-- Helper function to print styled messages
local function printStyledMessage(message, isError)
    print("\n----------------------------------------")
    if isError then
        print("ERROR: " .. message)
    else
        print(message)
    end
    print("----------------------------------------")
end

-- Handler for config_add command 
local function handleConfigAdd(cmd)
    local configId, description = cmd:match("^config_add%s+\"([^:]+):([^\"]+)\"")
    if not configId or not description then
        print("Usage: config_add \"code:description\"")
        return
    end
    
    local uname = getUname()
    local url = string.format("https://cfg.lmao.mx/api/configs?id=%s&desc=%s&uname=%s", 
        configId, description, uname)
    
    client.Command("clear", true)
    local response = http.Get(url)
    
    if response then
        -- Queue the response to be printed after delay
        table.insert(responseQueue, {
            text = response,  -- Print raw response (ASCII art captcha)
            printTime = globals.RealTime() + PRINT_DELAY,
            onPrint = function()
                -- Only show captcha instructions if response contains enough # characters to be ASCII art
                local hashCount = 0
                for hash in response:gmatch("#") do
                    hashCount = hashCount + 1
                    if hashCount >= 10 then
                        break
                    end
                end
                
                if hashCount >= 10 then
                    state.pendingCaptcha = true
                    state.captchaExpiry = globals.RealTime() + 60
                    state.pendingConfigId = configId
                    state.pendingConfigDesc = description
                    state.pendingUname = uname
                    
                    -- Print clear captcha instructions after the ASCII art
                    printStyledMessage([[
Please enter the captcha shown above using:
captcha "XXXXX"

Replace XXXXX with the characters you see in the ASCII art.
You have 60 seconds to complete this captcha.]])
                end
            end
        })
    end
end

-- Handler for captcha command
local function handleCaptcha(cmd)
    local captcha = cmd:match("^captcha%s+\"([^\"]+)\"")
    if not captcha then
        print("Usage: captcha \"XXXXX\" (replace XXXXX with the characters you see in the ASCII art)")
        return
    end
    
    if not state.pendingCaptcha or globals.RealTime() > state.captchaExpiry then
        printStyledMessage("No active captcha request or captcha has expired. Please try adding your config again.", true)
        return
    end
    
    local url = string.format("https://cfg.lmao.mx/api/configs?id=%s&desc=%s&uname=%s&captcha=%s",
        state.pendingConfigId,
        state.pendingConfigDesc,
        state.pendingUname,
        captcha)
        
    client.Command("clear", true)
    local response = http.Get(url)
    
    if response then
        -- Queue the response with both raw output and any additional messages
        table.insert(responseQueue, {
            text = response,  -- Print raw response
            printTime = globals.RealTime() + PRINT_DELAY,
            onPrint = function()
                if response == "Success" then
                    state.pendingCaptcha = nil
                    state.pageCache = {}
                    state.configs = {}
                    state.isInitialLoad = true
                    refreshConfigs()
                elseif response == "Config string already exists" then
                    state.pendingCaptcha = nil  -- Clear captcha state since it was valid
                    --printStyledMessage("This config has already been added to the database.")
                else
                    state.captchaExpiry = globals.RealTime() + 60
                    printStyledMessage("Invalid captcha! Please try again with the characters you see in the ASCII art.")
                end
            end
        })
    end
end

-- Add cleanup function definition for script unloading
local function cleanup()
    -- Re-enable mouse input if it was disabled
    input.SetMouseInputEnabled()
    
    -- Restore console state if needed
    if not conWasOpen and engine.Con_IsVisible() then
        client.Command("hideconsole", 1)
    end
    
    -- Reset all state variables
    state.menuOpen = false
    state.clickStartedInMenu = false
    state.clickStartedInTitleBar = false
    state.clickStartedInScrollbar = false
    state.interactionState = 'none'
    state.clickStartRegion = nil
    isDragging = false
    isDraggingScrollbar = false
    wasScrollbarDragging = false
    
    -- Clear any pending captcha state
    state.pendingCaptcha = nil
    state.captchaExpiry = 0
    state.pendingConfigId = nil
    state.pendingConfigDesc = nil
    state.pendingUname = nil
    
    -- Clear cache
    state.pageCache = {}
    state.configs = {}
    state.isInitialLoad = true

    -- Reset hash cache and check time
    cachedHash = nil
    lastKnownName = nil
    lastCheckTime = 0
end


-- Main draw callback
callbacks.Register("Draw", function()
    -- Check if we're in main menu
    state.consoleState.inMainMenu = engine.IsGameUIVisible()
    
    -- Process any queued responses first
    for i = #responseQueue, 1, -1 do
        local item = responseQueue[i]
        if globals.RealTime() >= item.printTime then
            print(item.text)
            if item.onPrint then
                item.onPrint()
            end
            table.remove(responseQueue, i)
        end
    end

    -- Keep mouse disabled and console hidden while menu is open
    if state.menuOpen then
        input.SetMouseInputEnabled("false")
        if engine.Con_IsVisible() then
            state.consoleState.wasOpen = true
            client.Command("hideconsole", 1)
        end
    else
        -- Enable mouse when menu is closed
        input.SetMouseInputEnabled()
        
        -- Handle pending console restore
        if state.consoleState.wasOpen and not state.consoleState.pendingRestore then
            state.consoleState.pendingRestore = true
        end
        
        -- Only restore console if we're in main menu and have a pending restore
        if state.consoleState.pendingRestore and state.consoleState.inMainMenu then
            client.Command("showconsole", 1)
            state.consoleState.pendingRestore = false
            state.consoleState.wasOpen = false
        end
    end

    -- Handle menu toggling
    local currentKeyState = input.IsButtonDown(KEY_DELETE)
    if currentKeyState and not lastKeyState then
        state.menuOpen = not state.menuOpen
        state.clickStartedInMenu = false
        state.clickStartedInTitleBar = false
        state.clickStartedInScrollbar = false
        state.interactionState = 'none'
        isDragging = false
        isDraggingScrollbar = false
        wasScrollbarDragging = false
        
        if not state.menuOpen then
            refreshConfigs()
        end
    end
    lastKeyState = currentKeyState
    
    if state.menuOpen then
        updateFont()
        renderWindow()
    end
end)

-- Register cleanup for script unload only
callbacks.Register("Unload", function()
    cleanup()
    
    -- Restore original UI scale factor if it was changed
    if originalScaleFactor ~= 1 then
        client.SetConVar("vgui_ui_scale_factor", tostring(originalScaleFactor))
    end
    
    print("Config Browser unloaded")
end)

-- Command handling
callbacks.Register("SendStringCmd", function(cmd)
    local command = cmd:Get()

    if command:match("^config_menu") then
        if state.menuOpen then
            state.menuOpen = false
        else
            state.menuOpen = true
        end
        return
    end

    if command:match("^config_add") then
        handleConfigAdd(command)
        cmd:Set("")
        return
    end
    
    if command:match("^captcha") then
        handleCaptcha(command)
        cmd:Set("")
        return
    end
end)

-- Initialize immediately when script loads
refreshConfigs()
local sw, sh = draw.GetScreenSize()
state.windowX = math.floor((sw - state.windowWidth) / 2)
state.windowY = math.floor((sh - state.windowHeight) / 2)
state.menuOpen = true -- Start with menu open
state.windowHeight = calculateWindowHeight() -- Set initial height

-- Block input initially
local conWasOpen = engine.Con_IsVisible()
if conWasOpen then
    client.Command("hideconsole", 1)
    conWasOpen = false
end
input.SetMouseInputEnabled("false") -- Block input initially

LastMouseState = input.IsButtonDown(MOUSE_LEFT)  -- Record initial state
MouseReleased = false  -- Force no release on first frame
hasSeenMousePress = false  -- Haven't seen a proper press cycle yet
print("Config Browser loaded! Press DEL to open/close or use 'config_menu'")
print("Use 'config_add \"code:description\"' to add configs")
print("Use 'captcha \"XXXXX\"' to complete captcha verification")
