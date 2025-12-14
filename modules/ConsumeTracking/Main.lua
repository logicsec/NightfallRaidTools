-- Consume Tracking Module
ConsumeTracker = ConsumeTracker or {}
ConsumeTracker.Modules = ConsumeTracker.Modules or {}
ConsumeTracker.Modules["ConsumeTracking"] = {}
local Module = ConsumeTracker.Modules["ConsumeTracking"]

Module.Label = "Consume Tracking"
-- Icon path needs to be verified or passed from core if we want to reuse assets
Module.Icon = "Interface\\Icons\\INV_Potion_83" 

function Module:OnInitialize()
    -- Called when addon loads
    -- Register events specific to this module here?
end

function Module:OnEnable(contentFrame)
    -- Called when this module is selected
    -- Build UI if not already built
    if not self.isBuilt then
        self:BuildUI(contentFrame)
        self.isBuilt = true
    end
    
    if contentFrame.headerBg then contentFrame.headerBg:Show() end
    -- Show subtabs
end

function Module:OnDisable(contentFrame)
    -- Called when switching away
end

function Module:BuildUI(parent)
    -- Consume Tracking Content Frame (Container for the sub-tabs)
    local module1Content = parent

    -- Module Header Background (Dark strip for Title + Tabs)
    local headerBg = module1Content:CreateTexture(nil, "BACKGROUND")
    headerBg:SetTexture(0.15, 0.15, 0.15, 0.8) -- Requested Dark Gray
    headerBg:SetPoint("TOPLEFT", module1Content, "TOPLEFT", 0, -35) -- Shifted down below title
    headerBg:SetPoint("TOPRIGHT", module1Content, "TOPRIGHT", 0, 0)
    headerBg:SetHeight(34) -- Height to cover tabs
    module1Content.headerBg = headerBg

    -- Module Header Title
    local module1Title = module1Content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    module1Title:SetText("Consume Tracking")
    module1Title:SetPoint("TOPLEFT", module1Content, "TOPLEFT", 10, -10)
    module1Title:SetTextColor(1, 0.82, 0) -- Gold

    -- Helper: Create Sub Tab
    local function CreateSubTab(parent, id, text, xOffset)
        local tab = CreateFrame("Button", "ConsumeTracker_SubTab_" .. id, parent)
        tab:SetWidth(100)
        tab:SetHeight(24)
        tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -40)

        -- Text
        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tabText:SetText(text)
        tabText:SetTextColor(0.6, 0.6, 0.6) -- Default Gray
        tab.text = tabText

        -- Active Indicator (Bottom Line)
        local activeLine = tab:CreateTexture(nil, "OVERLAY")
        activeLine:SetHeight(2)
        activeLine:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        activeLine:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        activeLine:Hide()
        tab.activeLine = activeLine

        tab:SetScript("OnClick", function()
            ConsumeTracker_ShowSubTab(id)
        end)
        
        return tab
    end

    -- Create Sub Tabs
    local subTabs = {}
    subTabs[1] = CreateSubTab(module1Content, 1, "Tracker", 10)
    subTabs[2] = CreateSubTab(module1Content, 2, "Items", 115)
    subTabs[3] = CreateSubTab(module1Content, 3, "Presets", 220)
    subTabs[4] = CreateSubTab(module1Content, 4, "Settings", 325)
    
    module1Content.subTabs = subTabs

    -- Send Data Button (in header, right-justified) - Green box style
    sendDataButton = CreateFrame("Button", "ConsumeTracker_sendDataButton", module1Content)
    sendDataButton:SetWidth(50)
    sendDataButton:SetHeight(18)
    sendDataButton:SetPoint("TOPRIGHT", module1Content, "TOPRIGHT", -10, -43) -- Right-justified
    
    -- Transparent box with green border outline
    sendDataButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    sendDataButton:SetBackdropColor(0, 0, 0, 0) -- Transparent background
    sendDataButton:SetBackdropBorderColor(0.2, 0.5, 0.4, 1) -- Green border
    
    -- White centered text (no shadow)
    local sendText = sendDataButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sendText:SetFont("Fonts\\ARIALN.TTF", 9)  -- Cleaner font at small size
    sendText:SetPoint("CENTER", sendDataButton, "CENTER", 0, 0)
    sendText:SetText("Sync")
    sendText:SetTextColor(1, 1, 1) -- White text
    sendText:SetShadowOffset(0, 0) -- Remove drop shadow
    sendDataButton.text = sendText
    
    -- Mini progress bar inside button (hidden by default)
    local miniProgressBar = sendDataButton:CreateTexture(nil, "ARTWORK")
    miniProgressBar:SetTexture("Interface\\Buttons\\WHITE8x8")
    miniProgressBar:SetVertexColor(0.2, 0.7, 0.4, 1) -- Green fill
    miniProgressBar:SetPoint("LEFT", sendDataButton, "LEFT", 2, 0)
    miniProgressBar:SetHeight(14)
    miniProgressBar:SetWidth(0) -- Start with 0 width
    miniProgressBar:Hide()
    sendDataButton.progressBar = miniProgressBar
    
    -- Checkmark texture (hidden by default)
    local checkmark = sendDataButton:CreateTexture(nil, "OVERLAY")
    checkmark:SetTexture("Interface\\AddOns\\NightfallRaidTools\\images\\checkmark.tga")
    checkmark:SetVertexColor(1, 1, 1, 1) -- Pure white, full opacity
    checkmark:SetBlendMode("BLEND") -- Ensure alpha transparency works
    checkmark:SetWidth(14)
    checkmark:SetHeight(14)
    checkmark:SetPoint("CENTER", sendDataButton, "CENTER", 0, 0)
    checkmark:Hide()
    sendDataButton.checkmark = checkmark
    
    -- Hover effects (only when not syncing)
    sendDataButton:SetScript("OnEnter", function()
        if sendDataButton.isSyncing then return end
        this:SetBackdropColor(0.2, 0.5, 0.4, 0.2) -- Slight green tint on hover
        this:SetBackdropBorderColor(0.3, 0.7, 0.5, 1) -- Brighter border
    end)
    sendDataButton:SetScript("OnLeave", function()
        if sendDataButton.isSyncing then return end
        this:SetBackdropColor(0, 0, 0, 0) -- Transparent background
        this:SetBackdropBorderColor(0.2, 0.5, 0.4, 1) -- Normal green border
    end)
    
    sendDataButton:SetScript("OnClick", function() 
        if PushData then PushData() end
    end)

    function updateSenDataButtonState()
        if ConsumeTracker_Options.Channel == nil or ConsumeTracker_Options.Channel == "" or ConsumeTracker_Options.Password == nil or ConsumeTracker_Options.Password == "" then
            sendDataButton:Hide()
            if ReadData then ReadData("stop") end
        else
            sendDataButton:Show()
            if ReadData then ReadData("start") end
        end
    end
    -- Export this so we can call it globally if needed, or hook into settings update
    ConsumeTracker.UpdateSyncButtonState = updateSenDataButtonState
    updateSenDataButtonState()

    -- Sub-Tab Content Frames
    module1Content.tabFrames = {}
    
    -- Common Content Rect
    local contentWidth = 590 
    local contentHeight = 420 
    local contentX = 10
    local contentY = -70 

    -- Helper to create content frame
    local function CreateTabFrame(id)
        local f = CreateFrame("Frame", nil, module1Content)
        f:SetWidth(contentWidth)
        f:SetHeight(contentHeight)
        f:SetPoint("TOPLEFT", module1Content, "TOPLEFT", contentX, contentY)
        f:Hide()
        module1Content.tabFrames[id] = f
        return f
    end

    local tab1Frame = CreateTabFrame(1) -- Tracker
    local tab2Frame = CreateTabFrame(2) -- Items
    local tab3Frame = CreateTabFrame(3) -- Presets
    local tab4Frame = CreateTabFrame(4) -- Settings

    -- Map old structure for compatibility so existing global functions work
    ConsumeTracker_MainFrame.tabs = {}
    ConsumeTracker_MainFrame.tabs[1] = tab1Frame 
    ConsumeTracker_MainFrame.tabs[2] = tab2Frame
    ConsumeTracker_MainFrame.tabs[3] = tab3Frame
    ConsumeTracker_MainFrame.tabs[4] = tab4Frame

    -- Add Custom Content for Tabs (Functions currently exist in Main.lua globally?)
    -- TODO: Move these functions to this module later
    if ConsumeTracker_CreateManagerContent then ConsumeTracker_CreateManagerContent(tab1Frame) end
    if ConsumeTracker_CreateItemsContent then ConsumeTracker_CreateItemsContent(tab2Frame) end
    if ConsumeTracker_CreatePresetsContent then ConsumeTracker_CreatePresetsContent(tab3Frame) end
    if ConsumeTracker_CreateSettingsContent then ConsumeTracker_CreateSettingsContent(tab4Frame) end

    if ConsumeTracker_UpdateTabStates then ConsumeTracker_UpdateTabStates() end
end
