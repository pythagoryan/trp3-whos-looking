-- ============================================================================
-- Addon Setup
-- ============================================================================
local ADDON_NAME, addon = ...
local frame = nil
addon.debugSelf = false
addon.version = "1.2.2"

-- Default settings and saved variables
WhosLookingDB = WhosLookingDB or {
    pos = { x = 250, y = -250 },
    size = { width = 220, height = 250 },
}

-- Core data table
local targetingPlayers = {}
local namePool = {}

-- ============================================================================
-- Forward Declarations
-- ============================================================================
local UpdateDisplay
local CheckAllNameplates
local OpenTRP3Profile

-- ============================================================================
-- UI Creation
-- ============================================================================
function addon:CreateFrames()
    if frame then return end

    frame = CreateFrame("Frame", "TRP3WhosLookingFrame", UIParent, "BackdropTemplate")
    
    if not WhosLookingDB.pos or type(WhosLookingDB.pos.x) ~= "number" then
        WhosLookingDB.pos = { x = 250, y = -250 }
    end
    if not WhosLookingDB.size or type(WhosLookingDB.size.width) ~= "number" then
        WhosLookingDB.size = { width = 220, height = 250 }
    end
    
    frame:SetSize(WhosLookingDB.size.width, WhosLookingDB.size.height)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", WhosLookingDB.pos.x, WhosLookingDB.pos.y)

    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetBackdrop({
        bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16, tile = true, tileSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    header:SetHeight(28)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        WhosLookingDB.pos.x = frame:GetLeft()
        WhosLookingDB.pos.y = frame:GetTop() - UIParent:GetTop()
    end)
    
    local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("CENTER", header)
    title:SetText("Who's Looking?")
    frame.title = title

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", 0, 0)
    resizeHandle:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizeHandle:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    
    frame:SetScript("OnSizeChanged", function(self, width, height)
        local minWidth, minHeight = 180, 100
        if width < minWidth then self:SetWidth(minWidth) end
        if height < minHeight then self:SetHeight(minHeight) end
        WhosLookingDB.size.width = self:GetWidth()
        WhosLookingDB.size.height = self:GetHeight()
        if UpdateDisplay then UpdateDisplay() end
    end)

    frame.lines = {}
    for i = 1, 15 do
        local line = CreateFrame("Button", nil, frame)
        line:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
        
        local fontString = line:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        fontString:SetAllPoints(true)
        fontString:SetJustifyH("LEFT")
        line.fontString = fontString

        -- Reverted to a simple OnClick script for the only desired action.
        line:SetScript("OnClick", function(self)
            if self.realName then
                OpenTRP3Profile(self.realName)
            end
        end)

        line:Hide()
        frame.lines[i] = line
    end
    
    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(90, 22)
    clearButton:SetPoint("BOTTOMLEFT", 5, 5)
    clearButton:SetText("Clear Recent")
    clearButton:SetScript("OnClick", function()
        local playersToKeep = {}
        for name, data in pairs(targetingPlayers) do
            if data.isTargeting then
                playersToKeep[name] = data
            end
        end
        targetingPlayers = playersToKeep
        UpdateDisplay()
    end)
    frame.clearButton = clearButton
    
    frame:Show()
end

-- ============================================================================
-- Core Logic
-- ============================================================================
function OpenTRP3Profile(realName)
    local fullName = realName
    if not string.find(fullName, "-") then
        local _, englishRealm = GetRealmName()
        if englishRealm and englishRealm ~= "" then
            fullName = fullName .. "-" .. englishRealm:gsub(" ", "")
        else
            fullName = fullName .. "-" .. GetRealmName():gsub(" ", "")
        end
    end
    
    local command = "/trp3 open " .. fullName
    ChatFrame_OpenChat(command)
    C_Timer.After(0.1, function()
        ChatEdit_SendText(ChatEdit_GetActiveWindow())
    end)
end

function GetDisplayName(unit, realName)
    if TRP3_API and TRP3_API.chat and TRP3_API.chat.getFullnameForUnitUsingChatMethod and TRP3_API.utils and TRP3_API.utils.str and TRP3_API.utils.str.getUnitID then
        local trpName = TRP3_API.chat.getFullnameForUnitUsingChatMethod(TRP3_API.utils.str.getUnitID(unit))
        if trpName and trpName ~= "" then return trpName end
    end
    return realName
end

function UpdateDisplay()
    if not frame or not frame:IsShown() then return end
    
    local hasRecentPlayers = false
    for name, data in pairs(targetingPlayers) do
        if not data.isTargeting then hasRecentPlayers = true; break; end
    end

    if hasRecentPlayers then frame.clearButton:Show() else frame.clearButton:Hide() end

    table.wipe(namePool)
    for name, data in pairs(targetingPlayers) do table.insert(namePool, data) end
    table.sort(namePool, function(a, b)
        if a.isPlayer and not b.isPlayer then return true end
        if not a.isPlayer and b.isPlayer then return false end
        if a.isTargeting ~= b.isTargeting then return a.isTargeting end
        return a.lastSeen > b.lastSeen
    end)

    for _, line in ipairs(frame.lines) do line:Hide() end

    local topPadding = 28 
    local bottomPadding = hasRecentPlayers and 30 or 8
    
    for i, data in ipairs(namePool) do
        if frame.lines[i] then
            local line = frame.lines[i]
            line:SetSize(frame:GetWidth() - 16, 16)
            
            if data.class and RAID_CLASS_COLORS[data.class] then
                local color = RAID_CLASS_COLORS[data.class]
                line.fontString:SetTextColor(color.r, color.g, color.b)
            end
            
            local statusText = ""
            if data.isPlayer then statusText = " |cff00ff00(You)|r"
            elseif not data.isTargeting then statusText = " |cff808080(recent)|r" end
            line.fontString:SetText(data.displayName .. statusText)
            line.realName = data.realName
            
            line:ClearAllPoints()
            if i == 1 then
                line:SetPoint("TOPLEFT", 8, -topPadding)
            else
                line:SetPoint("TOPLEFT", frame.lines[i-1], "BOTTOMLEFT", 0, -2)
            end
            line:Show()
        end
    end

    -- Auto-resize window height to fit visible lines (up to a max)
    local visibleLines = math.min(#namePool, #frame.lines)
    local lineHeight = 18 -- Slightly more than font for spacing
    local headerHeight = 28
    local bottomPadding = hasRecentPlayers and 30 or 8
    local minHeight = 100
    local maxHeight = 400 -- Set your preferred max height

    local neededHeight = headerHeight + bottomPadding + (visibleLines * lineHeight)
    neededHeight = math.max(minHeight, math.min(neededHeight, maxHeight))
    frame:SetHeight(neededHeight)
end

function AddOrUpdatePlayer(realName, displayName, unit, isPlayer)
    local guid = UnitGUID(unit)
    if not guid then return end
    local _, class = GetPlayerInfoByGUID(guid)
    targetingPlayers[realName] = {
        realName = realName,
        displayName = displayName,
        unit = unit,
        isTargeting = true,
        lastSeen = GetTime(),
        class = class or "PRIEST",
        isPlayer = isPlayer or false,
    }
end

function CheckAllNameplates()
    if targetingPlayers[UnitName("player")] and targetingPlayers[UnitName("player")].isPlayer then
        targetingPlayers[UnitName("player")] = nil
    end

    if addon.debugSelf then
        local realName = UnitName("player")
        local displayName = GetDisplayName("player", realName)
        AddOrUpdatePlayer(realName, displayName, "player", true)
    end

    local currentlyTargeting = {}
    for _, npFrame in ipairs(C_NamePlate.GetNamePlates()) do
        if npFrame and npFrame:IsShown() and npFrame.namePlateUnitToken then
            local unit = npFrame.namePlateUnitToken
            if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") and UnitIsUnit(unit .. "target", "player") then
                local realName = UnitName(unit)
                local displayName = GetDisplayName(unit, realName)
                currentlyTargeting[realName] = true
                AddOrUpdatePlayer(realName, displayName, unit, false)
            end
        end
    end

    for name, data in pairs(targetingPlayers) do
        if not data.isPlayer and data.isTargeting and not currentlyTargeting[name] then
            data.isTargeting = false
            data.lastSeen = GetTime()
        end
    end

    for name, data in pairs(targetingPlayers) do
        if not data.isPlayer and not data.isTargeting and (GetTime() - data.lastSeen) > 300 then
            targetingPlayers[name] = nil
        end
    end
    
    UpdateDisplay()
end

-- ============================================================================
-- Event Handling & Init
-- ============================================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        addon:CreateFrames()
        C_Timer.NewTicker(1.5, CheckAllNameplates)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        C_Timer.After(0.2, CheckAllNameplates)
    end
end)

SLASH_WHOSLOOKING1 = "/wl"
SlashCmdList["WHOSLOOKING"] = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "reset" then
        WhosLookingDB = nil
        print(ADDON_NAME .. ": Settings have been wiped. Reloading UI...")
        ReloadUI()
    elseif msg == "hide" then
        if frame then frame:Hide() end
    elseif msg == "debugself" then
        addon.debugSelf = not addon.debugSelf
        print(ADDON_NAME .. ": Debug Self is now " .. (addon.debugSelf and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        CheckAllNameplates()
    else
        if not frame then addon:CreateFrames() end
        frame:Show()
    end
end

print(ADDON_NAME .. " v" .. addon.version .. " loaded. Made by Woodchippa - Moon Guard. Thank you for your support. <3")