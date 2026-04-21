--[[
MethlBroadcast
World of Warcraft 3.3.5 addon for broadcasting a custom message on a repeating timer.
]]

local ADDON_NAME = ...
local MethlBroadcast = {}

-- Default settings used to initialize missing SavedVariables keys.
local DEFAULTS = {
    message = "",
    savedMessages = {},
    channels = {
        general = true,
        lfg = false,
        world = false,
    },
    worldChannelName = "World",
    intervalPreset = "60",
    customInterval = 180,
}

-- Runtime state.
MethlBroadcast.db = nil
MethlBroadcast.isBroadcasting = false
MethlBroadcast.elapsed = 0
MethlBroadcast.selectedSavedIndex = nil
MethlBroadcast.missingChannelWarnings = {}
MethlBroadcast.intervalButtons = {}

-- Utility: print with addon prefix.
local function PrintMessage(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[MethlBroadcast]|r " .. msg)
    end
end

-- Utility: basic trim helper compatible with Lua 5.1.
local function TrimString(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Utility: apply defaults recursively for missing keys only.
local function ApplyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

-- Resolve current interval in seconds based on selected preset/custom input.
function MethlBroadcast:GetCurrentInterval()
    if self.db.intervalPreset == "custom" then
        local custom = tonumber(self.customIntervalEditBox and self.customIntervalEditBox:GetText() or self.db.customInterval)
        custom = custom or self.db.customInterval or 10
        custom = math.floor(custom)
        if custom < 10 then
            custom = 10
        end
        self.db.customInterval = custom
        if self.customIntervalEditBox then
            self.customIntervalEditBox:SetText(tostring(custom))
        end
        return custom
    end

    return tonumber(self.db.intervalPreset) or 60
end

-- Refresh interval button visual states.
function MethlBroadcast:UpdateIntervalButtons()
    for key, button in pairs(self.intervalButtons) do
        if self.db.intervalPreset == key then
            button:SetButtonState("PUSHED", true)
            button:LockHighlight()
        else
            button:SetButtonState("NORMAL")
            button:UnlockHighlight()
        end
    end

    local showCustom = self.db.intervalPreset == "custom"
    if showCustom then
        self.customIntervalLabel:Show()
        self.customIntervalEditBox:Show()
    else
        self.customIntervalLabel:Hide()
        self.customIntervalEditBox:Hide()
    end
end

-- Refresh start/stop button visuals and status line.
function MethlBroadcast:UpdateStatusDisplay()
    if self.isBroadcasting then
        self.startStopButton:SetText("Stop Broadcasting")
        self.startStopButton:GetFontString():SetTextColor(1.0, 0.2, 0.2)
        self.statusText:SetText("Status: Broadcasting every " .. tostring(self:GetCurrentInterval()) .. "s")
    else
        self.startStopButton:SetText("Start Broadcasting")
        self.startStopButton:GetFontString():SetTextColor(0.2, 1.0, 0.2)
        self.statusText:SetText("Status: Stopped")
    end
end

-- Build the list of channels to send to. Missing channels are skipped with one-time warnings.
function MethlBroadcast:GetTargetChannels()
    local channels = {}

    if self.db.channels.general then
        local generalNum = GetChannelName("General")
        if generalNum and generalNum > 0 then
            table.insert(channels, { label = "General", number = 1 })
        elseif not self.missingChannelWarnings.general then
            PrintMessage("Warning: General channel not found or not joined.")
            self.missingChannelWarnings.general = true
        end
    end

    if self.db.channels.lfg then
        local lfgNum = GetChannelName("LookingForGroup")
        if lfgNum and lfgNum > 0 then
            table.insert(channels, { label = "LFG", number = lfgNum })
        elseif not self.missingChannelWarnings.lfg then
            PrintMessage("Warning: LookingForGroup channel not found or not joined.")
            self.missingChannelWarnings.lfg = true
        end
    end

    if self.db.channels.world then
        local worldName = TrimString(self.db.worldChannelName)
        if worldName == "" then
            worldName = "World"
        end

        local worldNum = GetChannelName(worldName)
        if worldNum and worldNum > 0 then
            table.insert(channels, { label = worldName, number = worldNum })
        elseif not self.missingChannelWarnings[worldName] then
            PrintMessage("Warning: World channel '" .. worldName .. "' not found or not joined.")
            self.missingChannelWarnings[worldName] = true
        end
    end

    return channels
end

-- Send the broadcast message to all currently available selected channels.
function MethlBroadcast:BroadcastNow()
    local msg = TrimString(self.db.message)
    if msg == "" then
        return
    end

    local targets = self:GetTargetChannels()
    local sentNames = {}

    for _, target in ipairs(targets) do
        SendChatMessage(msg, "CHANNEL", nil, target.number)
        table.insert(sentNames, target.label)
    end

    if #sentNames > 0 then
        PrintMessage("Sent to: " .. table.concat(sentNames, ", "))
    end
end

-- Validate user input and start the repeating ticker.
function MethlBroadcast:StartBroadcasting()
    local msg = TrimString(self.messageEditBox:GetText())
    if msg == "" then
        PrintMessage("Error: Message cannot be empty.")
        return
    end

    if not (self.db.channels.general or self.db.channels.lfg or self.db.channels.world) then
        PrintMessage("Error: Select at least one channel.")
        return
    end

    self.db.message = msg
    self.elapsed = 0
    self.isBroadcasting = true
    self.missingChannelWarnings = {}
    self:UpdateStatusDisplay()
end

-- Stop the repeating ticker.
function MethlBroadcast:StopBroadcasting()
    self.isBroadcasting = false
    self.elapsed = 0
    self:UpdateStatusDisplay()
end

-- Add current edit box message to saved list (deduplicated, max 20 entries).
function MethlBroadcast:SaveCurrentMessage()
    local text = TrimString(self.messageEditBox:GetText())
    if text == "" then
        PrintMessage("Error: Cannot save an empty message.")
        return
    end

    local existingIndex = nil
    for i, value in ipairs(self.db.savedMessages) do
        if value == text then
            existingIndex = i
            break
        end
    end

    if existingIndex then
        self.selectedSavedIndex = existingIndex
        UIDropDownMenu_SetSelectedID(self.savedDropdown, existingIndex)
        PrintMessage("Message already exists in saved list.")
        return
    end

    table.insert(self.db.savedMessages, text)
    if #self.db.savedMessages > 20 then
        table.remove(self.db.savedMessages, 1)
    end

    self.selectedSavedIndex = #self.db.savedMessages
    UIDropDownMenu_Initialize(self.savedDropdown, function() MethlBroadcast:InitializeSavedDropdown() end)
    UIDropDownMenu_SetSelectedID(self.savedDropdown, self.selectedSavedIndex)
    PrintMessage("Message saved.")
end

-- Delete selected saved message entry.
function MethlBroadcast:DeleteSelectedMessage()
    if not self.selectedSavedIndex or not self.db.savedMessages[self.selectedSavedIndex] then
        PrintMessage("Error: No saved message selected.")
        return
    end

    table.remove(self.db.savedMessages, self.selectedSavedIndex)
    self.selectedSavedIndex = nil
    UIDropDownMenu_Initialize(self.savedDropdown, function() MethlBroadcast:InitializeSavedDropdown() end)
    UIDropDownMenu_SetSelectedID(self.savedDropdown, nil)
    UIDropDownMenu_SetText(self.savedDropdown, "Select a saved message")
    PrintMessage("Saved message deleted.")
end

-- Populate Saved Messages dropdown.
function MethlBroadcast:InitializeSavedDropdown()
    local info = UIDropDownMenu_CreateInfo()

    if #self.db.savedMessages == 0 then
        info.text = "(No saved messages)"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        return
    end

    for i, message in ipairs(self.db.savedMessages) do
        local truncated = message
        if string.len(truncated) > 60 then
            truncated = string.sub(truncated, 1, 57) .. "..."
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = truncated
        info.notCheckable = true
        info.func = function()
            MethlBroadcast.selectedSavedIndex = i
            MethlBroadcast.messageEditBox:SetText(message)
            MethlBroadcast.db.message = message
            UIDropDownMenu_SetSelectedID(MethlBroadcast.savedDropdown, i)
        end
        UIDropDownMenu_AddButton(info)
    end
end

-- Create the full addon UI.
function MethlBroadcast:CreateUI()
    if self.frame then
        return
    end

    -- Main panel frame.
    local frame = CreateFrame("Frame", "MethlBroadcastMainFrame", UIParent)
    frame:SetWidth(460)
    frame:SetHeight(420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(selfFrame) selfFrame:StartMoving() end)
    frame:SetScript("OnDragStop", function(selfFrame) selfFrame:StopMovingOrSizing() end)
    frame:Hide()
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    self.frame = frame

    -- Title bar text.
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -12)
    title:SetText("MethlBroadcast")

    -- Close button.
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    -- Message section label.
    local messageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
    messageLabel:SetText("Broadcast Message:")

    -- Scrollable multi-line message input.
    local messageScroll = CreateFrame("ScrollFrame", "MethlBroadcastMessageScroll", frame, "UIPanelScrollFrameTemplate")
    messageScroll:SetPoint("TOPLEFT", messageLabel, "BOTTOMLEFT", 0, -8)
    messageScroll:SetWidth(426)
    messageScroll:SetHeight(120)

    local messageEditBox = CreateFrame("EditBox", "MethlBroadcastMessageEditBox", messageScroll)
    messageEditBox:SetMultiLine(true)
    messageEditBox:SetAutoFocus(false)
    messageEditBox:SetFontObject(ChatFontNormal)
    messageEditBox:SetWidth(398)
    messageEditBox:SetScript("OnTextChanged", function(selfBox)
        MethlBroadcast.db.message = selfBox:GetText() or ""
        local _, height = selfBox:GetTextBounds()
        selfBox:SetHeight(math.max(120, height + 20))
        messageScroll:UpdateScrollChildRect()
    end)
    messageEditBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    messageScroll:SetScrollChild(messageEditBox)
    messageEditBox:SetText(self.db.message or "")
    self.messageEditBox = messageEditBox

    -- Save message button.
    local saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveButton:SetPoint("TOPLEFT", messageScroll, "BOTTOMLEFT", 0, -10)
    saveButton:SetWidth(120)
    saveButton:SetHeight(24)
    saveButton:SetText("Save Message")
    saveButton:SetScript("OnClick", function()
        MethlBroadcast:SaveCurrentMessage()
    end)

    -- Saved messages dropdown.
    local savedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    savedLabel:SetPoint("TOPLEFT", saveButton, "BOTTOMLEFT", 0, -12)
    savedLabel:SetText("Saved Messages:")

    local savedDropdown = CreateFrame("Frame", "MethlBroadcastSavedDropdown", frame, "UIDropDownMenuTemplate")
    savedDropdown:SetPoint("TOPLEFT", savedLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(savedDropdown, 230)
    UIDropDownMenu_SetButtonWidth(savedDropdown, 245)
    UIDropDownMenu_SetText(savedDropdown, "Select a saved message")
    UIDropDownMenu_Initialize(savedDropdown, function() MethlBroadcast:InitializeSavedDropdown() end)
    self.savedDropdown = savedDropdown

    -- Delete saved button.
    local deleteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteButton:SetPoint("LEFT", savedDropdown, "RIGHT", -8, 2)
    deleteButton:SetWidth(110)
    deleteButton:SetHeight(24)
    deleteButton:SetText("Delete Saved")
    deleteButton:SetScript("OnClick", function()
        MethlBroadcast:DeleteSelectedMessage()
    end)

    -- Channel section label.
    local channelsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelsLabel:SetPoint("TOPLEFT", savedDropdown, "BOTTOMLEFT", 16, -10)
    channelsLabel:SetText("Channels:")

    -- General channel checkbox.
    local generalCheck = CreateFrame("CheckButton", "MethlBroadcastGeneralCheck", frame, "UICheckButtonTemplate")
    generalCheck:SetPoint("TOPLEFT", channelsLabel, "BOTTOMLEFT", 0, -6)
    getglobal(generalCheck:GetName() .. "Text"):SetText("General (Ch. 1)")
    generalCheck:SetChecked(self.db.channels.general)
    generalCheck:SetScript("OnClick", function(selfCheck)
        MethlBroadcast.db.channels.general = selfCheck:GetChecked() and true or false
    end)

    -- LFG channel checkbox.
    local lfgCheck = CreateFrame("CheckButton", "MethlBroadcastLFGCheck", frame, "UICheckButtonTemplate")
    lfgCheck:SetPoint("TOPLEFT", generalCheck, "BOTTOMLEFT", 0, -4)
    getglobal(lfgCheck:GetName() .. "Text"):SetText("LookingForGroup")
    lfgCheck:SetChecked(self.db.channels.lfg)
    lfgCheck:SetScript("OnClick", function(selfCheck)
        MethlBroadcast.db.channels.lfg = selfCheck:GetChecked() and true or false
    end)

    -- World channel checkbox + name box.
    local worldCheck = CreateFrame("CheckButton", "MethlBroadcastWorldCheck", frame, "UICheckButtonTemplate")
    worldCheck:SetPoint("TOPLEFT", lfgCheck, "BOTTOMLEFT", 0, -4)
    getglobal(worldCheck:GetName() .. "Text"):SetText("World Channel:")
    worldCheck:SetChecked(self.db.channels.world)
    worldCheck:SetScript("OnClick", function(selfCheck)
        MethlBroadcast.db.channels.world = selfCheck:GetChecked() and true or false
    end)

    local worldNameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    worldNameBox:SetPoint("LEFT", worldCheck, "RIGHT", 110, 0)
    worldNameBox:SetWidth(120)
    worldNameBox:SetHeight(20)
    worldNameBox:SetAutoFocus(false)
    worldNameBox:SetText(self.db.worldChannelName or "World")
    worldNameBox:SetScript("OnTextChanged", function(selfBox)
        MethlBroadcast.db.worldChannelName = selfBox:GetText() or "World"
    end)
    worldNameBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:ClearFocus()
    end)
    self.worldNameBox = worldNameBox

    -- Interval section label.
    local intervalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    intervalLabel:SetPoint("TOPLEFT", worldCheck, "BOTTOMLEFT", 0, -16)
    intervalLabel:SetText("Interval:")

    -- Interval toggle buttons.
    local intervalOptions = {
        { key = "30", text = "30s" },
        { key = "60", text = "60s" },
        { key = "120", text = "120s" },
        { key = "480", text = "480s" },
        { key = "custom", text = "Custom" },
    }

    local lastButton = nil
    for _, option in ipairs(intervalOptions) do
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetWidth(70)
        btn:SetHeight(24)
        btn:SetText(option.text)
        if not lastButton then
            btn:SetPoint("TOPLEFT", intervalLabel, "BOTTOMLEFT", 0, -8)
        else
            btn:SetPoint("LEFT", lastButton, "RIGHT", 6, 0)
        end

        btn:SetScript("OnClick", function()
            MethlBroadcast.db.intervalPreset = option.key
            MethlBroadcast:UpdateIntervalButtons()
            MethlBroadcast:UpdateStatusDisplay()
        end)

        self.intervalButtons[option.key] = btn
        lastButton = btn
    end

    -- Custom interval controls (shown only for custom preset).
    local customLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOPLEFT", intervalLabel, "BOTTOMLEFT", 0, -38)
    customLabel:SetText("Custom Seconds (min 10):")
    self.customIntervalLabel = customLabel

    local customBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    customBox:SetPoint("LEFT", customLabel, "RIGHT", 8, 0)
    customBox:SetWidth(60)
    customBox:SetHeight(20)
    customBox:SetAutoFocus(false)
    customBox:SetNumeric(true)
    customBox:SetText(tostring(self.db.customInterval or 180))
    customBox:SetScript("OnEnterPressed", function(selfBox)
        local value = tonumber(selfBox:GetText()) or MethlBroadcast.db.customInterval or 10
        value = math.floor(value)
        if value < 10 then
            value = 10
        end
        MethlBroadcast.db.customInterval = value
        selfBox:SetText(tostring(value))
        selfBox:ClearFocus()
        MethlBroadcast:UpdateStatusDisplay()
    end)
    customBox:SetScript("OnEscapePressed", function(selfBox)
        selfBox:SetText(tostring(MethlBroadcast.db.customInterval or 180))
        selfBox:ClearFocus()
    end)
    self.customIntervalEditBox = customBox

    -- Start/Stop button.
    local startStopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startStopButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)
    startStopButton:SetWidth(220)
    startStopButton:SetHeight(32)
    startStopButton:SetScript("OnClick", function()
        if MethlBroadcast.isBroadcasting then
            MethlBroadcast:StopBroadcasting()
        else
            MethlBroadcast:StartBroadcasting()
        end
    end)
    self.startStopButton = startStopButton

    -- Status text.
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOP", startStopButton, "BOTTOM", 0, -10)
    statusText:SetText("Status: Stopped")
    self.statusText = statusText

    self:UpdateIntervalButtons()
    self:UpdateStatusDisplay()
end

-- Toggle main frame visibility via slash commands.
function MethlBroadcast:ToggleFrame()
    if not self.frame then
        self:CreateUI()
    end

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

-- Event frame for load/logout and ticker handling.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Load SavedVariables and backfill missing keys.
        MethlBroadcastDB = ApplyDefaults(MethlBroadcastDB, DEFAULTS)
        MethlBroadcast.db = MethlBroadcastDB

        -- Register slash commands once addon has loaded.
        SLASH_METHLBROADCAST1 = "/mb"
        SLASH_METHLBROADCAST2 = "/methlbroadcast"
        SlashCmdList["METHLBROADCAST"] = function()
            MethlBroadcast:ToggleFrame()
        end

        -- Build UI lazily on first slash use, but create now so settings reflect immediately.
        MethlBroadcast:CreateUI()
    elseif event == "PLAYER_LOGOUT" then
        -- Ensure runtime DB reference is persisted.
        MethlBroadcastDB = MethlBroadcast.db or MethlBroadcastDB
    end
end)

eventFrame:SetScript("OnUpdate", function(_, delta)
    if not MethlBroadcast.isBroadcasting then
        return
    end

    local interval = MethlBroadcast:GetCurrentInterval()
    if interval <= 0 then
        return
    end

    MethlBroadcast.elapsed = MethlBroadcast.elapsed + delta
    if MethlBroadcast.elapsed >= interval then
        MethlBroadcast:BroadcastNow()
        MethlBroadcast.elapsed = 0
    end
end)
