-- Onload & Click Functionality -------------------------------------------------------------------------
    WindowWidth = 600

    function ConsumeTracker_OnLoad(self)
        self:RegisterForDrag("LeftButton")
        self:SetScript("OnDragStart", function() ConsumeTracker_OnDragStart(self) end)
        self:SetScript("OnDragStop", function() ConsumeTracker_OnDragStop(self) end)
         self:SetScript("OnClick", ConsumeTracker_HandleClick)
    end

    function ConsumeTracker_HandleClick(self, button)
        -- Only respond to left-clicks without the Shift key pressed
        if button == "LeftButton" and not IsShiftKeyDown() then
            -- Toggle the visibility of the main frame
            if ConsumeTracker_MainFrame and ConsumeTracker_MainFrame:IsShown() then
                ConsumeTracker_MainFrame:Hide()
            else
                ConsumeTracker_ShowMainWindow()
            end
        end
    end

    function ConsumeTracker_OnDragStart(self)
        if IsShiftKeyDown() then
            self:StartMoving()
            self.isMoving = true
        end
    end

    function ConsumeTracker_OnDragStop(self)
        if self and self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
        end
    end


    if not ConsumeTracker_Options then
        ConsumeTracker_Options = {}
    end
    if not ConsumeTracker_SelectedItems then
        ConsumeTracker_SelectedItems = {}
    end

    if not ConsumeTracker_Data then
        ConsumeTracker_Data = {}
    end

    -- Character Specific Settings Data Structure
    -- Initialized by SavedVariablesPerCharacter: ConsumeTracker_CharacterSettings

    function ConsumeTracker_GetCharacterSetting(key, default)
        if not ConsumeTracker_CharacterSettings then
            ConsumeTracker_CharacterSettings = {}
        end
        
        local value = ConsumeTracker_CharacterSettings[key]
        if value == nil then
            return default
        else
            return value
        end
    end

    function ConsumeTracker_SetCharacterSetting(key, value)
        if not ConsumeTracker_CharacterSettings then
            ConsumeTracker_CharacterSettings = {}
        end
        
        ConsumeTracker_CharacterSettings[key] = value
    end

-- Slash Command Handler --------------------------------------------------------------------------------
    SLASH_CONSUMETRACKER1 = "/ct"
    SLASH_CONSUMETRACKER2 = "/consumetracker"

    SlashCmdList["CONSUMETRACKER"] = function(msg)
        local cmd = string.lower(msg)
        
        if cmd == "show" then
            ConsumeTracker_Options.showActionBar = true
            ConsumeTracker_UpdateActionBar()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ConsumeTracker:|r Action Bar shown.")
        elseif cmd == "hide" then
            ConsumeTracker_Options.showActionBar = false
            ConsumeTracker_UpdateActionBar()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ConsumeTracker:|r Action Bar hidden.")
        elseif cmd == "reset" then
             ConsumeTracker_SetCharacterSetting("ActionBarPoint", nil)
             ConsumeTracker_SetCharacterSetting("ActionBarRelativePoint", nil)
             ConsumeTracker_SetCharacterSetting("ActionBarXOfs", nil)
             ConsumeTracker_SetCharacterSetting("ActionBarYOfs", nil)
             ConsumeTracker_RestoreActionBarPosition()
             DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ConsumeTracker:|r Action Bar position reset.")
        elseif cmd == "menu" or cmd == "config" or cmd == "options" then
            ConsumeTracker_ShowMainWindow()
            if cmd == "config" or cmd == "options" then
                 ConsumeTracker_ShowTab(4) -- Go to Settings tab
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ConsumeTracker Usage:|r")
            DEFAULT_CHAT_FRAME:AddMessage("/ct show  - Show the Action Bar")
            DEFAULT_CHAT_FRAME:AddMessage("/ct hide  - Hide the Action Bar")
            DEFAULT_CHAT_FRAME:AddMessage("/ct reset - Reset Action Bar position")
            DEFAULT_CHAT_FRAME:AddMessage("/ct menu  - Open Main Window")
            DEFAULT_CHAT_FRAME:AddMessage("/ct config - Open Settings")
        end
    end

-- Event frame for updating data ------------------------------------------------------------------------
    local ConsumeTracker_EventFrame = CreateFrame("Frame")
    ConsumeTracker_EventFrame:RegisterEvent("PLAYER_LOGIN")
    ConsumeTracker_EventFrame:RegisterEvent("BAG_UPDATE")
    ConsumeTracker_EventFrame:RegisterEvent("BANKFRAME_OPENED")
    ConsumeTracker_EventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    ConsumeTracker_EventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
    ConsumeTracker_EventFrame:RegisterEvent("MAIL_SHOW")
    ConsumeTracker_EventFrame:RegisterEvent("MAIL_INBOX_UPDATE")
    ConsumeTracker_EventFrame:RegisterEvent("MAIL_CLOSED")
    ConsumeTracker_EventFrame:RegisterEvent("UNIT_AURA")

    -- Tooltip for scanning buffs
    local scanTooltip = CreateFrame("GameTooltip", "ConsumeTracker_ScanTooltip", nil, "GameTooltipTemplate")
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

    function ConsumeTracker_IsBuffActive(targetBuffName, buffType, buffId)
        -- Fallback to "player" if not specified
        buffType = buffType or "player"

        if buffType == "player" then
            -- Turtle WoW / SuperWoW specific: UnitBuff returns spellId as 3rd arg
            for i = 1, 32 do
                local texture, stacks, spellId = UnitBuff("player", i)
                if not texture then break end -- No more buffs
                
                local found = false
                
                -- Check by ID if we have it (Fastest & Most Accurate)
                if buffId then
                    -- Correct integer overflow if necessary (common in vanilla modded clients)
                    if spellId and spellId < 0 then
                        spellId = spellId + 65536
                    end
                    
                    if spellId == buffId then
                        found = true
                    end
                end

                -- Fallback: Check by Name if ID check didn't pass (or no ID provided)
                if not found and not buffId and targetBuffName then
                    -- Note: UnitBuff doesn't return name in standard Vanilla, so we must scan tooltip
                     scanTooltip:ClearLines()
                     scanTooltip:SetUnitBuff("player", i)
                     local buffName = ConsumeTracker_ScanTooltipTextLeft1:GetText()
                     if buffName and buffName == targetBuffName then
                         found = true
                     end
                end
                
                if found then
                    -- Get Time Left
                    -- UnitBuff index i (1-based) corresponds to GetPlayerBuff(i-1, "HELPFUL")
                    -- GetPlayerBuff returns a global buff index used for GetPlayerBuffTimeLeft
                    local buffIndex = GetPlayerBuff(i - 1, "HELPFUL")
                    local timeLeft = nil
                    if buffIndex then
                        timeLeft = GetPlayerBuffTimeLeft(buffIndex)
                    end
                    return true, timeLeft
                end
            end
        elseif buffType == "weapon" then
            -- Weapon enchant scanning (Visual + Optional Text Check)
            local hasMainHandEnchant, mainHandExpiration, mainHandCharges, hasOffHandEnchant, offHandExpiration, offHandCharges = GetWeaponEnchantInfo()
            
            if hasMainHandEnchant then
                scanTooltip:ClearLines()
                scanTooltip:SetInventoryItem("player", 16) -- Main Hand
                -- Scan lines for the enchant name
                for i = 1, scanTooltip:NumLines() do
                     local line = getglobal("ConsumeTracker_ScanTooltipTextLeft" .. i)
                     if line then
                        local text = line:GetText()
                        if text and string.find(text, targetBuffName, 1, true) then
                            return true, (mainHandExpiration and mainHandExpiration / 1000)
                        end
                     end
                end
            end
            
            if hasOffHandEnchant then
                scanTooltip:ClearLines()
                scanTooltip:SetInventoryItem("player", 17) -- Off Hand
                for i = 1, scanTooltip:NumLines() do
                     local line = getglobal("ConsumeTracker_ScanTooltipTextLeft" .. i)
                     if line then
                        local text = line:GetText()
                        if text and string.find(text, targetBuffName, 1, true) then
                            return true, (offHandExpiration and offHandExpiration / 1000)
                        end
                     end
                end
            end
        end

        return false, nil
    end

    ConsumeTracker_EventFrame:SetScript("OnEvent", function()

        local isDefaultBankVisible = BankFrame and BankFrame:IsVisible()
        local isOneBankVisible = OneBankFrame and OneBankFrame:IsVisible()

        if event == "BANKFRAME_OPENED" then
            isBankOpen = true
        elseif event == "MAIL_SHOW" then
            isMailOpen = true
        elseif event == "MAIL_CLOSED" then
            isMailOpen = false
        elseif not (isDefaultBankVisible or isOneBankVisible) then
            isBankOpen = false
        end

        if event == "PLAYER_LOGIN" then


        function ConsumeTracker_CheckVersionUpdate()
            -- Initialize options if needed
            ConsumeTracker_Options = ConsumeTracker_Options or {}
            
            -- Check if we've already shown the popup for this version
            if not ConsumeTracker_Options.LastVersionReset or ConsumeTracker_Options.LastVersionReset ~= GetAddOnMetadata("ConsumeTracker", "Version") then
                -- Show the popup with a slight delay to ensure UI is loaded
                local delayFrame = CreateFrame("Frame")
                delayFrame:SetScript("OnUpdate", function()
                    local elapsed = 0
                    elapsed = elapsed + arg1
                    if elapsed >= 1 then
                        ConsumeTracker_ShowVersionUpdatePopup()
                        delayFrame:SetScript("OnUpdate", nil)
                    end
                end)
            end
        end

        -- Find this in your existing code, typically in a function that runs when the addon loads
        local ConsumeTracker_EventFrame = CreateFrame("Frame")
        ConsumeTracker_EventFrame:RegisterEvent("PLAYER_LOGIN")
        ConsumeTracker_EventFrame:SetScript("OnEvent", function()
            if event == "PLAYER_LOGIN" then
                -- Your existing code...
                
                -- Add this line to check for version updates
                -- ConsumeTracker_CheckVersionUpdate()
                
                -- Continue with your existing code...
            end
        end)




            if ConsumeTracker_Options and ConsumeTracker_Options.Channel and ConsumeTracker_Options.Password then
                local channelName = DecodeMessage(ConsumeTracker_Options.Channel)
                local channelPassword = DecodeMessage(ConsumeTracker_Options.Password)
                JoinChannelByName(channelName, channelPassword)
                SetChannelPassword(channelName, channelPassword)
                MultiAccountChannelAnnounce = "|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r |cffffffffJoined|r |cffffc0c0[" .. channelName .. "]|r|cffffffff. Multi-account synchronization |cff00ff00enabled|r|cffffffff.|r"
                ReadData("start")
            else
                MultiAccountChannelAnnounce = "|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r Multi-account synchronization |cffff0000disabled|r|cffffffff. Check the addon options for setup.|r"
                ReadData("stop")
            end

            local delayFrame = CreateFrame("Frame")
            local elapsed = 0
            local delay = 1

            delayFrame:SetScript("OnUpdate", function()
                elapsed = elapsed + arg1 -- arg1 provides the time since the last frame
                if elapsed >= delay then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00" .. GetAddOnMetadata("ConsumeTracker", "Title") .. "|r |cffaaaaaa(v" .. GetAddOnMetadata("ConsumeTracker", "Version") .. ")|r |cffffffffLoaded!|r")
                    DEFAULT_CHAT_FRAME:AddMessage(MultiAccountChannelAnnounce)
                    delayFrame:SetScript("OnUpdate", nil) -- Stop the OnUpdate script
                end
            end)

            ConsumeTracker_ScanPlayerInventory()
            ConsumeTracker_ScanPlayerBank()
            ConsumeTracker_ScanPlayerMail()
            ConsumeTracker_UpdateActionBar()
        elseif event == "BAG_UPDATE" then
            ConsumeTracker_ScanPlayerInventory()
            if isBankOpen == true then
                ConsumeTracker_ScanPlayerBank()
            end
            if isMailOpen == true then
                ConsumeTracker_ScanPlayerMail()
            end
        elseif event == "BANKFRAME_OPENED" then
            ConsumeTracker_ScanPlayerBank()
        elseif event == "PLAYERBANKSLOTS_CHANGED" then
            ConsumeTracker_ScanPlayerBank()
            ConsumeTracker_ScanPlayerInventory()
        elseif event == "ITEM_LOCK_CHANGED" then
            if isBankOpen == true then
                ConsumeTracker_ScanPlayerInventory()
                ConsumeTracker_ScanPlayerBank()
            end
            if isMailOpen == true then
                ConsumeTracker_ScanPlayerInventory()
                ConsumeTracker_ScanPlayerMail()
            end
        elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
            ConsumeTracker_ScanPlayerMail()
        elseif event == "UNIT_AURA" then
            if arg1 == "player" then
                ConsumeTracker_UpdateActionBar()
            end
        end
    end)


-- Plugin Reset on New Version

function ConsumeTracker_ShowVersionUpdatePopup()
    -- Check if a popup already exists
    if ConsumeTracker_VersionUpdateFrame then
        return
    end
    
    -- Create the popup frame
    local popup = CreateFrame("Frame", "ConsumeTracker_VersionUpdateFrame", UIParent)
    popup:SetWidth(400)
    popup:SetHeight(200)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    popup:SetBackdropColor(0, 0, 0, 1)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function() this:StartMoving() end)
    popup:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    
    -- Add a title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", popup, "TOP", 0, -20)
    title:SetText("ConsumeTracker Update " .. GetAddOnMetadata("ConsumeTracker", "Version"))
    title:SetTextColor(1, 0.8, 0)
    
    -- Add a message
    local message = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOP", title, "BOTTOM", 0, -20)
    message:SetWidth(360)
    message:SetText("This version adds cross-faction support, allowing you to track and trade consumables with characters from both factions.\n\nYou need to reset the addon to update the data structure. Don't worry, your settings will be preserved!")
    message:SetJustifyH("CENTER")
    
    -- Create Reset Button
    local resetButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    resetButton:SetWidth(100)
    resetButton:SetHeight(24)
    resetButton:SetPoint("BOTTOM", popup, "BOTTOM", 0, 40)
    resetButton:SetText("Reset Now")
    resetButton:SetScript("OnClick", function()
        -- Store that we've shown this version popup
        ConsumeTracker_Options = ConsumeTracker_Options or {}
        ConsumeTracker_Options.LastVersionReset = GetAddOnMetadata("ConsumeTracker", "Version")
        
        -- Reset the addon data structures, preserving important settings
        local channelInfo = nil
        local passwordInfo = nil
        local characterOptions = nil
        local enableCategories = nil
        local showUseButton = nil
        local selectedItems = nil
        
        -- Backup important settings
        if ConsumeTracker_Options then
            channelInfo = ConsumeTracker_Options.Channel
            passwordInfo = ConsumeTracker_Options.Password
            characterOptions = ConsumeTracker_Options.Characters
            enableCategories = ConsumeTracker_Options.enableCategories
            showUseButton = ConsumeTracker_Options.showUseButton
        end
        
        if ConsumeTracker_SelectedItems then
            selectedItems = {}
            for id, selected in pairs(ConsumeTracker_SelectedItems) do
                selectedItems[id] = selected
            end
        end
        
        -- Reset data
        ConsumeTracker_Data = {}
        
        -- Restore important settings
        ConsumeTracker_Options = {
            Channel = channelInfo,
            Password = passwordInfo,
            Characters = characterOptions,
            enableCategories = enableCategories,
            showUseButton = showUseButton,
            LastVersionReset = GetAddOnMetadata("ConsumeTracker", "Version")
        }
        
        ConsumeTracker_SelectedItems = selectedItems or {}
        
        -- Close the popup
        popup:Hide()
        
        -- Reload UI
        ReloadUI()
    end)
    
    -- Create Later Button
    local laterButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    laterButton:SetWidth(100)
    laterButton:SetHeight(24)
    laterButton:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 30, 40)
    laterButton:SetText("Later")
    laterButton:SetScript("OnClick", function()
        popup:Hide()
    end)
    
    -- Create Skip Button (never show again)
    local skipButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    skipButton:SetWidth(100)
    skipButton:SetHeight(24)
    skipButton:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -30, 40)
    skipButton:SetText("Skip")
    skipButton:SetScript("OnClick", function()
        -- Store that we've shown this version popup even if they didn't reset
        ConsumeTracker_Options = ConsumeTracker_Options or {}
        ConsumeTracker_Options.LastVersionReset = GetAddOnMetadata("ConsumeTracker", "Version")
        popup:Hide()
    end)
    
    -- Close button in corner
    local closeButton = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        popup:Hide()
    end)
    
    popup:Show()
end

-- Main Windows Setup -----------------------------------------------------------------------------------
function ConsumeTracker_CreateMainWindow()
    -- Main Frame
    ConsumeTracker_MainFrame = CreateFrame("Frame", "ConsumeTracker_MainFrame", UIParent)
    ConsumeTracker_MainFrame:SetWidth(800)
    ConsumeTracker_MainFrame:SetHeight(500)
    ConsumeTracker_MainFrame:SetPoint("CENTER", UIParent, "CENTER")
    ConsumeTracker_MainFrame:SetFrameStrata("DIALOG")
    ConsumeTracker_MainFrame:SetMovable(true)
    ConsumeTracker_MainFrame:EnableMouse(true)
    ConsumeTracker_MainFrame:RegisterForDrag("LeftButton")
    ConsumeTracker_MainFrame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    ConsumeTracker_MainFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)

    table.insert(UISpecialFrames, "ConsumeTracker_MainFrame")

    -- Sidebar Background
    local sidebar = ConsumeTracker_MainFrame:CreateTexture(nil, "BACKGROUND")
    sidebar:SetTexture(0, 0, 0, 0.5) -- Dark sidebar
    sidebar:SetWidth(180)
    sidebar:SetPoint("TOPLEFT", ConsumeTracker_MainFrame, "TOPLEFT", 5, -5)
    sidebar:SetPoint("BOTTOMLEFT", ConsumeTracker_MainFrame, "BOTTOMLEFT", 5, 5)

    -- Content Background
    local background = ConsumeTracker_MainFrame:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    background:SetPoint("TOPLEFT", ConsumeTracker_MainFrame, "TOPLEFT", 185, -5)
    background:SetPoint("BOTTOMRIGHT", ConsumeTracker_MainFrame, "BOTTOMRIGHT", -5, 5)

    -- Border (Removed edgeFile for borderless look)
    ConsumeTracker_MainFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 32,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    ConsumeTracker_MainFrame:SetBackdropColor(0.1, 0.1, 0.1, 1)

    -- Progress Bar for Syncing (Removed/Commented out)
    -- ProgressBarFrame = CreateFrame("Frame", "ConsumeTracker_ProgressBar", ConsumeTracker_MainFrame, BackdropTemplateMixin and "BackdropTemplate")
    -- ProgressBarFrame:SetWidth(20)
    -- ProgressBarFrame:SetHeight(496)
    -- ProgressBarFrame:SetPoint("TOPRIGHT", ConsumeTracker_MainFrame, "TOPRIGHT", 10, -8)
    -- ProgressBarFrame:SetBackdrop({
    --     bgFile = "Interface\\Buttons\\WHITE8x8",
    --     edgeFile = "Interface\\Buttons\\WHITE8x8",
    --     edgeSize = 1,
    -- })
    -- ProgressBarFrame:SetBackdropColor(0,0,0,1)
    -- ProgressBarFrame:SetBackdropBorderColor(0.5,0.5,0.5,1)
    -- ProgressBarFrame:SetFrameLevel(ConsumeTracker_MainFrame:GetFrameLevel() - 1)
    -- ProgressBarFrame:Hide()

    -- ProgressBarFrame_fill = CreateFrame("Frame", "ConsumeTracker_ProgressBarFill", ProgressBarFrame, BackdropTemplateMixin and "BackdropTemplate")
    -- ProgressBarFrame_fill:SetWidth(17)
    -- ProgressBarFrame_fill:SetHeight(0)
    -- ProgressBarFrame_fill:SetPoint("BOTTOMLEFT", ProgressBarFrame, "BOTTOMLEFT", 1, 2)
    -- ProgressBarFrame_fill:SetBackdrop({
    --     bgFile = "Interface\\Buttons\\WHITE8x8"
    -- })
    -- ProgressBarFrame_fill:SetBackdropColor(0,0.6,0,1)
    -- ProgressBarFrame_fill:Hide()
    -- ProgressBarFrame_fill:SetFrameLevel(ProgressBarFrame:GetFrameLevel() + 1)


    -- ProgressBarFrame_Text = ProgressBarFrame_fill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- ProgressBarFrame_Text:SetText("S\n\nY\n\nN\n\nC\n\nI\n\nN\n\nG")
    -- ProgressBarFrame_Text:SetPoint("CENTER", ProgressBarFrame, "CENTER", 1, 0)
    -- ProgressBarFrame_Text:SetTextColor(1,1,1)
    -- ProgressBarFrame_Text:Hide()


    -- Title Text
    local titleText = ConsumeTracker_MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetText("Nightfall Raid Tools")
    titleText:SetPoint("TOP", ConsumeTracker_MainFrame, "TOPLEFT", 90, -16) -- Adjusted padding (-10 to -16)
    titleText:SetTextColor(1, 0.82, 0)

    -- Calculate the width of the title text and adjust the title background accordingly
    local titleWidth = titleText:GetStringWidth() + 200 
    
    -- Title Background (REMOVED)

    -- Close Button
    local closeButton = CreateFrame("Button", nil, ConsumeTracker_MainFrame, "UIPanelCloseButton")
    closeButton:SetWidth(32)
    closeButton:SetHeight(32)
    closeButton:SetPoint("TOPRIGHT", ConsumeTracker_MainFrame, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        ConsumeTracker_MainFrame:Hide()
    end)

    -- Create a custom tooltip frame
    ConsumeTrackerTooltip = CreateFrame("Frame", "ConsumeTrackerTooltip", UIParent)
    ConsumeTrackerTooltip:SetWidth(100)
    ConsumeTrackerTooltip:SetHeight(40)
    ConsumeTrackerTooltip:SetFrameStrata("TOOLTIP")
    ConsumeTrackerTooltip:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    ConsumeTrackerTooltip:SetBackdropColor(0, 0, 0, 1)
    ConsumeTrackerTooltip:Hide()

    -- Tooltip text
    local tooltipText = ConsumeTrackerTooltip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tooltipText:SetPoint("CENTER", ConsumeTrackerTooltip, "CENTER", 0, 0)
    ConsumeTrackerTooltip.text = tooltipText

    -- Tabs
    local tabs = {}
    ConsumeTracker_Tabs = {}
    
    -- =========================================================================================
    -- Tab System Refactor: Hierarchy
    -- Level 1: Sidebar Modules (Vertical) - "Consume Tracking"
    -- Level 2: Sub-Tabs (Horizontal) - "Tracker", "Items", "Presets", "Settings"
    -- =========================================================================================

    local sidebarModules = {}
    ConsumeTracker_SidebarModules = {}
    
    local function CreateSidebarModule(name, texture, yOffset, labelText, moduleIndex)
        local btn = CreateFrame("Button", name, ConsumeTracker_MainFrame)
        btn:SetWidth(180) -- Sidebar width
        btn:SetHeight(24) -- Reduced Height (30 -> 24)
        btn:SetPoint("TOPLEFT", ConsumeTracker_MainFrame, "TOPLEFT", 5, yOffset) -- Adjusted X to 5 to match sidebar inset

        -- Background (Highlight/Select)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetTexture("Interface\\Buttons\\WHITE8x8") -- Use solid white texture for gradient
        bg:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0, 1, 0.82, 0, 0) -- Initially transparent
        btn.bg = bg

        -- Icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(texture)
        icon:SetWidth(18) -- Reduced icon size (20 -> 18)
        icon:SetHeight(18)
        icon:SetPoint("LEFT", btn, "LEFT", 10, 0)
        btn.icon = icon

        -- Label
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        label:SetText(labelText)
        label:SetTextColor(1, 0.82, 0) 
        btn.label = label

        -- Active Indicator Bar
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetTexture(1, 0.82, 0, 1)
        activeBar:SetWidth(3) -- Slightly thinner bar
        activeBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        activeBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        activeBar:Hide()
        btn.activeBar = activeBar

        btn:SetScript("OnClick", function()
            ConsumeTracker_ShowModule(moduleIndex)
        end)

        ConsumeTracker_SidebarModules[moduleIndex] = btn
        return btn
    end

    local function CreateSubTab(parent, id, text, xOffset)
        local tab = CreateFrame("Button", "ConsumeTracker_SubTab_" .. id, parent)
        tab:SetWidth(100)
        tab:SetHeight(24)
        tab:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, -40) -- Positioned below title area roughly

        -- Text
        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tabText:SetText(text)
        tabText:SetTextColor(0.6, 0.6, 0.6) -- Default Gray
        tab.text = tabText

        -- Active Indicator (Bottom Line)
        local activeLine = tab:CreateTexture(nil, "OVERLAY")
        -- activeLine:SetTexture(1, 0.82, 0, 1)
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

    -- Create "Consume Tracking" Sidebar Module
    local module1 = CreateSidebarModule("ConsumeTracker_Module1", "Interface\\AddOns\\ConsumeTracker\\images\\minimap_icon", -50, "Consume Tracking", 1)

    -- Send Data Button placeholder - will be created after module1Content
    -- (moved to after subTabs creation)

    -- Module Content Frames
    ConsumeTracker_MainFrame.modules = {}
    
    -- Consume Tracking Content Frame (Container for the sub-tabs)
    local module1Content = CreateFrame("Frame", nil, ConsumeTracker_MainFrame)
    module1Content:SetPoint("TOPLEFT", ConsumeTracker_MainFrame, "TOPLEFT", 185, -5) -- Right of sidebar
    module1Content:SetPoint("BOTTOMRIGHT", ConsumeTracker_MainFrame, "BOTTOMRIGHT", -5, 5)
    module1Content:Hide()
    ConsumeTracker_MainFrame.modules[1] = module1Content

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
    
    -- Checkmark text (hidden by default)
    -- Checkmark texture (hidden by default)
    local checkmark = sendDataButton:CreateTexture(nil, "OVERLAY")
    checkmark:SetTexture("Interface\\AddOns\\ConsumeTracker\\images\\checkmark.tga")
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
    
    sendDataButton:SetScript("OnClick", function() PushData() end)
    
    function updateSenDataButtonState()
        if ConsumeTracker_Options.Channel == nil or ConsumeTracker_Options.Channel == "" or ConsumeTracker_Options.Password == nil or ConsumeTracker_Options.Password == "" then
            sendDataButton:Hide()
            ReadData("stop")
        else
            sendDataButton:Show()
            ReadData("start")
        end
    end
    updateSenDataButtonState()

    -- Sub-Tab Content Frames
    module1Content.tabFrames = {}
    
    -- Common Content Rect
    local contentWidth = 590 
    local contentHeight = 420 -- Reduced height due to tabs on top
    local contentX = 10
    local contentY = -70 -- Below horizontal tabs

    -- Tab 1: Tracker Content
    local tab1Frame = CreateFrame("Frame", nil, module1Content)
    tab1Frame:SetWidth(contentWidth)
    tab1Frame:SetHeight(contentHeight)
    tab1Frame:SetPoint("TOPLEFT", module1Content, "TOPLEFT", contentX, contentY)
    tab1Frame:Hide() -- Hide by default
    module1Content.tabFrames[1] = tab1Frame

    -- Tab 2: Items Content
    local tab2Frame = CreateFrame("Frame", nil, module1Content)
    tab2Frame:SetWidth(contentWidth)
    tab2Frame:SetHeight(contentHeight)
    tab2Frame:SetPoint("TOPLEFT", module1Content, "TOPLEFT", contentX, contentY)
    tab2Frame:Hide() -- Hide by default
    module1Content.tabFrames[2] = tab2Frame

    -- Tab 3: Presets Content
    local tab3Frame = CreateFrame("Frame", nil, module1Content)
    tab3Frame:SetWidth(contentWidth)
    tab3Frame:SetHeight(contentHeight)
    tab3Frame:SetPoint("TOPLEFT", module1Content, "TOPLEFT", contentX, contentY)
    tab3Frame:Hide() -- Hide by default
    module1Content.tabFrames[3] = tab3Frame

    -- Tab 4: Settings Content
    local tab4Frame = CreateFrame("Frame", nil, module1Content)
    tab4Frame:SetWidth(contentWidth)
    tab4Frame:SetHeight(contentHeight)
    tab4Frame:SetPoint("TOPLEFT", module1Content, "TOPLEFT", contentX, contentY)
    tab4Frame:Hide() -- Hide by default
    module1Content.tabFrames[4] = tab4Frame

    -- Map old structure for compatibility if needed (temporarily)
    ConsumeTracker_MainFrame.tabs = {}
    ConsumeTracker_MainFrame.tabs[1] = tab1Frame 
    ConsumeTracker_MainFrame.tabs[2] = tab2Frame
    ConsumeTracker_MainFrame.tabs[3] = tab3Frame
    ConsumeTracker_MainFrame.tabs[4] = tab4Frame

    -- Footer Button to Push Database
    local footerText = ConsumeTracker_MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footerText:SetText("Made by Astraeya (v" .. GetAddOnMetadata("ConsumeTracker", "Version") .. ")")
    footerText:SetTextColor(0.6, 0.6, 0.6)
    footerText:SetPoint("BOTTOM", ConsumeTracker_MainFrame, "BOTTOMLEFT", 90, 10) -- Centered in 180px sidebar

    -- Add Custom Content for Tabs
    ConsumeTracker_CreateManagerContent(tab1Frame)
    ConsumeTracker_CreateItemsContent(tab2Frame)
    ConsumeTracker_CreatePresetsContent(tab3Frame)
    ConsumeTracker_CreateSettingsContent(tab4Frame)

    ConsumeTracker_UpdateTabStates()
end

function ConsumeTracker_ShowMainWindow()
    if not ConsumeTracker_MainFrame then
        ConsumeTracker_CreateMainWindow()
    end
    ConsumeTracker_MainFrame:Show()
    
    -- Scan inventory when the window is opened
    ConsumeTracker_ScanPlayerInventory()
    
    -- Only scan bank and mail if they are open
    if event == "BANKFRAME_OPENED" then
        ConsumeTracker_ScanPlayerBank()
    end
    if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        ConsumeTracker_ScanPlayerMail()
    end
    
    -- Update the tabs based on whether bank and mail have been scanned
    ConsumeTracker_UpdateTabStates()
    
    -- Update the Manager content
    ConsumeTracker_UpdateManagerContent()
    
    -- Update the Presets content
    ConsumeTracker_UpdatePresetsConsumables()
    
    -- Update Settings content
    ConsumeTracker_UpdateSettingsContent()
end

function ConsumeTracker_ShowModule(moduleIndex)
    -- Hide all modules
    for i, moduleFrame in pairs(ConsumeTracker_MainFrame.modules) do
        moduleFrame:Hide()
        if ConsumeTracker_SidebarModules[i] then
            ConsumeTracker_SidebarModules[i].activeBar:Hide()
            -- Reset to transparent gradient
            ConsumeTracker_SidebarModules[i].bg:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0, 1, 0.82, 0, 0)
        end
    end

    -- Show selected
    local selectedModule = ConsumeTracker_MainFrame.modules[moduleIndex]
    if selectedModule then
        selectedModule:Show()
        if ConsumeTracker_SidebarModules[moduleIndex] then
            ConsumeTracker_SidebarModules[moduleIndex].activeBar:Show()
            -- Set to visible gradient: Left=Gold(0.5 alpha), Right=Gold(0 alpha) 
            ConsumeTracker_SidebarModules[moduleIndex].bg:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.5, 1, 0.82, 0, 0)
        end
        
        -- Force update sub-tabs if this module has them (Module 1)
        if moduleIndex == 1 then
            ConsumeTracker_ShowSubTab(1)
        end
    end
end

function ConsumeTracker_ShowSubTab(tabIndex)
    -- We assume we are in Module 1 for now, as it's the only one with subtabs
    local module1Content = ConsumeTracker_MainFrame.modules[1]
    if not module1Content then return end

    for i, tabFrame in pairs(module1Content.tabFrames) do
        if i == tabIndex then
            tabFrame:Show()
            if module1Content.subTabs[i] then
                -- Active: Yellow
                module1Content.subTabs[i].text:SetTextColor(1, 0.82, 0)
            end
        else
            tabFrame:Hide()
            if module1Content.subTabs[i] then
                -- Inactive: Gray
                module1Content.subTabs[i].text:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end

    -- Trigger existing update functions based on tab
    if tabIndex == 1 then
        ConsumeTracker_UpdateManagerContent()
    elseif tabIndex == 2 then
        -- Update Items
    elseif tabIndex == 3 then
        ConsumeTracker_UpdatePresetsConsumables()
    elseif tabIndex == 4 then
        ConsumeTracker_UpdateSettingsContent()
    end
end

-- Backward compatibility function if called elsewhere
function ConsumeTracker_ShowTab(tabIndex)
    ConsumeTracker_ShowModule(1)
    ConsumeTracker_ShowSubTab(tabIndex)
end



-- Tracker Window -----------------------------------------------------------------------------------
function ConsumeTracker_CreateManagerContent(parentFrame)
    -- Initialize sort order if not set
    ConsumeTracker_Options.sortOrder = ConsumeTracker_Options.sortOrder or "name"
    ConsumeTracker_Options.sortDirection = ConsumeTracker_Options.sortDirection or "asc"

    -- ==========================
    -- Tracker Search Box
    -- ==========================
    local trackerSearchBox = CreateFrame("EditBox", "ConsumeTracker_TrackerSearchBox", parentFrame, "InputBoxTemplate")
    trackerSearchBox:SetWidth(WindowWidth - 50)
    trackerSearchBox:SetHeight(25)
    trackerSearchBox:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, -5)
    trackerSearchBox:SetAutoFocus(false)
    trackerSearchBox:SetText("Search...")
    trackerSearchBox:SetTextColor(0.5, 0.5, 0.5)

    trackerSearchBox:SetScript("OnEditFocusGained", function()
        if this:GetText() == "Search..." then
            this:SetText("")
            this:SetTextColor(1, 1, 1)
        end
    end)

    trackerSearchBox:SetScript("OnEditFocusLost", function()
        if this:GetText() == "" then
            this:SetText("Search...")
            this:SetTextColor(0.5, 0.5, 0.5)
        end
    end)

    trackerSearchBox:SetScript("OnTextChanged", function()
        ConsumeTracker_UpdateManagerContent()
    end)

    parentFrame.searchBox = trackerSearchBox





    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "ConsumeTracker_ManagerScrollFrame", parentFrame)
    scrollFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, -35) -- Adjusted to be below the search box
    scrollFrame:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -20, 16)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
        local delta = arg1
        local current = this:GetVerticalScroll()
        local maxScroll = this.range or 0
        local newScroll = math.max(0, math.min(current - (delta * 20), maxScroll))
        this:SetVerticalScroll(newScroll)
        parentFrame.scrollBar:SetValue(newScroll)
    end)

    -- Scroll Child Frame
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(WindowWidth - 10)
    scrollChild:SetHeight(1)  -- Will adjust later
    scrollFrame:SetScrollChild(scrollChild)
    parentFrame.scrollChild = scrollChild
    parentFrame.scrollFrame = scrollFrame

    -- Initialize data structures
    parentFrame.categoryInfo = {}
    local index = 0 -- Position index
    local lineHeight = 18

    -- Sort categories alphabetically
    local sortedCategories = {}
    for categoryName, _ in pairs(consumablesCategories) do
        table.insert(sortedCategories, categoryName)
    end
    table.sort(sortedCategories)

    -- Iterate over sorted categories
    for _, categoryKey in ipairs(sortedCategories) do
        local categoryData = consumablesCategories[categoryKey]
        local categoryName = categoryData.name
        
        local consumables = {}
        if categoryData.items then
            for id, item in pairs(categoryData.items) do
                item.id = id
                table.insert(consumables, item)
            end
        end

        -- Create category label
        local categoryLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        categoryLabel:SetText(categoryName)
        categoryLabel:SetTextColor(1, 1, 1)
        categoryLabel:Show()

        local categoryInfo = { name = categoryName, label = categoryLabel, Items = {} }

        index = index + 1  -- Position for the category label

        local numItemsInCategory = 0  -- Counter for items in this category

        -- Sort the consumables by name
        table.sort(consumables, function(a, b) return a.name < b.name end)

        -- For each consumable in the category
        for _, consumable in ipairs(consumables) do
            local itemID = consumable.id
            local itemName = consumable.name

            -- Create a frame that encompasses the button and label
            local itemFrame = CreateFrame("Frame", "ConsumeTracker_ManagerItemFrame" .. index, scrollChild)
            itemFrame:SetWidth(WindowWidth - 10)
            itemFrame:SetHeight(lineHeight)
            itemFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, - (index) * lineHeight)
            itemFrame:Hide()
            itemFrame:EnableMouse(true)

            -- Create the 'Use' button inside the itemFrame (Custom Gold Theme)
            local useButton = CreateFrame("Button", "ConsumeTracker_UseButton" .. index, itemFrame)
            useButton:SetWidth(36)
            useButton:SetHeight(16)
            useButton:SetPoint("LEFT", itemFrame, "LEFT", 0, 0)
            
            useButton:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            useButton:SetBackdropColor(0, 0, 0, 0) 
            useButton:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold border

            local btnText = useButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btnText:SetPoint("CENTER", useButton, "CENTER", 0, 0)
            btnText:SetText("USE")
            btnText:SetTextColor(1, 0.82, 0) -- Gold text
            useButton.text = btnText

            -- Hover Effects
            useButton:SetScript("OnEnter", function()
                if this:IsEnabled() == 1 then
                    this:SetBackdropBorderColor(1, 1, 1, 1)
                    this.text:SetTextColor(1, 1, 1)
                end
            end)
            useButton:SetScript("OnLeave", function()
                if this:IsEnabled() == 1 then
                    this:SetBackdropBorderColor(1, 0.82, 0, 1)
                    this.text:SetTextColor(1, 0.82, 0)
                else
                    this:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
                    this.text:SetTextColor(0.5, 0.5, 0.5)
                end
            end)

            -- Initially show or hide the use button based on settings
            if ConsumeTracker_Options.showUseButton then
                useButton:Show()
            else
                useButton:Hide()
            end

            -- Set up the button OnClick handler
            useButton:SetScript("OnClick", function()
                local bag, slot = ConsumeTracker_FindItemInBags(itemID)
                if bag and slot then
                    UseContainerItem(bag, slot)
                else
                    DEFAULT_CHAT_FRAME:AddMessage("Item not found in bags.")
                end
            end)

            -- Item Icon
            local icon = itemFrame:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(14)
            icon:SetHeight(14)
            -- Position relative to Use Button if shown, else left edge
            if ConsumeTracker_Options.showUseButton then
                icon:SetPoint("LEFT", useButton, "RIGHT", 4, 0)
            else
                icon:SetPoint("LEFT", itemFrame, "LEFT", 0, 0)
            end
            
            -- Try fetching texture
            local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
            if not itemTexture and consumable.texture then itemTexture = consumable.texture end
            if not itemTexture then itemTexture = "Interface\\Icons\\INV_Misc_QuestionMark" end
            icon:SetTexture(itemTexture)
            
            -- Item Name Label
            local label = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            label:SetText(itemName)
            label:SetJustifyH("LEFT")

            -- Quantity Label
            local qtyLabel = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            qtyLabel:SetPoint("RIGHT", itemFrame, "RIGHT", -20, 0)
            qtyLabel:SetText("")

            -- Initialize button state
            useButton:Disable()
            useButton:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            btnText:SetTextColor(0.5, 0.5, 0.5)

            -- Mouseover Tooltip
            itemFrame:SetScript("OnEnter", function()
                ConsumeTracker_ShowConsumableTooltip(itemID)
            end)
            itemFrame:SetScript("OnLeave", function()
                if ConsumeTracker_CustomTooltip then
                    ConsumeTracker_CustomTooltip:Hide()
                end
            end)

            -- Store item info
            table.insert(categoryInfo.Items, {
                frame = itemFrame,
                label = label,
                qtyLabel = qtyLabel,
                icon = icon,
                name = itemName,
                itemID = itemID,
                button = useButton
            })

            index = index + 1  -- Increment index after adding item
            numItemsInCategory = numItemsInCategory + 1  -- Increment item count
        end

        -- Position the category label above its items
        categoryLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, - (index - numItemsInCategory - 1) * lineHeight)

        -- Store category info
        table.insert(parentFrame.categoryInfo, categoryInfo)

        -- Add extra spacing after the category
        index = index + 1  -- Add one extra line of spacing between categories
    end

    -- Adjust the scroll child height
    scrollChild.contentHeight = (index - 1) * lineHeight
    scrollChild:SetHeight(scrollChild.contentHeight)

    -- Message Label (adjusted to be a child of parentFrame)
    local messageLabel = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageLabel:SetText("|cffff0000No consumables selected|r\n\n|cffffffffClick on |rItems|cffffffff to get started|r")
    messageLabel:SetPoint("CENTER", parentFrame, "CENTER", 0, 0)
    messageLabel:Hide()  -- Initially hidden
    parentFrame.messageLabel = messageLabel

    -- Scroll Bar
    -- Scroll Bar (Minimalist)
    local scrollBar = CreateFrame("Slider", "ConsumeTracker_ManagerScrollBar", parentFrame)
    scrollBar:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -5, -35) 
    scrollBar:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -5, 10)
    scrollBar:SetWidth(6)
    scrollBar:SetOrientation('VERTICAL')
    
    -- Background (Track)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollBar)
    track:SetTexture(0, 0, 0, 0.4)
    
    -- Thumb
    scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = scrollBar:GetThumbTexture()
    thumb:SetVertexColor(1, 0.82, 0, 0.8) -- Gold
    thumb:SetWidth(6)
    thumb:SetHeight(30)
    scrollBar:SetScript("OnValueChanged", function()
        local value = this:GetValue()
        parentFrame.scrollFrame:SetVerticalScroll(value)
    end)
    parentFrame.scrollBar = scrollBar

    -- Initially hide the scrollbar
    scrollBar:Hide()
end

function ConsumeTracker_UpdateManagerContent()
    if not ConsumeTracker_MainFrame or not ConsumeTracker_MainFrame.tabs or not ConsumeTracker_MainFrame.tabs[1] then
        return
    end

    local ManagerFrame = ConsumeTracker_MainFrame.tabs[1]
    local realmName = GetRealmName()
    local playerName = UnitName("player")

    -- Read Tracker filter text (if present)
    local filterText = ""
    if ManagerFrame and ManagerFrame.searchBox and ManagerFrame.searchBox:GetText() then
        filterText = string.lower(ManagerFrame.searchBox:GetText())
        if filterText == "search..." then
            filterText = ""
        end
    end

    -- Ensure data structure exists
    if not ConsumeTracker_Data[realmName] then
        ConsumeTracker_Data[realmName] = {}
    end
    
    -- Hide the message label and order buttons by default
    ManagerFrame.messageLabel:Hide()


    -- Hide all item frames and category labels
    for _, categoryInfo in ipairs(ManagerFrame.categoryInfo) do
        categoryInfo.label:Hide()
        for _, itemInfo in ipairs(categoryInfo.Items) do
            itemInfo.frame:Hide()
        end
    end

    -- Reset the scrollChild height
    ManagerFrame.scrollChild.contentHeight = 0
    ManagerFrame.scrollChild:SetHeight(0)

    -- Check if bank and mail have been scanned for current character
    local currentCharData = ConsumeTracker_Data[realmName][playerName]
    local bankScanned = currentCharData and currentCharData["bank"] ~= nil
    local mailScanned = currentCharData and currentCharData["mail"] ~= nil

    if not bankScanned or not mailScanned then
        -- Show message
        ManagerFrame.messageLabel:SetText("|cffff0000This character is not scanned yet|r\n\n|cffffffffOpen your |rBank|cffffffff and |rMail|cffffffff to get started|r")
        ManagerFrame.messageLabel:Show()

        -- Update the Manager scrollbar
        ConsumeTracker_UpdateManagerScrollBar()

        return
    end

    -- Proceed with normal content update
    local index = 0  -- Positioning index for items
    local hasAnyVisibleItems = false  -- Track if any items are visible
    local lineHeight = 18

    -- Get the current sort order and direction
    local sortOrder = ConsumeTracker_Options.sortOrder or "name"
    local sortDirection = ConsumeTracker_Options.sortDirection or "asc"

    local enableCategories = ConsumeTracker_Options.enableCategories or false
    local showUseButton = ConsumeTracker_Options.showUseButton or false

    -- Check if categories are enabled
    if ConsumeTracker_Options.enableCategories then
        -- Iterate over categories
        for _, categoryInfo in ipairs(ManagerFrame.categoryInfo) do
            local anyItemVisible = false

            -- First, collect the enabled items and their counts
            local enabledItems = {}

            for _, itemInfo in ipairs(categoryInfo.Items) do
                local itemID = itemInfo.itemID
                local nameMatches = (filterText == "" or string.find(string.lower(itemInfo.name), filterText, 1, true))
                if ConsumeTracker_SelectedItems[itemID] and nameMatches then
                    -- Sum counts across all selected characters
                    local totalCount = 0
                    for character, _ in pairs(ConsumeTracker_Data[realmName]) do
                        if type(ConsumeTracker_Data[realmName][character]) == "table" and ConsumeTracker_Options["Characters"][character] == true then
                            -- Make sure it's not a special field like "faction"
                            if character ~= "faction" then
                                local inventory = ConsumeTracker_Data[realmName][character]["inventory"] and ConsumeTracker_Data[realmName][character]["inventory"][itemID] or 0
                                local bank = ConsumeTracker_Data[realmName][character]["bank"] and ConsumeTracker_Data[realmName][character]["bank"][itemID] or 0
                                local mail = ConsumeTracker_Data[realmName][character]["mail"] and ConsumeTracker_Data[realmName][character]["mail"][itemID] or 0
                                totalCount = totalCount + inventory + bank + mail
                            end
                        end
                    end
                    table.insert(enabledItems, {itemInfo = itemInfo, totalCount = totalCount})
                    anyItemVisible = true
                else
                    itemInfo.frame:Hide()
                end
            end

            -- If any items are visible, handle category label
            if anyItemVisible then
                categoryInfo.label:SetPoint("TOPLEFT", ManagerFrame.scrollChild, "TOPLEFT", 0, - (index) * lineHeight)
                categoryInfo.label:Show()
                index = index + 1

                -- Sort enabled items based on sort order and direction
                if sortOrder == "name" then
                    if sortDirection == "asc" then
                        table.sort(enabledItems, function(a, b) return a.itemInfo.name < b.itemInfo.name end)
                    else
                        table.sort(enabledItems, function(a, b) return a.itemInfo.name > b.itemInfo.name end)
                    end
                elseif sortOrder == "amount" then
                    if sortDirection == "desc" then
                        table.sort(enabledItems, function(a, b) return a.totalCount > b.totalCount end)
                    else
                        table.sort(enabledItems, function(a, b) return a.totalCount < b.totalCount end)
                    end
                end

                -- Now, position and show the enabled items
                for _, itemData in ipairs(enabledItems) do
                    local itemInfo = itemData.itemInfo
                    local itemID = itemInfo.itemID
                    local itemName = itemInfo.name
                    local label = itemInfo.label
                    local qtyLabel = itemInfo.qtyLabel
                    local icon = itemInfo.icon
                    local button = itemInfo.button
                    local frame = itemInfo.frame
                    local totalCount = itemData.totalCount

                    -- Update label text (Name only) and color
                    label:SetText(itemName)
                    label:SetTextColor(1, 1, 1)

                    -- Update Quantity Label
                    qtyLabel:SetText(totalCount)

                    -- Adjust quantity label color based on count
                    if totalCount == 0 then
                        qtyLabel:SetTextColor(1, 0, 0)  -- Red
                    elseif totalCount < 10 then
                        qtyLabel:SetTextColor(1, 0.4, 0)  -- Orange
                    elseif totalCount <= 19 then
                        qtyLabel:SetTextColor(1, 0.85, 0)  -- Yellow
                    else
                        qtyLabel:SetTextColor(0, 1, 0)  -- Green
                    end

                    -- Enable or disable the 'Use' button based on whether the item is in the player's inventory
                    local playerInventory = ConsumeTracker_Data[realmName][playerName]["inventory"] or {}
                    local countInInventory = playerInventory[itemID] or 0
                    local inBags = (countInInventory > 0)

                    if ConsumeTracker_Options.showUseButton then
                        button:Show()
                        if inBags then
                            button:Enable()
                            button:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold
                            button.text:SetTextColor(1, 0.82, 0)
                        else
                            button:Disable()
                            button:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) -- Gray
                            button.text:SetTextColor(0.5, 0.5, 0.5)
                        end
                        -- Align icon to button
                        icon:SetPoint("LEFT", button, "RIGHT", 4, 0)
                    else
                        button:Disable()
                        button:Hide()
                        -- Align icon to left edge
                        icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
                    end

                    -- Show and position the item frame
                    frame:SetPoint("TOPLEFT", ManagerFrame.scrollChild, "TOPLEFT", 0, - (index) * lineHeight)
                    frame:Show()
                    index = index + 1
                    hasAnyVisibleItems = true
                end

                -- Add extra spacing after the category
                index = index + 1  -- Add one extra line of spacing between categories
            else
                categoryInfo.label:Hide()
                -- Hide all items under this category
                for _, itemInfo in ipairs(categoryInfo.Items) do
                    itemInfo.frame:Hide()
                end
            end
        end
    else
        -- Categories are disabled
        -- Collect all enabled items into a single list with their counts
        local allItems = {}
        for _, categoryInfo in ipairs(ManagerFrame.categoryInfo) do
            categoryInfo.label:Hide()
            for _, itemInfo in ipairs(categoryInfo.Items) do
                local itemID = itemInfo.itemID
                local nameMatches = (filterText == "" or string.find(string.lower(itemInfo.name), filterText, 1, true))
                if ConsumeTracker_SelectedItems[itemID] and nameMatches then
                    -- Sum counts across all selected characters
                    local totalCount = 0
                    for character, charData in pairs(ConsumeTracker_Data[realmName]) do
                        if type(charData) == "table" and ConsumeTracker_Options["Characters"][character] == true then
                            if character ~= "faction" then
                                local inventory = charData["inventory"] and charData["inventory"][itemID] or 0
                                local bank = charData["bank"] and charData["bank"][itemID] or 0
                                local mail = charData["mail"] and charData["mail"][itemID] or 0
                                totalCount = totalCount + inventory + bank + mail
                            end
                        end
                    end
                    table.insert(allItems, {itemInfo = itemInfo, totalCount = totalCount})
                    hasAnyVisibleItems = true
                else
                    itemInfo.frame:Hide()
                end
            end
        end

        -- Sort allItems based on sort order and direction
        if sortOrder == "name" then
            if sortDirection == "asc" then
                table.sort(allItems, function(a, b) return a.itemInfo.name < b.itemInfo.name end)
            else
                table.sort(allItems, function(a, b) return a.itemInfo.name > b.itemInfo.name end)
            end
        elseif sortOrder == "amount" then
            if sortDirection == "desc" then
                table.sort(allItems, function(a, b) return a.totalCount > b.totalCount end)
            else
                table.sort(allItems, function(a, b) return a.totalCount < b.totalCount end)
            end
        end

        -- Display all items
        for _, itemData in ipairs(allItems) do
            local itemInfo = itemData.itemInfo
            local itemID = itemInfo.itemID
            local itemName = itemInfo.name
            local label = itemInfo.label
            local qtyLabel = itemInfo.qtyLabel
            local icon = itemInfo.icon
            local button = itemInfo.button
            local frame = itemInfo.frame
            local totalCount = itemData.totalCount

            -- Update label text (Name only) and color
            label:SetText(itemName)
            label:SetTextColor(1, 1, 1)

            -- Update Quantity Label
            qtyLabel:SetText(totalCount)

            -- Adjust quantity label color based on count
            if totalCount == 0 then
                qtyLabel:SetTextColor(1, 0, 0)  -- Red
            elseif totalCount < 10 then
                qtyLabel:SetTextColor(1, 0.4, 0)  -- Orange
            elseif totalCount <= 20 then
                qtyLabel:SetTextColor(1, 0.85, 0)  -- Yellow
            else
                qtyLabel:SetTextColor(0, 1, 0)  -- Green
            end

            -- Enable or disable the 'Use' button based on whether the item is in the player's inventory
            local playerInventory = ConsumeTracker_Data[realmName][playerName]["inventory"] or {}
            local countInInventory = playerInventory[itemID] or 0
            local inBags = (countInInventory > 0)

            if ConsumeTracker_Options.showUseButton then
                button:Show()
                if inBags then
                    button:Enable()
                    button:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold
                    button.text:SetTextColor(1, 0.82, 0)
                else
                    button:Disable()
                    button:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) -- Gray
                    button.text:SetTextColor(0.5, 0.5, 0.5)
                end
                -- Align icon to button
                icon:SetPoint("LEFT", button, "RIGHT", 4, 0)
            else
                button:Disable()
                button:Hide()
                -- Align icon to left edge
                icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
            end

            -- Show and position the item frame
            frame:SetPoint("TOPLEFT", ManagerFrame.scrollChild, "TOPLEFT", 0, - (index) * lineHeight)
            frame:Show()
            index = index + 1
        end
    end

    -- Adjust the scroll child height
    ManagerFrame.scrollChild.contentHeight = index * lineHeight
    ManagerFrame.scrollChild:SetHeight(ManagerFrame.scrollChild.contentHeight)

    -- Update the scrollbar
    ConsumeTracker_UpdateManagerScrollBar()

    if not hasAnyVisibleItems then
        -- Hide the order buttons

        -- Show message when no items are selected
        ManagerFrame.messageLabel:SetText("|cffff0000No consumables selected|r\n\n|cffffffffClick on |rItems|cffffffff to get started|r")
        ManagerFrame.messageLabel:Show()

        -- Reset the scrollChild height
        ManagerFrame.scrollChild.contentHeight = 0
        ManagerFrame.scrollChild:SetHeight(0)

        -- Update the scrollbar
        ConsumeTracker_UpdateManagerScrollBar()
    else
        -- Show the order buttons

        -- Hide the message label as we have content to display
        ManagerFrame.messageLabel:Hide()
    end
    ConsumeTracker_UpdateActionBar()
end

function ConsumeTracker_UpdateManagerScrollBar()
    local ManagerFrame = ConsumeTracker_MainFrame.tabs[1]
    local scrollBar = ManagerFrame.scrollBar
    local scrollFrame = ManagerFrame.scrollFrame
    local scrollChild = ManagerFrame.scrollChild

    local totalHeight = scrollChild:GetHeight()
    local shownHeight = ManagerFrame:GetHeight() - 20  -- Account for padding/margins

    if totalHeight > shownHeight then
        local maxScroll = totalHeight - shownHeight
        scrollFrame.range = maxScroll  -- Set the scroll range
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(math.min(scrollBar:GetValue(), maxScroll))
        scrollBar:Show()
    else
        scrollFrame.range = 0  -- Also handle this case
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        scrollBar:Hide()
    end
end



-- Items Window -----------------------------------------------------------------------------------
function ConsumeTracker_CreateItemsContent(parentFrame)
    -- Create Search Input
    local searchBox = CreateFrame("EditBox", "ConsumeTracker_SearchBox", parentFrame, "InputBoxTemplate")
    searchBox:SetWidth(WindowWidth - 160) -- Reduced width to make room for filter
    searchBox:SetHeight(25)
    searchBox:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, -5)
    searchBox:SetAutoFocus(false)
    searchBox:SetText("Search...")
    searchBox:SetTextColor(0.5, 0.5, 0.5) -- Placeholder text color

    searchBox:SetScript("OnEditFocusGained", function()
        if this:GetText() == "Search..." then
            this:SetText("")
            this:SetTextColor(1, 1, 1) -- User input text color
        end
    end)

    searchBox:SetScript("OnEditFocusLost", function()
        if this:GetText() == "" then
            this:SetText("Search...")
            this:SetTextColor(0.5, 0.5, 0.5) -- Placeholder text color
        end
    end)

    -- Filter Settings
    parentFrame.filterType = "All"

    -- Filter Label
    local filterLabel = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    filterLabel:SetText("Filter")
    
    -- Filter Dropdown Button
    local filterButton = CreateFrame("Button", "ConsumeTracker_FilterButton", parentFrame)
    filterButton:SetWidth(24)
    filterButton:SetHeight(24)
    filterButton:SetPoint("LEFT", filterLabel, "RIGHT", 5, 0)
    
    -- Filter Button Arrow Texture
    local arrow = filterButton:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetPoint("CENTER", filterButton, "CENTER", 0, 0)
    filterButton.arrow = arrow

    -- Filter Dropdown Menu Frame (Hidden, used for menu logic)
    local filterMenu = CreateFrame("Frame", "ConsumeTracker_FilterMenu", parentFrame, "UIDropDownMenuTemplate")

    -- Filter Button Click Handler
    filterButton:SetScript("OnClick", function()
        UIDropDownMenu_Initialize(filterMenu, function()
            local info = {}
            
            info = {}
            info.text = "All"
            info.checked = (parentFrame.filterType == "All")
            info.func = function() 
                parentFrame.filterType = "All" 
                -- We need to find the UpdateFilter function. Since it's local inside CreateItemsContent, 
                -- we might need to expose it or trigger the search box OnTextChanged which calls it.
                -- For now, let's trigger OnTextChanged manually or store UpdateFilter on parentFrame.
                if parentFrame.UpdateFilterFunc then parentFrame.UpdateFilterFunc() end
            end
            UIDropDownMenu_AddButton(info)

            info = {}
            info.text = "|cff00ff00Available|r" -- Green
            info.checked = (parentFrame.filterType == "Available")
            info.func = function() 
                parentFrame.filterType = "Available"
                if parentFrame.UpdateFilterFunc then parentFrame.UpdateFilterFunc() end
            end
            UIDropDownMenu_AddButton(info)

            info = {}
            info.text = "|cffff0000Unavailable|r" -- Red
            info.checked = (parentFrame.filterType == "Unavailable")
            info.func = function() 
                parentFrame.filterType = "Unavailable"
                if parentFrame.UpdateFilterFunc then parentFrame.UpdateFilterFunc() end
            end
            UIDropDownMenu_AddButton(info)
        end, "MENU")
        ToggleDropDownMenu(1, nil, filterMenu, filterButton, 0, 0)
    end)

    -- Box around button (optional visual to match screenshot style roughly)
    local btnBorder = CreateFrame("Frame", nil, filterButton)
    btnBorder:SetAllPoints(filterButton)
    btnBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })

    -- Function to update the filter
    local function UpdateFilter()
        local filterText = string.lower(searchBox:GetText())
        if filterText == "search..." then filterText = "" end
        local index = 0 -- Position index
        local lineHeight = 18
        
        -- Get filter type
        local filterType = parentFrame.filterType or "All"
        local realmName = GetRealmName()
        local playerName = UnitName("player")

        -- Iterate over categories
        for _, categoryInfo in ipairs(parentFrame.categoryInfo) do
            local categoryLabel = categoryInfo.label
            local anyitemVisible = false

            -- First, check if any Items in the category match the filter
            for _, itemInfo in ipairs(categoryInfo.Items) do
                local itemNameLower = string.lower(itemInfo.name)
                local itemID = itemInfo.itemID
                
                -- Check Search
                local searchMatch = (filterText == "" or string.find(itemNameLower, filterText, 1, true))
                
                -- Check Availability
                local availabilityMatch = true
                if filterType ~= "All" then
                    local playerInventory = (ConsumeTracker_Data[realmName] and 
                                           ConsumeTracker_Data[realmName][playerName] and 
                                           ConsumeTracker_Data[realmName][playerName].inventory) or {}
                    local countInInventory = playerInventory[itemID] or 0
                    
                    if filterType == "Available" then
                        availabilityMatch = (countInInventory > 0)
                    elseif filterType == "Unavailable" then
                        availabilityMatch = (countInInventory == 0)
                    end
                end

                if searchMatch and availabilityMatch then
                    anyitemVisible = true
                    break
                end
            end

            -- If any Items are visible, show the category label
            if anyitemVisible then
                categoryLabel:SetPoint("TOPLEFT", parentFrame.scrollChild, "TOPLEFT", 0, - (index) * lineHeight)
                categoryLabel:Show()
                index = index + 1

                -- Now, position and show the matching Items
                for _, itemInfo in ipairs(categoryInfo.Items) do
                    local itemFrame = itemInfo.frame
                    local itemNameLower = string.lower(itemInfo.name)
                    local itemID = itemInfo.itemID

                    -- Check Search
                    local searchMatch = (filterText == "" or string.find(itemNameLower, filterText, 1, true))
                    
                    -- Check Availability
                    local availabilityMatch = true
                    if filterType ~= "All" then
                        local playerInventory = (ConsumeTracker_Data[realmName] and 
                                               ConsumeTracker_Data[realmName][playerName] and 
                                               ConsumeTracker_Data[realmName][playerName].inventory) or {}
                        local countInInventory = playerInventory[itemID] or 0
                        
                        if filterType == "Available" then
                            availabilityMatch = (countInInventory > 0)
                        elseif filterType == "Unavailable" then
                            availabilityMatch = (countInInventory == 0)
                        end
                    end

                    if searchMatch and availabilityMatch then
                        -- Show the item
                        itemFrame:SetPoint("TOPLEFT", parentFrame.scrollChild, "TOPLEFT", 0, - (index) * lineHeight)
                        itemFrame:Show()
                        
                        -- Update Qty Label (Dynamically update count even if not filtering)
                        if itemInfo.qtyLabel then
                             local playerInventory = (ConsumeTracker_Data[realmName] and 
                                               ConsumeTracker_Data[realmName][playerName] and 
                                               ConsumeTracker_Data[realmName][playerName].inventory) or {}
                             local count = playerInventory[itemID] or 0
                             itemInfo.qtyLabel:SetText(count)
                             if count > 0 then
                                itemInfo.qtyLabel:SetTextColor(0, 1, 0) -- Green
                             else
                                itemInfo.qtyLabel:SetTextColor(0.5, 0.5, 0.5) -- Gray
                             end
                        end
                        
                        index = index + 1
                    else
                        itemFrame:Hide()
                    end
                end

                -- Add extra spacing after the category
                index = index + 1  -- Add one extra line of spacing between categories

            else
                categoryLabel:Hide()
                -- Hide all Items under this category
                for _, itemInfo in ipairs(categoryInfo.Items) do
                    itemInfo.frame:Hide()
                end
            end
        end

        -- Adjust the scroll child height
        parentFrame.scrollChild.contentHeight = index * lineHeight
        parentFrame.scrollChild:SetHeight(parentFrame.scrollChild.contentHeight)

        -- Update the scrollbar
        ConsumeTracker_UpdateItemsScrollBar()
    end
    
    parentFrame.UpdateFilterFunc = UpdateFilter

    searchBox:SetScript("OnTextChanged", function()
        UpdateFilter()
    end)

    -- Adjust the size of the scroll frame to make room for the search box and add extra spacing
    local scrollFrame = CreateFrame("ScrollFrame", "ConsumeTracker_ItemsScrollFrame", parentFrame)
    scrollFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, -40)  -- Start below the search box
    scrollFrame:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -20, 60) -- Leave space for buttons
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
        local delta = arg1
        local current = this:GetVerticalScroll()
        local maxScroll = this.maxScroll or 0
        local newScroll = math.max(0, math.min(current - (delta * 20), maxScroll))
        this:SetVerticalScroll(newScroll)
        parentFrame.scrollBar:SetValue(newScroll)
    end)

    -- Scroll Child Frame
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(WindowWidth - 10)
    scrollChild:SetHeight(1)  -- Will adjust later
    scrollFrame:SetScrollChild(scrollChild)
    parentFrame.scrollChild = scrollChild
    parentFrame.scrollFrame = scrollFrame

    -- Sort categories alphabetically
    local sortedCategories = {}
    for categoryName, _ in pairs(consumablesCategories) do
        table.insert(sortedCategories, categoryName)
    end
    table.sort(sortedCategories)

    -- Checkboxes
    parentFrame.checkboxes = {}
    parentFrame.categoryInfo = {}
    local index = 0 -- Position index
    local lineHeight = 18

    -- Iterate over sorted categories
    for _, categoryKey in ipairs(sortedCategories) do
        local categoryData = consumablesCategories[categoryKey]
        local categoryName = categoryData.name

        local consumables = {}
        if categoryData.items then
            for id, item in pairs(categoryData.items) do
                item.id = id
                table.insert(consumables, item)
            end
        end

        -- Create category label
        local categoryLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        categoryLabel:SetText(categoryName)
        categoryLabel:SetTextColor(1, 1, 1)
        categoryLabel:Show()
        
        local categoryInfo = { name = categoryName, label = categoryLabel, Items = {} }

        index = index + 1  -- Position for the category label

        local numItemsInCategory = 0  -- Counter for Items in this category

        -- Sort the consumables by name
        table.sort(consumables, function(a, b) return a.name < b.name end)

        -- For each consumable in the category
        for _, consumable in ipairs(consumables) do
            local currentItemID = consumable.id
            local itemName = consumable.name

            -- Create a frame that encompasses the checkbox and label
            local itemFrame = CreateFrame("Frame", "ConsumeTracker_ItemsFrame" .. index, scrollChild)
            itemFrame:SetWidth(WindowWidth - 10)
            itemFrame:SetHeight(lineHeight)
            itemFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, - (index) * lineHeight)
            itemFrame:Show()

            -- Create the checkbox inside the itemFrame
            local checkbox = CreateFrame("CheckButton", "ConsumeTracker_ItemsCheckbox" .. index, itemFrame)
            checkbox:SetWidth(16)
            checkbox:SetHeight(16)
            checkbox:SetPoint("LEFT", itemFrame, "LEFT", 0, 0)

            -- Create Textures for the checkbox
            checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            checkbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
            checkbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
            checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

            -- Item Icon
            local icon = itemFrame:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(14)
            icon:SetHeight(14)
            icon:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
            
            -- Try to get texture from GetItemInfo or fallback to preset
            local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(currentItemID)
            if not itemTexture and consumable.texture then
                 itemTexture = consumable.texture
            elseif not itemTexture then
                 itemTexture = "Interface\\Icons\\INV_Misc_QuestionMark" 
            end
            icon:SetTexture(itemTexture)

            -- Create FontString for label
            local label = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            label:SetText(itemName or consumable.name)

            -- Quantity Label
            local qtyLabel = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            qtyLabel:SetPoint("RIGHT", itemFrame, "RIGHT", -20, 0)
            qtyLabel:SetText("-") -- Initial placeholder
            
            -- Set up the checkbox OnClick handler
            checkbox:SetScript("OnClick", function()
                ConsumeTracker_SelectedItems[currentItemID] = checkbox:GetChecked()
                ConsumeTracker_UpdateManagerContent()
            end)
            -- Load saved setting
            if ConsumeTracker_SelectedItems[currentItemID] then
                checkbox:SetChecked(true)
            end

            parentFrame.checkboxes[currentItemID] = checkbox
            
            -- Make the itemFrame clickable
            itemFrame:EnableMouse(true)
            itemFrame:SetScript("OnMouseDown", function()
                checkbox:Click()
            end)

            -- Mouseover Tooltip
            itemFrame:SetScript("OnEnter", function()
                ConsumeTracker_ShowItemsTooltip(currentItemID)
            end)
            itemFrame:SetScript("OnLeave", function()
                if ConsumeTracker_ItemsTooltip then
                    ConsumeTracker_ItemsTooltip:Hide()
                end
            end)

            -- Store item info
            table.insert(categoryInfo.Items, { 
                frame = itemFrame, 
                name = itemName or consumable.name, 
                itemID = currentItemID,
                qtyLabel = qtyLabel 
            })

            index = index + 1  -- Increment index after adding item
            numItemsInCategory = numItemsInCategory + 1  -- Increment Items count
        end

        -- Position the category label above its Items
        categoryLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, - (index - numItemsInCategory - 1) * lineHeight)

        -- Store category info
        table.insert(parentFrame.categoryInfo, categoryInfo)

        -- Add extra spacing after the category
        index = index + 1  -- Add one extra line of spacing between categories
    end

    -- Adjust the scroll child height
    scrollChild.contentHeight = (index - 1) * lineHeight
    scrollChild:SetHeight(scrollChild.contentHeight)

    -- Scroll Bar
    -- Scroll Bar (Minimalist)
    local scrollBar = CreateFrame("Slider", "ConsumeTracker_ItemsScrollBar", parentFrame)
    scrollBar:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -5, -40) 
    scrollBar:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -5, 10)
    scrollBar:SetWidth(6) -- Thinner
    scrollBar:SetOrientation('VERTICAL')
    
    -- Background (Track)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollBar)
    track:SetTexture(0, 0, 0, 0.4)
    
    -- Thumb
    scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = scrollBar:GetThumbTexture()
    thumb:SetVertexColor(1, 0.82, 0, 0.8) -- Gold
    thumb:SetWidth(6)
    thumb:SetHeight(30) -- Longer thumb for better grip visual
    
    scrollBar:SetScript("OnValueChanged", function()
        local value = this:GetValue()
        parentFrame.scrollFrame:SetVerticalScroll(value)
    end)
    parentFrame.scrollBar = scrollBar

    -- Update the scrollbar and apply initial filter
    UpdateFilter()

    -- Helper to create Gold Button (Local to this function avoid global pollution)
    local function CreateItemsGoldButton(name, parent, text, width, height, point, relativeTo, relativePoint, xOfs, yOfs)
        local btn = CreateFrame("Button", name, parent)
        btn:SetWidth(width)
        btn:SetHeight(height)
        btn:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
        
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        btn:SetBackdropColor(0, 0, 0, 0.5) 
        btn:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold border

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btnText:SetText(text)
        btnText:SetTextColor(1, 0.82, 0) -- Gold text
        btn.text = btnText

        -- Hover Effects
        btn:SetScript("OnEnter", function()
            if this:IsEnabled() == 1 then
                this:SetBackdropBorderColor(1, 1, 1, 1)
                this.text:SetTextColor(1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function()
            if this:IsEnabled() == 1 then
                this:SetBackdropBorderColor(1, 0.82, 0, 1)
                this.text:SetTextColor(1, 0.82, 0)
            else
                this:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
                this.text:SetTextColor(0.5, 0.5, 0.5)
            end
        end)

        return btn
    end

    -- Create Select All Button
    local selectAllButton = CreateItemsGoldButton("ConsumeTracker_SelectAllButton", parentFrame, "Select All", 80, 20, "BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 20, 10)
    selectAllButton:SetScript("OnClick", function()
        for itemID, checkbox in pairs(parentFrame.checkboxes) do
            checkbox:SetChecked(true)
            ConsumeTracker_SelectedItems[itemID] = true
        end
        ConsumeTracker_UpdateManagerContent()
    end)

    -- Create Deselect All Button
    local deselectAllButton = CreateItemsGoldButton("ConsumeTracker_DeselectAllButton", parentFrame, "Deselect All", 80, 20, "BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -40, 10)
    deselectAllButton:SetScript("OnClick", function()
        for itemID, checkbox in pairs(parentFrame.checkboxes) do
            checkbox:SetChecked(false)
            ConsumeTracker_SelectedItems[itemID] = false
        end
        ConsumeTracker_UpdateManagerContent()
    end)
end

function ConsumeTracker_UpdateItemsScrollBar()
    local ItemsFrame = ConsumeTracker_MainFrame.tabs[2]
    if not ItemsFrame then
        print("Error: ItemsFrame (tabs[2]) is nil in UpdateItemsScrollBar")
        return
    end
    local scrollBar = ItemsFrame.scrollBar
    local scrollFrame = ItemsFrame.scrollFrame
    local scrollChild = ItemsFrame.scrollChild

    local totalHeight = scrollChild.contentHeight
    local parentHeight = ItemsFrame:GetHeight()
    local searchBoxHeight = 36  -- Adjusted height including padding
    local buttonsHeight = 40      -- Space reserved for Select/Deselect buttons
    local shownHeight = parentHeight - searchBoxHeight - buttonsHeight - 20  -- Additional padding

    local maxScroll = math.max(0, totalHeight - shownHeight)
    scrollFrame.maxScroll = maxScroll

    if totalHeight > shownHeight then
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(math.min(scrollBar:GetValue(), maxScroll))
        scrollBar:Show()
    else
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        scrollBar:Hide()
    end
end



-- Presets Window -----------------------------------------------------------------------------------

    local classColors = {
        ["Rogue"] = "fff569",
        ["Mage"] = "69ccf0",
        ["Warrior"] = "c79c6e",
        ["Hunter"] = "abd473",
        ["Druid"] = "ff7d0a",
        ["Priest"] = "ffffff",
        ["Warlock"] = "9482c9",
        ["Shaman"] = "0070dd",
        ["Paladin"] = "f58cba"
    }

    -- Manually ordered raids (adjust as needed)
    local orderedRaids = {
        "Molten Core",
        "Blackwing Lair",
        "Emerald Sanctum",
        "Temple of Ahn'Qiraj",
        "Naxxramas",
        "The Tower of Karazhan"
    }

    local function GetLastWord(str)
        local spacePos = 0
        while true do
            local found = string.find(str, " ", spacePos + 1)
            if found then
                spacePos = found
            else
                break
            end
        end
        if spacePos == 0 then
            return str
        else
            return string.sub(str, spacePos + 1)
        end
    end

    local function SortClassesByLastWord(t)
        local n = table.getn(t)
        local i = 1
        while i < n do
            local j = i + 1
            while j <= n do
                local lwA = GetLastWord(t[i])
                local lwB = GetLastWord(t[j])
                if lwA > lwB then
                    t[i], t[j] = t[j], t[i]
                end
                j = j + 1
            end
            i = i + 1
        end
    end

function ConsumeTracker_CreatePresetsContent(parentFrame)
    local lineHeight = 18

    local raidDropdown = CreateFrame("Frame", "ConsumeTracker_PresetsRaidDropdown", parentFrame, "UIDropDownMenuTemplate")
    raidDropdown:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", -20, 0)
    UIDropDownMenu_SetWidth(120, raidDropdown)
    UIDropDownMenu_SetText("Select |cffffff00Raid|r", raidDropdown)

    local raidDropdownText = getglobal("ConsumeTracker_PresetsRaidDropdownText")
    if raidDropdownText then
        raidDropdownText:SetJustifyH("LEFT")
    end

    local classDropdown = CreateFrame("Frame", "ConsumeTracker_PresetsClassDropdown", parentFrame, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("LEFT", raidDropdown, "RIGHT", -20, 0)
    UIDropDownMenu_SetWidth(120, classDropdown)
    UIDropDownMenu_SetText("Select |cffffff00Class|r", classDropdown)

    local classDropdownText = getglobal("ConsumeTracker_PresetsClassDropdownText")
    if classDropdownText then
        classDropdownText:SetJustifyH("LEFT")
    end

    local classes = {}
    for className, _ in pairs(classPresets) do
        table.insert(classes, className)
    end

    SortClassesByLastWord(classes)

    UIDropDownMenu_Initialize(classDropdown, function()
        local idx = 1
        while classes[idx] do
            local cName = classes[idx]
            local cIndex = idx
            local info = {}
            local lastWord = GetLastWord(cName)
            local color = classColors[lastWord] or "ffffff"
            info.text = "|cff" .. color .. cName .. "|r"
            info.func = function()
                UIDropDownMenu_SetSelectedID(classDropdown, cIndex)
                ConsumeTracker_SelectedClass = cName
                ConsumeTracker_UpdateRaidsDropdown()
                ConsumeTracker_UpdatePresetsConsumables()
            end
            UIDropDownMenu_AddButton(info)
            idx = idx + 1
        end
    end)

    -- Build initial raid list from the first class, but we won't sort them automatically
    -- We rely on our manual "orderedRaids" list
    local uniqueRaids, seen = {}, {}
    local count = 0
    local firstClass = next(classPresets)
    if firstClass then
        local classList = classPresets[firstClass]
        local i = 1
        while classList[i] do
            local rName = classList[i].raid
            if not seen[rName] then
                count = count + 1
                uniqueRaids[count] = rName
                seen[rName] = true
            end
            i = i + 1
        end
    end

    UIDropDownMenu_Initialize(raidDropdown, function()
        if count == 0 then
            local info = {}
            info.text = "No Raids Available"
            info.disabled = true
            UIDropDownMenu_AddButton(info)
            UIDropDownMenu_SetText("Select |cffffff00Raid|r", raidDropdown)
            return
        end
        local i = 1
        while orderedRaids[i] do
            local orName = orderedRaids[i]
            if seen[orName] then
                local cIndex = i
                local cRaidName = orName
                local info = {}
                info.text = orName
                info.func = function()
                    UIDropDownMenu_SetSelectedID(raidDropdown, cIndex)
                    ConsumeTracker_SelectedRaid = cRaidName
                    ConsumeTracker_UpdatePresetsConsumables()
                end
                UIDropDownMenu_AddButton(info)
            end
            i = i + 1
        end
        UIDropDownMenu_SetText("Select |cffffff00Raid|r", raidDropdown)
    end)

    UIDropDownMenu_SetSelectedID(raidDropdown, 0)

    local scrollFrame = CreateFrame("ScrollFrame", "ConsumeTracker_PresetsScrollFrame", parentFrame)
    scrollFrame:SetPoint("TOPLEFT", classDropdown, "BOTTOMLEFT", -135, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -25, -5)
    scrollFrame:EnableMouseWheel(true)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(parentFrame:GetWidth() - 40)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    parentFrame.scrollChild = scrollChild
    parentFrame.scrollFrame = scrollFrame

    -- Scroll Bar (Minimalist)
    local scrollBar = CreateFrame("Slider", "ConsumeTracker_PresetsScrollBar", parentFrame)
    scrollBar:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -5, -80) 
    scrollBar:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -5, 10)
    scrollBar:SetWidth(6)
    scrollBar:SetOrientation('VERTICAL')
    
    -- Background (Track)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollBar)
    track:SetTexture(0, 0, 0, 0.4)
    
    -- Thumb
    scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = scrollBar:GetThumbTexture()
    thumb:SetVertexColor(1, 0.82, 0, 0.8) -- Gold
    thumb:SetWidth(6)
    thumb:SetHeight(30)
    scrollBar:SetScript("OnValueChanged", function()
        local val = this:GetValue()
        parentFrame.scrollFrame:SetVerticalScroll(val)
    end)
    parentFrame.scrollBar = scrollBar
    scrollBar:Hide()

    scrollFrame:SetScript("OnMouseWheel", function()
        local d = arg1
        local cur = this:GetVerticalScroll()
        local mx = this.range or 0
        local new = 0
        if d < 0 then
            new = math.min(cur + 20, mx)
        else
            new = math.max(cur - 20, 0)
        end
        this:SetVerticalScroll(new)
        parentFrame.scrollBar:SetValue(new)
    end)

    local orderByNameButton = CreateFrame("Button", "ConsumeTracker_PresetsOrderByNameButton", parentFrame, "UIPanelButtonTemplate")
    orderByNameButton:SetWidth(100)
    orderByNameButton:SetHeight(24)
    orderByNameButton:SetText("Order by Name")
    orderByNameButton:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 10, "NORMAL")
    orderByNameButton:SetPoint("TOPLEFT", ConsumeTracker_MainFrame.tabs[3], "TOPLEFT", -4, -35)
    orderByNameButton:SetScript("OnClick", function()
        if ConsumeTracker_Options.presetsSortOrder == "name" then
            if ConsumeTracker_Options.presetsSortDirection == "asc" then
                ConsumeTracker_Options.presetsSortDirection = "desc"
            else
                ConsumeTracker_Options.presetsSortDirection = "asc"
            end
        else
            ConsumeTracker_Options.presetsSortOrder = "name"
            ConsumeTracker_Options.presetsSortDirection = "asc"
        end
        ConsumeTracker_UpdatePresetsConsumables()
    end)

    local orderByAmountButton = CreateFrame("Button", "ConsumeTracker_PresetsOrderByAmountButton", parentFrame, "UIPanelButtonTemplate")
    orderByAmountButton:SetWidth(120)
    orderByAmountButton:SetHeight(24)
    orderByAmountButton:SetText("Order by Amount")
    orderByAmountButton:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 10, "NORMAL")
    orderByAmountButton:SetPoint("LEFT", orderByNameButton, "RIGHT", 10, 0)
    orderByAmountButton:SetScript("OnClick", function()
        if ConsumeTracker_Options.presetsSortOrder == "amount" then
            if ConsumeTracker_Options.presetsSortDirection == "desc" then
                ConsumeTracker_Options.presetsSortDirection = "asc"
            else
                ConsumeTracker_Options.presetsSortDirection = "desc"
            end
        else
            ConsumeTracker_Options.presetsSortOrder = "amount"
            ConsumeTracker_Options.presetsSortDirection = "desc"
        end
        ConsumeTracker_UpdatePresetsConsumables()
    end)

    parentFrame.orderByNameButton = orderByNameButton
    parentFrame.orderByAmountButton = orderByAmountButton
    orderByNameButton:Hide()
    orderByAmountButton:Hide()

    parentFrame.presetsConsumables = {}
    local messageLabel = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageLabel:SetText("|cffff0000Please select both a Raid and a Class.|r")
    messageLabel:SetPoint("CENTER", parentFrame, "CENTER", 0, 0)
    messageLabel:Hide()
    parentFrame.messageLabel = messageLabel
end

function ConsumeTracker_UpdateRaidsDropdown()
    local raidDropdown = getglobal("ConsumeTracker_PresetsRaidDropdown")
    if not raidDropdown then
        return
    end
    local prevRaid = ConsumeTracker_SelectedRaid
    UIDropDownMenu_ClearAll(raidDropdown)

    local uniqueRaids, seen = {}, {}
    local c = 0
    if ConsumeTracker_SelectedClass and classPresets[ConsumeTracker_SelectedClass] then
        local clList = classPresets[ConsumeTracker_SelectedClass]
        local i = 1
        while clList[i] do
            local rName = clList[i].raid
            if not seen[rName] then
                c = c + 1
                uniqueRaids[c] = rName
                seen[rName] = true
            end
            i = i + 1
        end
    end

    UIDropDownMenu_Initialize(raidDropdown, function()
        if c == 0 then
            local info = {}
            info.text = "No Raids Available"
            info.disabled = 1
            UIDropDownMenu_AddButton(info)
            UIDropDownMenu_SetText("Select |cffffff00Raid|r", raidDropdown)
            return
        end
        local i = 1
        local selectedIndex = 0
        while orderedRaids[i] do
            local raidName = orderedRaids[i]
            if seen[raidName] then
                local currentIndex = i
                local currentRaidName = raidName
                local info = {}
                info.text = raidName
                info.func = function()
                    UIDropDownMenu_SetSelectedID(raidDropdown, currentIndex)
                    ConsumeTracker_SelectedRaid = currentRaidName
                    ConsumeTracker_UpdatePresetsConsumables()
                end
                UIDropDownMenu_AddButton(info)
                if raidName == prevRaid then
                    selectedIndex = i
                end
            end
            i = i + 1
        end
        if selectedIndex > 0 then
            UIDropDownMenu_SetSelectedID(raidDropdown, selectedIndex)
        else
            UIDropDownMenu_SetSelectedID(raidDropdown, 0)
            UIDropDownMenu_SetText("Select |cffffff00Raid|r", raidDropdown)
            ConsumeTracker_SelectedRaid = nil
        end
    end)
end


function ConsumeTracker_UpdatePresetsScrollBar()
    local PresetsFrame = ConsumeTracker_MainFrame.tabs[3]
    if not PresetsFrame then
        return
    end

    local scrollFrame = PresetsFrame.scrollFrame
    local scrollChild = PresetsFrame.scrollChild
    local scrollBar = PresetsFrame.scrollBar

    if not scrollFrame or not scrollChild or not scrollBar then
        return
    end

    local totalHeight = scrollChild:GetHeight()
    local shownHeight = PresetsFrame:GetHeight() - 20  -- Account for padding/margins

    if totalHeight > shownHeight then
        local maxScroll = totalHeight - shownHeight
        scrollFrame.range = maxScroll  -- Set the scroll range
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(math.min(scrollBar:GetValue(), maxScroll))
        scrollBar:Show()
    else
        scrollFrame.range = 0  -- Also handle this case
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        scrollBar:Hide()
    end
end

function ConsumeTracker_UpdatePresetsConsumables()
    -- References to necessary frames
    local parentFrame = ConsumeTracker_MainFrame and ConsumeTracker_MainFrame.tabs and ConsumeTracker_MainFrame.tabs[3]
    if not parentFrame then
        -- Presets tab is not initialized yet
        return
    end

    local scrollChild = parentFrame.scrollChild
    local scrollFrame = parentFrame.scrollFrame
    local scrollBar = parentFrame.scrollBar

    -- Initialize presetsConsumables table if not already
    if not parentFrame.presetsConsumables then
        parentFrame.presetsConsumables = {}
    end

    -- Function to get the number of elements in a table
    local function GetTableLength(t)
        local count = 0
        if type(t) == "table" then
            for _ in pairs(t) do
                count = count + 1
            end
        end
        return count
    end

    -- Clear existing consumables
    local consumablesCount = GetTableLength(parentFrame.presetsConsumables)
    for i = 1, consumablesCount do
        local consumable = parentFrame.presetsConsumables[i]
        if consumable and consumable.frame and consumable.frame.Hide then
            consumable.frame:Hide()
        end
    end
    parentFrame.presetsConsumables = {}

    -- Hide "No items" message if it exists
    if parentFrame.noItemsMessage then
        parentFrame.noItemsMessage:Hide()
    end

    -- Check if both Raid and Class are selected
    if not ConsumeTracker_SelectedRaid or not ConsumeTracker_SelectedClass then
        -- Show a message prompting the user to select both
        parentFrame.messageLabel:SetText("|cffffffffSelect both a |rRaid|cffffffff and a |rClass|cffffffff.|r")
        parentFrame.messageLabel:Show()
        parentFrame.orderByNameButton:Hide()
        parentFrame.orderByAmountButton:Hide()
        return
    else
        parentFrame.messageLabel:Hide()
    end

    -- Retrieve the selected preset based on Class and Raid
    local selectedPreset = nil
    if classPresets and classPresets[ConsumeTracker_SelectedClass] and type(classPresets[ConsumeTracker_SelectedClass]) == "table" then
        local presetListLength = GetTableLength(classPresets[ConsumeTracker_SelectedClass])
        for i = 1, presetListLength do
            local preset = classPresets[ConsumeTracker_SelectedClass][i]
            if preset and preset.raid == ConsumeTracker_SelectedRaid then
                selectedPreset = preset
                break
            end
        end
    end

    -- Handle case where no preset is found
    if not selectedPreset then
        parentFrame.messageLabel:SetText("|cffff0000No presets found for this combination.|r")
        parentFrame.messageLabel:Show()
        parentFrame.orderByNameButton:Hide()
        parentFrame.orderByAmountButton:Hide()
        return
    end

    -- Get the consumable IDs from selectedPreset
    local presetIDs = selectedPreset.id
    if not presetIDs or type(presetIDs) ~= "table" then
        parentFrame.messageLabel:SetText("|cffff0000Invalid preset data.|r")
        parentFrame.messageLabel:Show()
        parentFrame.orderByNameButton:Hide()
        parentFrame.orderByAmountButton:Hide()
        return
    end

    -- Ensure data structure exists
    local realmName = GetRealmName()
    local playerName = UnitName("player")

    -- Populate the consumables list based on presetIDs
    -- Initialize tables
    local consumablesList = {}
    local consumablesNameToID = {}
    local consumablesTexture = {}
    local consumablesDescription = {}

    -- Populate consumablesList and other lookup tables
    for categoryKey, categoryData in pairs(consumablesCategories) do
        if categoryData.items then
            for id, consumable in pairs(categoryData.items) do
                consumablesList[id] = consumable.name
                consumablesNameToID[consumable.name] = id
                consumablesTexture[id] = consumable.texture
                consumablesDescription[id] = consumable.description
            end
        end
    end

    -- Create a mapping from consumable ID to category name
    local consumablesIDToCategory = {}
    for categoryName, consumables in pairs(consumablesCategories) do
        for _, consumable in ipairs(consumables) do
            consumablesIDToCategory[consumable.id] = categoryName
        end
    end

    -- Main loop to gather consumables to show
    local consumablesToShow = {}
    local presetIDsLength = GetTableLength(presetIDs)
    for i = 1, presetIDsLength do
        local id = presetIDs[i]
        if id and consumablesList[id] then
            -- Calculate total count across selected characters
            local totalCount = 0
            if ConsumeTracker_Data[realmName] and ConsumeTracker_SelectedItems and ConsumeTracker_Options.Characters and type(ConsumeTracker_Options.Characters) == "table" then
                for character, isSelected in pairs(ConsumeTracker_Options.Characters) do
                    if isSelected and ConsumeTracker_Data[realmName][character] and type(ConsumeTracker_Data[realmName][character]) == "table" then
                        local charInventory = ConsumeTracker_Data[realmName][character].inventory or {}
                        local charBank = ConsumeTracker_Data[realmName][character].bank or {}
                        local charMail = ConsumeTracker_Data[realmName][character].mail or {}
                        totalCount = totalCount + (charInventory[id] or 0) + (charBank[id] or 0) + (charMail[id] or 0)
                    end
                end
            end

            -- Assign category using the mapping table
            local category = consumablesIDToCategory[id] or "Uncategorized"

            -- Insert consumable with additional data
            table.insert(consumablesToShow, {
                id = id,
                name = consumablesList[id],
                texture = consumablesTexture[id],
                description = consumablesDescription[id],
                totalCount = totalCount,
                category = category
            })
        else
            -- Optional: Handle the else case if needed
        end
    end

    -- Apply sorting based on settings
    local sortOrder = ConsumeTracker_Options.presetsSortOrder or "name"
    local sortDirection = ConsumeTracker_Options.presetsSortDirection or "asc"

    -- Sorting function
    local function SortConsumables(a, b)
        if sortOrder == "name" then
            if sortDirection == "asc" then
                return a.name < b.name
            else
                return a.name > b.name
            end
        elseif sortOrder == "amount" then
            if sortDirection == "asc" then
                return a.totalCount < b.totalCount
            else
                return a.totalCount > b.totalCount
            end
        else
            -- Default to name ascending
            return a.name < b.name
        end
    end

    -- Sort consumablesToShow
    if table and table.sort then
        table.sort(consumablesToShow, SortConsumables)
    else
        -- Implement a simple bubble sort if table.sort is unavailable
        local n = GetTableLength(consumablesToShow)
        for i = 1, n - 1 do
            for j = 1, n - i do
                if not SortConsumables(consumablesToShow[j], consumablesToShow[j + 1]) then
                    -- Swap
                    consumablesToShow[j], consumablesToShow[j + 1] = consumablesToShow[j + 1], consumablesToShow[j]
                end
            end
        end
    end

    -- Initialize variables for display
    local index = 0
    local lineHeight = 18
    local hasAnyVisibleItems = false

    -- Get settings
    local enableCategories = ConsumeTracker_Options.enableCategories or false
    local showUseButton = ConsumeTracker_Options.showUseButton or false

    if enableCategories then
        -- Group consumables by category
        local categories = {}
        local consumablesToShowLength = GetTableLength(consumablesToShow)
        for i = 1, consumablesToShowLength do
            local consumable = consumablesToShow[i]
            local category = consumable.category or "Uncategorized"
            if not categories[category] then
                categories[category] = {}
            end
            table.insert(categories[category], consumable)
        end

        -- Sort category names alphabetically
        local sortedCategoryNames = {}
        for categoryName in pairs(categories) do
            table.insert(sortedCategoryNames, categoryName)
        end
        if table and table.sort then
            table.sort(sortedCategoryNames)
        else
            -- Simple bubble sort if table.sort is unavailable
            local n = GetTableLength(sortedCategoryNames)
            for i = 1, n - 1 do
                for j = 1, n - i do
                    if sortedCategoryNames[j] > sortedCategoryNames[j + 1] then
                        sortedCategoryNames[j], sortedCategoryNames[j + 1] = sortedCategoryNames[j + 1], sortedCategoryNames[j]
                    end
                end
            end
        end

        -- Iterate over each category
        local sortedCategoryNamesLength = GetTableLength(sortedCategoryNames)
        for i = 1, sortedCategoryNamesLength do
            local categoryName = sortedCategoryNames[i]
            local items = categories[categoryName]

            if items and GetTableLength(items) > 0 then
                -- Create and display category label
                index = index + 1
                local categoryFrame = CreateFrame("Frame", "ConsumeTracker_CategoryFrame" .. index, scrollChild)
                categoryFrame:SetWidth(scrollChild:GetWidth() - 10)
                categoryFrame:SetHeight(lineHeight)
                categoryFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, - ((index - 1) * lineHeight))
                categoryFrame:Show()

                local categoryLabel = categoryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                categoryLabel:SetPoint("LEFT", categoryFrame, "LEFT", 0, 0)
                categoryLabel:SetText(categoryName)
                categoryLabel:SetJustifyH("LEFT")
                categoryLabel:SetTextColor(1, 1, 1)


                -- Store the category frame
                table.insert(parentFrame.presetsConsumables, {
                    frame = categoryFrame,
                    label = categoryLabel,
                    isCategory = true
                })

                -- Increment index for items under the category
                index = index + 1

                -- Sort items within the category
                if table and table.sort then
                    table.sort(items, SortConsumables)
                else
                    -- Simple bubble sort if table.sort is unavailable
                    local m = GetTableLength(items)
                    for p = 1, m - 1 do
                        for q = 1, m - p do
                            if not SortConsumables(items[q], items[q + 1]) then
                                items[q], items[q + 1] = items[q + 1], items[q]
                            end
                        end
                    end
                end

                -- Iterate through each consumable in the category
                local itemsLength = GetTableLength(items)
                for j = 1, itemsLength do
                    local consumable = items[j]
                    if consumable then
                        -- Create consumable frame
                        local frame = CreateFrame("Frame", "ConsumeTracker_PresetsConsumableFrame" .. index, scrollChild)
                        frame:SetWidth(scrollChild:GetWidth() - 10)
                        frame:SetHeight(lineHeight)
                        frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, - ((index - 1) * lineHeight))
                        frame:Show()
                        frame:EnableMouse(true)  -- Enable mouse for tooltip

                        -- Create "Use" button if enabled
                        local useButton = nil
                        if showUseButton then
                            useButton = CreateFrame("Button", "ConsumeTracker_PresetsUseButton" .. index, frame, "UIPanelButtonTemplate")
                            useButton:SetWidth(40)
                            useButton:SetHeight(16)
                            useButton:SetPoint("LEFT", frame, "LEFT", 0, 0)
                            useButton:SetText("Use")
                            useButton:SetScript("OnClick", function()
                                local bag, slot = ConsumeTracker_FindItemInBags(consumable.id)
                                if bag and slot then
                                    UseContainerItem(bag, slot)
                                else
                                    DEFAULT_CHAT_FRAME:AddMessage("Item not found in bags.")
                                end
                            end)
                        end

                        -- Create label with count
                        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        if showUseButton and useButton then
                            label:SetPoint("LEFT", useButton, "RIGHT", 4, 0)
                        else
                            label:SetPoint("LEFT", frame, "LEFT", 0, 0)
                        end
                        label:SetText(consumable.name .. " (" .. consumable.totalCount .. ")")
                        label:SetJustifyH("LEFT")

                        -- Adjust label color based on count
                        if consumable.totalCount == 0 then
                            label:SetTextColor(1, 0, 0) -- Red
                        elseif consumable.totalCount < 10 then
                            label:SetTextColor(1, 0.4, 0) -- Orange
                        elseif consumable.totalCount <= 20 then
                            label:SetTextColor(1, 0.85, 0) -- Yellow
                        else
                            label:SetTextColor(0, 1, 0) -- Green
                        end

                        -- Tooltip handling
                        frame:SetScript("OnEnter", function()
                            ConsumeTracker_ShowConsumableTooltip(consumable.id)
                        end)
                        frame:SetScript("OnLeave", function()
                            if ConsumeTracker_CustomTooltip and ConsumeTracker_CustomTooltip.Hide then
                                ConsumeTracker_CustomTooltip:Hide()
                            end
                        end)

                        -- Enable or disable "Use" button based on inventory
                        if useButton then
                            local playerInventory = (ConsumeTracker_Data[realmName] and 
                                                   ConsumeTracker_Data[realmName][playerName] and 
                                                   ConsumeTracker_Data[realmName][playerName].inventory) or {}
                            local countInInventory = playerInventory[consumable.id] or 0

                            if countInInventory > 0 then
                                useButton:Enable()
                            else
                                useButton:Disable()
                            end
                        end

                        -- Store the consumable frame
                        table.insert(parentFrame.presetsConsumables, {
                            frame = frame,
                            label = label,
                            useButton = useButton,
                            id = consumable.id
                        })

                        index = index + 1
                        hasAnyVisibleItems = true
                    end
                end
                
            end
        end
    else
        -- Categories are disabled; display all consumables in a single list
        local consumablesToShowLength = GetTableLength(consumablesToShow)
        for i = 1, consumablesToShowLength do
            local consumable = consumablesToShow[i]
            if consumable then
                -- Create consumable frame
                index = index + 1

                local frame = CreateFrame("Frame", "ConsumeTracker_PresetsConsumableFrame" .. index, scrollChild)
                frame:SetWidth(scrollChild:GetWidth() - 10)
                frame:SetHeight(lineHeight)
                frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, - ((index - 1) * lineHeight))
                frame:Show()
                frame:EnableMouse(true)  -- Enable mouse for tooltip

                -- Create "Use" button if enabled
                local useButton = nil
                if showUseButton then
                    useButton = CreateFrame("Button", "ConsumeTracker_PresetsUseButton" .. index, frame, "UIPanelButtonTemplate")
                    useButton:SetWidth(40)
                    useButton:SetHeight(16)
                    useButton:SetPoint("LEFT", frame, "LEFT", 0, 0)
                    useButton:SetText("Use")
                    useButton:SetScript("OnClick", function()
                        local bag, slot = ConsumeTracker_FindItemInBags(consumable.id)
                        if bag and slot then
                            UseContainerItem(bag, slot)
                        else
                            DEFAULT_CHAT_FRAME:AddMessage("Item not found in bags.")
                        end
                    end)
                end

                -- Create label with count
                local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                if showUseButton and useButton then
                    label:SetPoint("LEFT", useButton, "RIGHT", 4, 0)
                else
                    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
                end
                label:SetText(consumable.name .. " (" .. consumable.totalCount .. ")")
                label:SetJustifyH("LEFT")

                -- Adjust label color based on count
                if consumable.totalCount == 0 then
                    label:SetTextColor(1, 0, 0) -- Red
                elseif consumable.totalCount < 10 then
                    label:SetTextColor(1, 0.4, 0) -- Orange
                elseif consumable.totalCount <= 20 then
                    label:SetTextColor(1, 0.85, 0) -- Yellow
                else
                    label:SetTextColor(0, 1, 0) -- Green
                end

                -- Tooltip handling
                frame:SetScript("OnEnter", function()
                    ConsumeTracker_ShowConsumableTooltip(consumable.id)
                end)
                frame:SetScript("OnLeave", function()
                    if ConsumeTracker_CustomTooltip and ConsumeTracker_CustomTooltip.Hide then
                        ConsumeTracker_CustomTooltip:Hide()
                    end
                end)

                -- Enable or disable "Use" button based on inventory
                if useButton then
                    local playerInventory = (ConsumeTracker_Data[realmName] and 
                                           ConsumeTracker_Data[realmName][playerName] and 
                                           ConsumeTracker_Data[realmName][playerName].inventory) or {}
                    local countInInventory = playerInventory[consumable.id] or 0

                    if countInInventory > 0 then
                        useButton:Enable()
                    else
                        useButton:Disable()
                    end
                end

                -- Store the consumable frame
                table.insert(parentFrame.presetsConsumables, {
                    frame = frame,
                    label = label,
                    useButton = useButton,
                    id = consumable.id
                })

               
                hasAnyVisibleItems = true
            end
        end
    end

    -- Adjust the scroll child height based on the number of items
    scrollChild:SetHeight(index * lineHeight + 40)

    -- Show sorting order buttons
    parentFrame.orderByNameButton:Show()
    parentFrame.orderByAmountButton:Show()

    -- Update the scrollbar to reflect new content
    ConsumeTracker_UpdatePresetsScrollBar()

    -- Handle the case where no consumables are visible
    if not hasAnyVisibleItems then
        -- Create and show a "No consumables available" message if it doesn't exist
        if not parentFrame.noItemsMessage then
            parentFrame.noItemsMessage = parentFrame.messageLabel
            
            parentFrame.noItemsMessage:SetText("|cffff0000This preset is not available yet.|r")

            parentFrame.orderByNameButton:Hide()
            parentFrame.orderByAmountButton:Hide()


        end
        parentFrame.noItemsMessage:Show()
    else
        -- Hide the message if it exists
        if parentFrame.noItemsMessage then
            parentFrame.noItemsMessage:Hide()
        end

    end
end

function ConsumeTracker_IsItemInPresets(itemID)
    for className, presets in pairs(classPresets) do
        for _, preset in ipairs(presets) do
            for _, id in ipairs(preset.id) do
                if id == itemID then
                    return true
                end
            end
        end
    end
    return false
end



-- Settings Window -----------------------------------------------------------------------------------
function ConsumeTracker_CreateSettingsContent(parentFrame)
    -- Scroll Frame Setup
    local scrollFrame = CreateFrame("ScrollFrame", "ConsumeTracker_SettingsScrollFrame", parentFrame)
    scrollFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -20, 0)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
        local delta = arg1
        local current = this:GetVerticalScroll()
        local maxScroll = this.maxScroll or 0
        local newScroll = math.max(0, math.min(current - (delta * 20), maxScroll))
        this:SetVerticalScroll(newScroll)
        parentFrame.scrollBar:SetValue(newScroll)
    end)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(WindowWidth - 10)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    parentFrame.scrollChild = scrollChild
    parentFrame.scrollFrame = scrollFrame

    parentFrame.checkboxes = {}
    local index = 0
    local lineHeight = 20

    ConsumeTracker_Options["Characters"] = ConsumeTracker_Options["Characters"] or {}
    ConsumeTracker_Options.enableCategories = (ConsumeTracker_Options.enableCategories == nil) and true or ConsumeTracker_Options.enableCategories
    ConsumeTracker_Options.showUseButton = (ConsumeTracker_Options.showUseButton == nil) and true or ConsumeTracker_Options.showUseButton

    local realmName = GetRealmName()
    local playerName = UnitName("player")
    local playerFaction = UnitFactionGroup("player")

    -- Build character list with faction info
    local characterList = {}
    if ConsumeTracker_Data[realmName] then
        for characterName, charData in pairs(ConsumeTracker_Data[realmName]) do
            if type(charData) == "table" then
                table.insert(characterList, {
                    name = characterName,
                    faction = charData.faction or "Unknown"
                })
            end
        end
    end

    local playerInList = false
    for _, charInfo in ipairs(characterList) do
        if charInfo.name == playerName then
            playerInList = true
            break
        end
    end
    if not playerInList then
        table.insert(characterList, {
            name = playerName,
            faction = playerFaction
        })
    end

    -- Create faction-specific character lists
    local allianceCharacters = {}
    local hordeCharacters = {}
    
    for _, charInfo in ipairs(characterList) do
        if charInfo.faction == "Alliance" then
            table.insert(allianceCharacters, charInfo)
        elseif charInfo.faction == "Horde" then
            table.insert(hordeCharacters, charInfo)
        else
            -- For characters with unknown faction, add to both lists
            table.insert(allianceCharacters, charInfo)
            table.insert(hordeCharacters, charInfo)
        end
    end
    
    -- Sort characters by name
    table.sort(allianceCharacters, function(a, b) return a.name < b.name end)
    table.sort(hordeCharacters, function(a, b) return a.name < b.name end)

    -- Title
    local title = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -20) -- Added top padding
    title:SetText("Select Characters To Track")
    title:SetTextColor(1, 1, 1)

    local startYOffset = -60
    local currentYOffset = startYOffset

    -- Track whether we have characters from each faction
    local hasAlliance = table.getn(allianceCharacters) > 0
    local hasHorde = table.getn(hordeCharacters) > 0

    -- First add Alliance section if there are Alliance characters
    if hasAlliance then
        -- Alliance Header
        local allianceHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        allianceHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
        allianceHeader:SetText("|cff0078ffAlliance Characters:|r")
        allianceHeader:SetJustifyH("LEFT")
        currentYOffset = currentYOffset - lineHeight

        -- Alliance Characters
        for i, charInfo in ipairs(allianceCharacters) do
            local currentCharacterName = charInfo.name
            
            local itemFrame = CreateFrame("Frame", "ConsumeTracker_AllianceCharFrame" .. i, scrollChild)
            itemFrame:SetWidth(WindowWidth - 10)
            itemFrame:SetHeight(18)
            itemFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 20, currentYOffset)

            local checkbox = CreateFrame("CheckButton", "ConsumeTracker_AllianceCharCheckbox" .. i, itemFrame)
            checkbox:SetWidth(16)
            checkbox:SetHeight(16)
            checkbox:SetPoint("LEFT", itemFrame, "LEFT", 0, 0)

            checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            checkbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
            checkbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
            checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

            local label = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
            label:SetText(currentCharacterName)
            label:SetTextColor(0, 0.48, 1) -- Blue for Alliance
            label:SetJustifyH("LEFT")

            checkbox:SetScript("OnClick", function()
                ConsumeTracker_Options["Characters"][currentCharacterName] = (checkbox:GetChecked() == 1)
                ConsumeTracker_UpdateAllContent()
            end)

            if ConsumeTracker_Options["Characters"][currentCharacterName] == nil then
                checkbox:SetChecked(true)
                ConsumeTracker_Options["Characters"][currentCharacterName] = true
            else
                checkbox:SetChecked(ConsumeTracker_Options["Characters"][currentCharacterName] == true)
            end

            parentFrame.checkboxes[currentCharacterName] = checkbox
            itemFrame:EnableMouse(true)
            itemFrame:SetScript("OnMouseDown", function()
                checkbox:Click()
            end)
            
            currentYOffset = currentYOffset - lineHeight
            index = index + 1
        end
        
        -- Add extra spacing after Alliance section
        currentYOffset = currentYOffset - lineHeight / 2
    end

    -- Then add Horde section if there are Horde characters
    if hasHorde then
        -- Horde Header
        local hordeHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hordeHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
        hordeHeader:SetText("|cffb30000Horde Characters:|r")
        hordeHeader:SetJustifyH("LEFT")
        currentYOffset = currentYOffset - lineHeight

        -- Horde Characters
        for i, charInfo in ipairs(hordeCharacters) do
            local currentCharacterName = charInfo.name
            
            local itemFrame = CreateFrame("Frame", "ConsumeTracker_HordeCharFrame" .. i, scrollChild)
            itemFrame:SetWidth(WindowWidth - 10)
            itemFrame:SetHeight(18)
            itemFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 20, currentYOffset)

            local checkbox = CreateFrame("CheckButton", "ConsumeTracker_HordeCharCheckbox" .. i, itemFrame)
            checkbox:SetWidth(16)
            checkbox:SetHeight(16)
            checkbox:SetPoint("LEFT", itemFrame, "LEFT", 0, 0)

            checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            checkbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
            checkbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
            checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

            local label = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
            label:SetText(currentCharacterName)
            label:SetTextColor(0.7, 0, 0) -- Red for Horde
            label:SetJustifyH("LEFT")

            checkbox:SetScript("OnClick", function()
                ConsumeTracker_Options["Characters"][currentCharacterName] = (checkbox:GetChecked() == 1)
                ConsumeTracker_UpdateAllContent()
            end)

            if ConsumeTracker_Options["Characters"][currentCharacterName] == nil then
                checkbox:SetChecked(true)
                ConsumeTracker_Options["Characters"][currentCharacterName] = true
            else
                checkbox:SetChecked(ConsumeTracker_Options["Characters"][currentCharacterName] == true)
            end

            parentFrame.checkboxes[currentCharacterName] = checkbox
            itemFrame:EnableMouse(true)
            itemFrame:SetScript("OnMouseDown", function()
                checkbox:Click()
            end)
            
            currentYOffset = currentYOffset - lineHeight
            index = index + 1
        end
        
        -- Add extra spacing after Horde section
        currentYOffset = currentYOffset - lineHeight / 2
    end

    -- Ensure we have a good spacing after character lists
    currentYOffset = currentYOffset - lineHeight / 2

    -- General Settings Title
    local generalSettingsTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    generalSettingsTitle:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    generalSettingsTitle:SetText("General Settings")
    generalSettingsTitle:SetTextColor(1, 1, 1)
    currentYOffset = currentYOffset - lineHeight

    -- Enable Categories Checkbox
    local enableCategoriesFrame = CreateFrame("Frame", "ConsumeTracker_EnableCategoriesFrame", scrollChild)
    enableCategoriesFrame:SetWidth(WindowWidth - 10)
    enableCategoriesFrame:SetHeight(18)
    enableCategoriesFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    enableCategoriesFrame:EnableMouse(true)

    local enableCategoriesCheckbox = CreateFrame("CheckButton", "ConsumeTracker_EnableCategoriesCheckbox", enableCategoriesFrame)
    enableCategoriesCheckbox:SetWidth(16)
    enableCategoriesCheckbox:SetHeight(16)
    enableCategoriesCheckbox:SetPoint("LEFT", enableCategoriesFrame, "LEFT", 0, 0)
    enableCategoriesCheckbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    enableCategoriesCheckbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    enableCategoriesCheckbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    enableCategoriesCheckbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    enableCategoriesCheckbox:SetChecked(ConsumeTracker_Options.enableCategories)

    enableCategoriesCheckbox:SetScript("OnClick", function()
        if enableCategoriesCheckbox:GetChecked() then
            ConsumeTracker_Options.enableCategories = true
        else
            ConsumeTracker_Options.enableCategories = false 
        end
        ConsumeTracker_UpdateManagerContent()
        ConsumeTracker_UpdatePresetsConsumables()
    end)

    local enableCategoriesLabel = enableCategoriesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableCategoriesLabel:SetPoint("LEFT", enableCategoriesCheckbox, "RIGHT", 4, 0)
    enableCategoriesLabel:SetText("Enable Categories")
    enableCategoriesLabel:SetJustifyH("LEFT")
    enableCategoriesFrame:SetScript("OnMouseDown", function()
        enableCategoriesCheckbox:Click()
    end)

    currentYOffset = currentYOffset - lineHeight

    -- Show Use Button Checkbox
    local showUseButtonFrame = CreateFrame("Frame", "ConsumeTracker_ShowUseButtonFrame", scrollChild)
    showUseButtonFrame:SetWidth(WindowWidth - 10)
    showUseButtonFrame:SetHeight(18)
    showUseButtonFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    showUseButtonFrame:EnableMouse(true)

    local showUseButtonCheckbox = CreateFrame("CheckButton", "ConsumeTracker_ShowUseButtonCheckbox", showUseButtonFrame)
    showUseButtonCheckbox:SetWidth(16)
    showUseButtonCheckbox:SetHeight(16)
    showUseButtonCheckbox:SetPoint("LEFT", showUseButtonFrame, "LEFT", 0, 0)
    showUseButtonCheckbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    showUseButtonCheckbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    showUseButtonCheckbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    showUseButtonCheckbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    showUseButtonCheckbox:SetChecked(ConsumeTracker_Options.showUseButton)

    showUseButtonCheckbox:SetScript("OnClick", function()
        if showUseButtonCheckbox:GetChecked() then
            ConsumeTracker_Options.showUseButton = true
        else
            ConsumeTracker_Options.showUseButton = false 
        end
        ConsumeTracker_UpdateManagerContent()
        ConsumeTracker_UpdatePresetsConsumables()
    end)

    local showUseButtonLabel = showUseButtonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showUseButtonLabel:SetPoint("LEFT", showUseButtonCheckbox, "RIGHT", 4, 0)
    showUseButtonLabel:SetText("Show Use Button")
    showUseButtonLabel:SetJustifyH("LEFT")
    showUseButtonFrame:SetScript("OnMouseDown", function()
        showUseButtonCheckbox:Click()
    end)

    currentYOffset = currentYOffset - lineHeight - 20

    -- Show Action Bar Checkbox
    local showActionBarFrame = CreateFrame("Frame", "ConsumeTracker_ShowActionBarFrame", scrollChild)
    showActionBarFrame:SetWidth(WindowWidth - 10)
    showActionBarFrame:SetHeight(18)
    showActionBarFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    showActionBarFrame:EnableMouse(true)

    local showActionBarCheckbox = CreateFrame("CheckButton", "ConsumeTracker_ShowActionBarCheckbox", showActionBarFrame)
    showActionBarCheckbox:SetWidth(16)
    showActionBarCheckbox:SetHeight(16)
    showActionBarCheckbox:SetPoint("LEFT", showActionBarFrame, "LEFT", 0, 0)
    showActionBarCheckbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    showActionBarCheckbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    showActionBarCheckbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    showActionBarCheckbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    showActionBarCheckbox:SetChecked(ConsumeTracker_Options.showActionBar)

    showActionBarCheckbox:SetScript("OnClick", function()
        ConsumeTracker_Options.showActionBar = (showActionBarCheckbox:GetChecked() == 1)
        ConsumeTracker_UpdateActionBar()
    end)

    local showActionBarLabel = showActionBarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showActionBarLabel:SetPoint("LEFT", showActionBarCheckbox, "RIGHT", 4, 0)
    showActionBarLabel:SetText("Show Action Bar")
    showActionBarLabel:SetJustifyH("LEFT")
    showActionBarFrame:SetScript("OnMouseDown", function()
        showActionBarCheckbox:Click()
    end)

    currentYOffset = currentYOffset - lineHeight - 10

    -- Scale Slider
    local scaleSlider = CreateFrame("Slider", "ConsumeTracker_ScaleSlider", scrollChild, "OptionsSliderTemplate")
    scaleSlider:SetWidth(180)
    scaleSlider:SetHeight(16)
    scaleSlider:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, currentYOffset)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetValue(ConsumeTracker_GetCharacterSetting("actionBarScale") or ConsumeTracker_Options.actionBarScale or 1)
    
    getglobal(scaleSlider:GetName() .. "Text"):SetText("Action Bar Scale: " .. string.format("%.1f", scaleSlider:GetValue()))
    getglobal(scaleSlider:GetName() .. "Low"):SetText("0.5")
    getglobal(scaleSlider:GetName() .. "High"):SetText("2.0")

    scaleSlider:SetScript("OnValueChanged", function()
        -- Quantize to step
        local val = this:GetValue()
        val = math.floor(val * 10 + 0.5) / 10
        
        ConsumeTracker_SetCharacterSetting("actionBarScale", val)
        getglobal(this:GetName() .. "Text"):SetText("Action Bar Scale: " .. string.format("%.1f", val))
        ConsumeTracker_UpdateActionBar()
    end)

    currentYOffset = currentYOffset - lineHeight - 30

    -- Multi-Account Setup
    local multiAccountTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    multiAccountTitle:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    multiAccountTitle:SetText("Multi-Account Setup |cffff0000(BETA!)|r")
    multiAccountTitle:SetTextColor(1, 1, 1)
    currentYOffset = currentYOffset - lineHeight

    local multiAccountInfo = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    multiAccountInfo:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    multiAccountInfo:SetText("Set a unique channel name and password. \nRepeat this setup for each of your alt-accounts.")
    multiAccountInfo:SetJustifyH("LEFT")
    currentYOffset = currentYOffset - lineHeight * 2

    -- Helper to create Gold Button
    local function CreateGoldButton(name, parent, text, width, height, point, relativeTo, relativePoint, xOfs, yOfs)
        local btn = CreateFrame("Button", name, parent)
        btn:SetWidth(width)
        btn:SetHeight(height)
        btn:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
        
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        btn:SetBackdropColor(0, 0, 0, 0.5) 
        btn:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold border

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- Normal font for these buttons
        btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btnText:SetText(text)
        btnText:SetTextColor(1, 0.82, 0) -- Gold text
        btn.text = btnText

        -- Hover Effects
        btn:SetScript("OnEnter", function()
            if this:IsEnabled() == 1 then
                this:SetBackdropBorderColor(1, 1, 1, 1)
                this.text:SetTextColor(1, 1, 1)
            end
        end)
        btn:SetScript("OnLeave", function()
            if this:IsEnabled() == 1 then
                this:SetBackdropBorderColor(1, 0.82, 0, 1)
                this.text:SetTextColor(1, 0.82, 0)
            else
                this:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
                this.text:SetTextColor(0.5, 0.5, 0.5)
            end
        end)
        
        -- Hook Enabe/Disable to update visual state immediately
        local originalEnable = btn.Enable
        local originalDisable = btn.Disable
        
        btn.Enable = function(self)
            originalEnable(self)
            self:SetBackdropBorderColor(1, 0.82, 0, 1)
            self.text:SetTextColor(1, 0.82, 0)
        end
        
        btn.Disable = function(self)
            originalDisable(self)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            self.text:SetTextColor(0.5, 0.5, 0.5)
        end

        return btn
    end

    -- More Info Button (Next to BETA!)
    local popup = MultiAccountInfoPopup()
    local MoreInfoBtn = CreateGoldButton("ConsumeTracker_MoreInfoBtn", scrollChild, "More Info", 60, 16, "LEFT", multiAccountTitle, "RIGHT", 10, 0)
    MoreInfoBtn.text:SetFontObject("GameFontNormalSmall") -- Match Use button font size
    MoreInfoBtn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            popup:Show()
        end
    end)


    -- Channel Input
    local channelLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    channelLabel:SetText("Channel:")
    channelLabel:SetWidth(60)
    channelLabel:SetJustifyH("LEFT")
    channelLabel:SetTextColor(1, 1, 1)

    -- Create a frame to hold the editbox so the sub-textures stay aligned
    local channelFrame = CreateFrame("Frame", nil, scrollChild)
    channelFrame:SetHeight(20)
    channelFrame:SetWidth(140)
    channelFrame:SetPoint("LEFT", channelLabel, "RIGHT", 10, 0)

    local channelEditBox = CreateFrame("EditBox", "ConsumeTracker_ChannelEditBox", channelFrame, "InputBoxTemplate")
    channelEditBox:SetAutoFocus(false)
    channelEditBox:SetMaxLetters(50)
    channelEditBox:SetAllPoints(channelFrame) -- Fill the entire holding frame

    local leftTex = getglobal(channelEditBox:GetName().."Left")
    local midTex  = getglobal(channelEditBox:GetName().."Middle")
    local rightTex= getglobal(channelEditBox:GetName().."Right")

    -- Anchor them so they move with the EditBox
    if leftTex then
        leftTex:ClearAllPoints()
        leftTex:SetPoint("LEFT", channelEditBox, "LEFT", -5, 0)
    end
    if midTex then
        midTex:ClearAllPoints()
        midTex:SetPoint("LEFT", leftTex, "RIGHT", 0, 0)
        midTex:SetPoint("RIGHT", rightTex, "LEFT", 0, 0)
    end
    if rightTex then
        rightTex:ClearAllPoints()
        rightTex:SetPoint("RIGHT", channelEditBox, "RIGHT", 5, 0)
    end

    -- Retrieve stored channel
    local stored_channel = ""
    if ConsumeTracker_Options.Channel and ConsumeTracker_Options.Channel ~= "" then
        stored_channel = DecodeMessage(ConsumeTracker_Options.Channel)
    end
    channelEditBox:SetText(stored_channel)
    currentYOffset = currentYOffset - lineHeight

    -- Password Input
    local passwordLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    passwordLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    passwordLabel:SetText("Password:")
    passwordLabel:SetWidth(60)
    passwordLabel:SetJustifyH("LEFT")
    passwordLabel:SetTextColor(1, 1, 1)

    -- Same holding frame approach
    local passwordFrame = CreateFrame("Frame", nil, scrollChild)
    passwordFrame:SetHeight(20)
    passwordFrame:SetWidth(140)
    passwordFrame:SetPoint("LEFT", passwordLabel, "RIGHT", 10, 0)

    local passwordEditBox = CreateFrame("EditBox", "ConsumeTracker_PasswordEditBox", passwordFrame, "InputBoxTemplate")
    passwordEditBox:SetAutoFocus(false)
    passwordEditBox:SetMaxLetters(50)
    passwordEditBox:SetAllPoints(passwordFrame)

    local pLeft = getglobal(passwordEditBox:GetName().."Left")
    local pMid  = getglobal(passwordEditBox:GetName().."Middle")
    local pRight= getglobal(passwordEditBox:GetName().."Right")

    if pLeft then
        pLeft:ClearAllPoints()
        pLeft:SetPoint("LEFT", passwordEditBox, "LEFT", -5, 0)
    end
    if pMid then
        pMid:ClearAllPoints()
        pMid:SetPoint("LEFT", pLeft, "RIGHT", 0, 0)
        pMid:SetPoint("RIGHT", pRight, "LEFT", 0, 0)
    end
    if pRight then
        pRight:ClearAllPoints()
        pRight:SetPoint("RIGHT", passwordEditBox, "RIGHT", 5, 0)
    end

    local stored_password = ""
    if ConsumeTracker_Options.Password and ConsumeTracker_Options.Password ~= "" then
        stored_password = DecodeMessage(ConsumeTracker_Options.Password)
    end
    passwordEditBox:SetText(stored_password)
    currentYOffset = currentYOffset - lineHeight - 10

    -- Join and Leave Channel Buttons
    joinChannelButton = CreateGoldButton("ConsumeTracker_JoinChannelButton", scrollChild, "Save & Join Channel", 140, 24, "TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    LeaveChannelButton = CreateGoldButton("ConsumeTracker_LeaveChannelButton", scrollChild, "Leave Channel", 140, 24, "TOPLEFT", scrollChild, "TOPLEFT", 150, currentYOffset)

    -- Function to Update Leave Button State
    local function UpdateLeaveButtonState()
        if ConsumeTracker_Options.Channel == "" or ConsumeTracker_Options.Channel == nil then
            LeaveChannelButton:Disable()
            -- LeaveChannelButton:SetAlpha(0.5) -- Handled by Disable override now
            channelEditBox:SetText("")
            passwordEditBox:SetText("")
        else
            LeaveChannelButton:Enable()
            -- LeaveChannelButton:SetAlpha(1)
        end
    end

    UpdateLeaveButtonState()

    -- Leave Channel Button Script
    LeaveChannelButton:SetScript("OnClick", function()
        if ConsumeTracker_Options.Channel == "" or ConsumeTracker_Options.Channel == nil then
            UpdateLeaveButtonState()
            updateSenDataButtonState()
        else
            local decoded_channel = DecodeMessage(ConsumeTracker_Options.Channel)
            DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r |cffffffffYou left|r |cffffc0c0[" .. decoded_channel .. "]|r|cffffffff. Multi-account sync |cffff0000disabled|r|cffffffff.|r")
            LeaveChannelByName(decoded_channel)
            ConsumeTracker_Options.Channel = nil
            ConsumeTracker_Options.Password = nil
            UpdateLeaveButtonState()
            updateSenDataButtonState()
        end
    end)

    -- Channel Error Message
    local channelErrorMessage = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelErrorMessage:SetPoint("TOPLEFT", joinChannelButton, "BOTTOMLEFT", 0, -5)
    channelErrorMessage:SetTextColor(1, 0, 0)
    channelErrorMessage:SetText("Failed to join channel. Read chat for more info.")
    channelErrorMessage:Hide()
    currentYOffset = currentYOffset - lineHeight - 30

    -- Function to Update Join Button State
    local function UpdateJoinButtonState()
        local ctext = channelEditBox:GetText()
        local ptext = passwordEditBox:GetText()
        if ctext ~= "" and ptext ~= "" then
            joinChannelButton:Enable()
            -- joinChannelButton:SetAlpha(1)
        else
            joinChannelButton:Disable()
            -- joinChannelButton:SetAlpha(0.5)
        end
    end

    channelEditBox:SetScript("OnTextChanged", UpdateJoinButtonState)
    passwordEditBox:SetScript("OnTextChanged", UpdateJoinButtonState)

    UpdateJoinButtonState()

    -- Function to Handle Channel Join Failures
    function ConsumeTracker_ChannelJoinFailed(error_message)
        ConsumeTracker_Options.Channel = nil
        ConsumeTracker_Options.Password = nil
        channelEditBox:SetText("")
        passwordEditBox:SetText("")
        UpdateJoinButtonState()
        channelErrorMessage:Show()
        channelErrorMessage:SetText(error_message)
    end

    -- Danger Zone Title
    local DangerZonTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    DangerZonTitle:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    DangerZonTitle:SetText("Danger Zone")
    DangerZonTitle:SetTextColor(1, 1, 1)
    currentYOffset = currentYOffset - lineHeight * 2

    -- Reset Addon Button
    resetButton = CreateGoldButton("ConsumeTracker_ResetButton", scrollChild, "Reset Addon", 120, 24, "TOPLEFT", scrollChild, "TOPLEFT", 0, currentYOffset)
    resetButton:SetScript("OnClick", function()
        if ConsumeTracker_Options.Channel then 
            local decoded_channel = DecodeMessage(ConsumeTracker_Options.Channel)
            LeaveChannelByName(decoded_channel)
        end
        ConsumeTracker_Options = {}
        ConsumeTracker_SelectedItems = {}
        ConsumeTracker_Data = {}
        ReloadUI()
    end)

    -- Set the scroll child height to accommodate all content
    scrollChild.contentHeight = math.abs(startYOffset - currentYOffset) + 100
    scrollChild:SetHeight(scrollChild.contentHeight)

    -- Scroll Bar Setup
    -- Scroll Bar (Minimalist)
    local scrollBar = CreateFrame("Slider", "ConsumeTracker_SettingsScrollBar", parentFrame)
    scrollBar:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -5, -16) 
    scrollBar:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -5, 10)
    scrollBar:SetWidth(6)
    scrollBar:SetOrientation('VERTICAL')
    
    -- Background (Track)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(scrollBar)
    track:SetTexture(0, 0, 0, 0.4)
    
    -- Thumb
    scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = scrollBar:GetThumbTexture()
    thumb:SetVertexColor(1, 0.82, 0, 0.8) -- Gold
    thumb:SetWidth(6)
    thumb:SetHeight(30)
    
    scrollBar:SetScript("OnValueChanged", function()
        local value = this:GetValue()
        scrollFrame:SetVerticalScroll(value)
    end)
    parentFrame.scrollBar = scrollBar

    ConsumeTracker_UpdateSettingsScrollBar()

    if not ConsumeTracker_ChannelFrame then
        ConsumeTracker_ChannelFrame = CreateFrame("Frame", "ConsumeTracker_ChannelFrame")
    end

    local channelmsg = ""

    joinChannelButton:SetScript("OnClick", function()

        ConsumeTracker_ChannelFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")

        channelErrorMessage:Hide()
        local ctext = channelEditBox:GetText()
        local ptext = passwordEditBox:GetText()
        local final_result = nil
        local try_again = false

         ConsumeTracker_ChannelFrame:SetScript("OnEvent", function()
            local noticeType = string.upper(arg1 or "")
            local channelName = string.upper(arg9 or "")
            local inputChannelName = string.upper(ctext or "")

            if noticeType == "WRONG_PASSWORD" and channelName == inputChannelName then
                channelmsg = "WRONG_PASSWORD"
                --DEFAULT_CHAT_FRAME:AddMessage(noticeType)
            elseif noticeType == "NOT_MODERATOR" and channelName == inputChannelName then
                channelmsg = "NOT_MODERATOR"
                --DEFAULT_CHAT_FRAME:AddMessage(noticeType)
            elseif noticeType == "YOU_JOINED" and channelName == inputChannelName then
                channelmsg = "YOU_JOINED"
                --DEFAULT_CHAT_FRAME:AddMessage(noticeType)
            end

        end)


        -- Don't join same channel
        if ConsumeTracker_Options.Channel then
            if DecodeMessage(ConsumeTracker_Options.Channel) == ctext then
                channelErrorMessage:SetText("Already in this channel")
                channelErrorMessage:Show()
                return
            end
        end

        -- Block attempts to join big system channels
        local blocked = { "world", "general", "localdefense", "hardcore", "lft", "trade" }
        local lowerChannel = string.lower(ctext)
        for _, b in pairs(blocked) do
            if lowerChannel == b then
                ConsumeTracker_ChannelJoinFailed("You cannot use a global channel")
                return
            end
        end

        JoinChannelByName(ctext, ptext)

        joinChannelButton:SetText("Connecting... (4)")
        joinChannelButton:Disable()
        joinChannelButton:SetAlpha(0.5)


        local delayFrame = CreateFrame("Frame")
        delayFrame:Show()
        local elapsed = 0
        local delay = 5
        local one_attempt = 0

        delayFrame:SetScript("OnUpdate", function()
            

            if elapsed > 1 and elapsed < 2 then

                joinChannelButton:SetText("Connecting... (3)")

                if one_attempt == 0 then

                    DEFAULT_CHAT_FRAME:AddMessage("message: " .. channelmsg)

                    if channelmsg == "WRONG_PASSWORD" then
                        final_result = "WRONG_PASSWORD"
                    elseif channelmsg == "YOU_JOINED" then
                        DEFAULT_CHAT_FRAME:AddMessage("setting password")
                        SetChannelPassword(ctext, ptext)
                    end
                end

                one_attempt = 1


            elseif elapsed > 2 and elapsed < 3 then
                joinChannelButton:SetText("Connecting... (2)")


                if one_attempt == 1 then

                    DEFAULT_CHAT_FRAME:AddMessage("message: " .. channelmsg)

                    if channelmsg == "YOU_JOINED" then
                        final_result = "SUCCESS"
                    elseif channelmsg == "NOT_MODERATOR" then
                        LeaveChannelByName(ctext)
                        try_again = true
                    end
                end

                one_attempt = 2



            elseif elapsed > 3 and elapsed < 4 then
                joinChannelButton:SetText("Connecting... (1)")

                if one_attempt == 2 then

                    DEFAULT_CHAT_FRAME:AddMessage("message: " .. channelmsg)

                    if try_again == true then

                        JoinChannelByName(ctext, ptext)

                    end
                 end

                one_attempt = 3

            elseif elapsed > 4 and elapsed < 5 then
                joinChannelButton:SetText("Connecting... (0)")

                if one_attempt == 3 then

                    DEFAULT_CHAT_FRAME:AddMessage("message: " .. channelmsg)

                    if try_again == true then

                        if channelmsg == "YOU_JOINED" then
                            final_result = "SUCCESS"
                        elseif channelmsg == "NOT_MODERATOR" then
                            final_result = "NOT_MODERATOR"
                        end
                    end
                 end

                one_attempt = 4

            end



            elapsed = elapsed + arg1

            if elapsed >= delay then

                delayFrame:SetScript("OnUpdate", nil)
                delayFrame:Hide()


                -- ACTION AFTER 3 SECONDS


                if final_result == "SUCCESS" then

                    ConsumeTracker_Options.Channel = EncodeMessage(ctext)
                    ConsumeTracker_Options.Password = EncodeMessage(ptext)

                    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") ..
                    ":|r |cffffffffYou joined|r |cffffc0c0[" .. ctext ..
                    "]|r|cffffffff. Multi-account sync |cff00ff00enabled|r|cffffffff.|r")

                elseif final_result == "WRONG_PASSWORD" then

                    ConsumeTracker_ChannelJoinFailed("Wrong password. Try again.")

                    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") ..
                    ":|r |cffffffffWrong password for|r |cffffc0c0[" .. ctext ..
                    "]|r|cffffffff. Multi-account sync |cffff0000disabled|r|cffffffff.|r")

                elseif final_result == "NOT_MODERATOR" then

                    ConsumeTracker_ChannelJoinFailed("This is not your channel.")
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") ..
                    ":|r |cffffffffYou don't own|r |cffffc0c0[" .. ctext ..
                    "]|r|cffffffff. Multi-account sync |cffff0000disabled|r|cffffffff.|r")

                else
                    LeaveChannelByName(ctext)
                    ConsumeTracker_ChannelJoinFailed("Unknown error")
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") ..
                    ":|r |cffffffffFailed to join|r |cffffc0c0[" .. ctext ..
                    "]|r|cffffffff. Multi-account sync |cffff0000disabled|r|cffffffff.|r")
                end

                joinChannelButton:SetText("Save & Join Channel")
                joinChannelButton:Enable()
                joinChannelButton:SetAlpha(1)
                updateSenDataButtonState()
                UpdateLeaveButtonState()

                ConsumeTracker_ChannelFrame:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")

            end
            delayFrame:Show()
        end)
    end)
end

function ConsumeTracker_UpdateSettingsContent()
    local parentFrame = ConsumeTracker_MainFrame and ConsumeTracker_MainFrame.tabs and ConsumeTracker_MainFrame.tabs[4]
    if not parentFrame or not parentFrame.scrollFrame then
        return
    end

    -- Remove existing child
    local oldChild = parentFrame.scrollFrame:GetScrollChild()
    if oldChild then
        oldChild:Hide()
        oldChild:SetParent(nil)
        parentFrame.scrollFrame:SetScrollChild(nil)
    end

    -- Remove old scrollbar
    if parentFrame.scrollBar then
        parentFrame.scrollBar:Hide()
        parentFrame.scrollBar:SetParent(nil)
        parentFrame.scrollBar = nil
    end

    -- New scroll child
    local newScrollChild = CreateFrame("Frame", nil, parentFrame.scrollFrame)
    newScrollChild:SetWidth(WindowWidth - 10)
    newScrollChild:SetHeight(1)
    newScrollChild.contentHeight = 0
    parentFrame.scrollFrame:SetScrollChild(newScrollChild)
    parentFrame.scrollChild = newScrollChild

    -- Build content
    ConsumeTracker_CreateSettingsContent(parentFrame)

    -- Reset scroll
    if parentFrame.scrollBar then
        parentFrame.scrollBar:SetValue(0)
    end
end

function ConsumeTracker_UpdateSettingsScrollBar()
    local OptionsFrame = ConsumeTracker_MainFrame and ConsumeTracker_MainFrame.tabs and ConsumeTracker_MainFrame.tabs[4]
    if not OptionsFrame then
        return
    end
    local scrollBar = OptionsFrame.scrollBar
    local scrollFrame = OptionsFrame.scrollFrame
    local scrollChild = OptionsFrame.scrollChild

    local totalHeight = scrollChild.contentHeight
    local shownHeight = 420

    local maxScroll = math.max(0, totalHeight - shownHeight)
    scrollFrame.maxScroll = maxScroll

    if totalHeight > shownHeight then
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(math.min(scrollBar:GetValue(), maxScroll))
        scrollBar:Show()
    else
        scrollFrame.maxScroll = 0
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        scrollBar:Hide()
    end
end



-- Global Functions -----------------------------------------------------------------------------
function ConsumeTracker_UpdateUseButtons()
    if not ConsumeTracker_MainFrame or not ConsumeTracker_MainFrame.tabs or not ConsumeTracker_MainFrame.tabs[1] then
        return
    end

    local ManagerFrame = ConsumeTracker_MainFrame.tabs[1]
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    local faction = UnitFactionGroup("player")

    -- Ensure data structure exists
    if not ConsumeTracker_Data[realmName] or not ConsumeTracker_Data[realmName][faction] then
        return
    end
    local data = ConsumeTracker_Data[realmName][faction]
    local charData = data[playerName]
    if not charData then return end

    local inventory = charData["inventory"] or {}

    -- Iterate over the Items to update the buttons
    for _, categoryInfo in ipairs(ManagerFrame.categoryInfo) do
        for _, itemInfo in ipairs(categoryInfo.Items) do
            local itemID = itemInfo.itemID
            local button = itemInfo.button
            local label = itemInfo.label
            local frame = itemInfo.frame

            if ConsumeTracker_SelectedItems[itemID] then
                local count = inventory[itemID] or 0
                if count > 0 then
                    if ConsumeTracker_Options.showUseButton then
                        button:Enable()
                        button:Show()
                        label:SetPoint("LEFT", button, "RIGHT", 4, 0)
                    else
                        button:Disable()
                        button:Hide()
                        label:SetPoint("LEFT", frame, "LEFT", 0, 0)
                    end
                else
                    button:Disable()
                    button:Hide()
                    label:SetPoint("LEFT", frame, "LEFT", 0, 0)
                end
            else
                button:Disable()
                button:Hide()
                label:SetPoint("LEFT", frame, "LEFT", 0, 0)
            end
        end
    end
end

function ConsumeTracker_FindItemInBags(itemID)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, linkItemID = string.find(link, "item:(%d+)")
                    if linkItemID then
                        linkItemID = tonumber(linkItemID)
                        if linkItemID == itemID then
                            return bag, slot
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

function ConsumeTracker_GetConsumableCount(itemID)
    local totalCount = 0
    local realmName = GetRealmName()

    -- Early exit if no data
    if not ConsumeTracker_Data[realmName] then 
        return 0 
    end

    -- Loop through all characters regardless of faction
    for character, charData in pairs(ConsumeTracker_Data[realmName]) do
        if type(charData) == "table" and ConsumeTracker_Options["Characters"] and ConsumeTracker_Options["Characters"][character] == true then
            if character ~= "faction" then  -- Skip non-character metadata
                if charData["inventory"] and charData["inventory"][itemID] then
                    totalCount = totalCount + charData["inventory"][itemID]
                end
                if charData["bank"] and charData["bank"][itemID] then
                    totalCount = totalCount + charData["bank"][itemID]
                end
                if charData["mail"] and charData["mail"][itemID] then
                    totalCount = totalCount + charData["mail"][itemID]
                end
            end
        end
    end
    
    return totalCount
end

function ConsumeTracker_UpdateAllContent()
    ConsumeTracker_UpdateManagerContent()
    ConsumeTracker_UpdatePresetsConsumables()
    ConsumeTracker_UpdateSettingsContent()
end

function ConsumeTracker_DisableTab(tab)
    tab.isEnabled = false
    tab:EnableMouse(true)  -- Keep mouse enabled for tooltip
    tab.icon:SetDesaturated(true)  -- Grey out the icon
    tab:SetScript("OnClick", nil)  -- Remove OnClick handler

    -- Hide highlight effect
    if tab.hoverTexture then
        tab.hoverTexture:SetAlpha(0)
    end

    -- Adjust OnEnter handler to show tooltip only
    tab:SetScript("OnEnter", function()
        ShowTooltip(tab, tab.tooltipText)
    end)
    tab:SetScript("OnLeave", HideTooltip)
end

function ConsumeTracker_EnableTab(tab)
    tab.isEnabled = true
    tab:EnableMouse(true)
    tab.icon:SetDesaturated(false)
    tab:SetScript("OnClick", tab.originalOnClick)  -- Restore OnClick handler

    -- Show highlight effect
    if tab.hoverTexture then
        tab.hoverTexture:SetAlpha(1)
    end

    -- Restore original OnEnter and OnLeave handlers
    tab:SetScript("OnEnter", function()
        ShowTooltip(tab, tab.tooltipText)
    end)
    tab:SetScript("OnLeave", HideTooltip)
end

function ConsumeTracker_CheckBankAndMailScanned()
    local realmName = GetRealmName()
    local playerName = UnitName("player")

    -- Ensure data structure exists
    if not ConsumeTracker_Data[realmName] or not ConsumeTracker_Data[realmName][playerName] then
        return false, false
    end
    
    local currentCharData = ConsumeTracker_Data[realmName][playerName]
    
    local bankScanned = currentCharData["bank"] ~= nil
    local mailScanned = currentCharData["mail"] ~= nil

    return bankScanned, mailScanned
end


function ConsumeTracker_UpdateTabStates()
    if not ConsumeTracker_Tabs or not ConsumeTracker_Tabs[2] or not ConsumeTracker_Tabs[3] then
        -- Tabs have not been created yet; exit the function
        return
    end

    local bankScanned, mailScanned = ConsumeTracker_CheckBankAndMailScanned()
    if bankScanned and mailScanned then
        ConsumeTracker_EnableTab(ConsumeTracker_Tabs[2])  -- Items Tab
        ConsumeTracker_EnableTab(ConsumeTracker_Tabs[3])  -- Presets Tab
    else
        ConsumeTracker_DisableTab(ConsumeTracker_Tabs[2])  -- Items Tab
        ConsumeTracker_DisableTab(ConsumeTracker_Tabs[3])  -- Presets Tab
    end
end

function MultiAccountInfoPopup()
    -- Create the frame
    local popup = CreateFrame("Frame", "MyPopupFrame", UIParent)
    popup:SetHeight(180)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground", -- Solid black background
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    popup:SetBackdropColor(0, 0, 0, 1) -- Black background with full opacity
    popup:SetBackdropBorderColor(1, 1, 1, 1) -- White border
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(1000)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    popup:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)

    -- Add a close button
    local closeButton = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)

    -- Add a title
    local infotitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    infotitle:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -20)
    infotitle:SetText("How does it work?")
    infotitle:SetTextColor(1,1,1)

    -- Add the infotext
    popup.infotext = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.infotext:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -35)
    popup.infotext:SetJustifyH("LEFT")
    popup.infotext:SetText(
        "|cffff0000(Beta Feature! Might be glitchy!)|r\n\n" ..
        "To sync accounts, follow these steps:\n\n" ..
        "1. Join a private channel with a unique name and password.\n" ..
        "2. The channel info is saved for all characters on your account.\n" ..
        "3. Log into your alt account on a second client.\n" ..
        "4. Join the same channel via this addon to link both accounts.\n" ..
        "5. Keep one character from your main account online for syncing.\n" ..
        "6. Click on 'Push Data' to send the database from one account to all the other that are online."
    )


    -- Function to adjust width dynamically after text is set
    popup:SetScript("OnShow", function()
        local textWidth = popup.infotext:GetStringWidth() + 40 -- Add padding
        popup:SetWidth(textWidth)
    end)

    popup:Hide()
    return popup
end



-- Tooltip Functions  --------------------------------------------------------------------------------------
function ConsumeTracker_ShowConsumableTooltip(itemID)
    -- Ensure item is enabled in settings or part of presets
    if not ConsumeTracker_SelectedItems[itemID] and not ConsumeTracker_IsItemInPresets(itemID) then
        return
    end

    -- Create or reuse custom tooltip frame
    if not ConsumeTracker_CustomTooltip then
        -- Create the frame
        local tooltipFrame = CreateFrame("Frame", "ConsumeTracker_CustomTooltip", UIParent)
        tooltipFrame:SetFrameStrata("TOOLTIP")
        tooltipFrame:SetWidth(200)
        tooltipFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        tooltipFrame:SetBackdropColor(0, 0, 0, 1)

        -- Item icon
        local icon = tooltipFrame:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(32)
        icon:SetHeight(32)
        icon:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 10, -10)
        tooltipFrame.icon = icon

        -- Item name
        local title = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
        title:SetJustifyH("LEFT")
        tooltipFrame.title = title

        -- Item Total
        local total = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        total:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -20)
        total:SetJustifyH("LEFT")
        tooltipFrame.total = total

        -- Content text
        local content = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        content:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
        content:SetJustifyH("LEFT")
        tooltipFrame.content = content

        -- Mats text
        local mats = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mats:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -10)
        mats:SetJustifyH("LEFT")
        tooltipFrame.mats = mats

        ConsumeTracker_CustomTooltip = tooltipFrame
    end

    local tooltipFrame = ConsumeTracker_CustomTooltip

    -- Get item info
    local itemName = consumablesList[itemID] or "Unknown Item"
    local itemTexture = consumablesTexture[itemID] or "Interface\\Icons\\INV_Misc_QuestionMark"
   
    -- Set icon and title
    tooltipFrame.icon:SetTexture(itemTexture)
    tooltipFrame.title:SetText(itemName)

    local mats = consumablesMats[itemID] or {}
    local matsText = ""

    if type(mats) == "table" and next(mats) then
        local index = 0
        local divider = ""
        for _, mat in ipairs(mats) do
            index = index + 1
            if index > 1 then
                divider = " | "
            else
                divider = ""
            end

            matsText = matsText .. divider .. "|cff4ac9ff" .. mat .. "|r" 
        end
    else
        matsText = "|cff696969No materials specified for this item.|r"
    end

    tooltipFrame.mats:SetText(matsText)

    -- Prepare content text
    local contentText = ""
    local realmName = GetRealmName()
    local playerName = UnitName("player")
    local playerFaction = UnitFactionGroup("player")

    -- Ensure data structure exists
    ConsumeTracker_Data[realmName] = ConsumeTracker_Data[realmName] or {}

    -- Initialize totals
    local totalInventory, totalBank, totalMail = 0, 0, 0
    local hasItems = false
    local characterList = {}

    -- Ensure character settings exist
    ConsumeTracker_Options["Characters"] = ConsumeTracker_Options["Characters"] or {}

    -- Collect data for each character
    for character, charData in pairs(ConsumeTracker_Data[realmName]) do
        -- Make sure it's a character data table and not metadata
        if type(charData) == "table" and ConsumeTracker_Options["Characters"][character] == true then
            -- Get faction info for display
            local charFaction = charData.faction or "Unknown"
            local inventory = charData["inventory"] and charData["inventory"][itemID] or 0
            local bank = charData["bank"] and charData["bank"][itemID] or 0
            local mail = charData["mail"] and charData["mail"][itemID] or 0
            local total = inventory + bank + mail

            if total > 0 then
                hasItems = true
                totalInventory = totalInventory + inventory
                totalBank = totalBank + bank
                totalMail = totalMail + mail

                table.insert(characterList, {
                    name = character,
                    faction = charFaction,
                    inventory = inventory,
                    bank = bank,
                    mail = mail,
                    total = total,
                    isPlayer = (character == playerName)
                })
            end
        end
    end

    local totalItems = totalInventory + totalBank + totalMail
    -- Adjust label color based on count
    if totalItems == 0 then
        tooltipFrame.total:SetTextColor(1, 0, 0)  -- Red
    elseif totalItems < 10 then
        tooltipFrame.total:SetTextColor(1, 0.4, 0)  -- Orange
    elseif totalItems <= 20 then
        tooltipFrame.total:SetTextColor(1, 0.85, 0)  -- Yellow
    else
        tooltipFrame.total:SetTextColor(0, 1, 0)  -- Green
    end

    tooltipFrame.total:SetText("Total: " .. totalItems)

    if not hasItems then
        contentText = contentText .. "|cffff0000No items found for this consumable.|r"
        lineHeightAdjust = 10
    else
        lineHeightAdjust = 0
        -- Sort characters alphabetically
        table.sort(characterList, function(a, b) return a.name < b.name end)

        -- Display data for each character
        for _, charInfo in ipairs(characterList) do
            local nameColor = charInfo.isPlayer and "|cff00ff00" or "|cffffffff"  -- Green for player, white for others
            local factionColor = ""
            
            -- Color code by faction
            if charInfo.faction == "Alliance" then
                factionColor = "|cff0078ff"  -- Blue for Alliance
            elseif charInfo.faction == "Horde" then
                factionColor = "|cffb30000"  -- Red for Horde
            else
                factionColor = "|cff808080"  -- Grey for unknown
            end
            
            contentText = contentText .. nameColor .. charInfo.name .. factionColor .. " [" .. charInfo.faction .. "]|r (" .. charInfo.total .. ")\n"

            local detailText = ""
            if charInfo.inventory > 0 then
                detailText = detailText .. "|cffffffffInventory:|r " .. charInfo.inventory .. "  "
            end
            if charInfo.bank > 0 then
                detailText = detailText .. "|cffffffffBank:|r " .. charInfo.bank .. "  "
            end
            if charInfo.mail > 0 then
                detailText = detailText .. "|cffffffffMail:|r " .. charInfo.mail .. "  "
            end

            contentText = contentText .. "  " .. detailText .. "\n\n"
        end
    end

    tooltipFrame.content:SetText(contentText)

    -- Calculate the number of lines in contentText using string.gsub
    local _, numLines = string.gsub(contentText, "\n", "")
    numLines = numLines + 2  -- Add lines for title and padding

    -- Adjust tooltip height based on the number of lines
    local lineHeightTooltip = 12
    local totalHeight = 60 + (numLines * lineHeightTooltip) + lineHeightAdjust
    tooltipFrame:SetHeight(totalHeight)

    -- Set the width based on content
    local titleWidth = math.max(tooltipFrame.mats:GetStringWidth() + 20, tooltipFrame.title:GetStringWidth() + 60)
    local maxWidth = math.max(titleWidth, tooltipFrame.content:GetStringWidth() + 20)
    tooltipFrame:SetWidth(maxWidth)

    -- Position the tooltip near the cursor
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    tooltipFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 10, y / scale - 10)

    tooltipFrame:Show()
end

function ConsumeTracker_ShowItemsTooltip(itemID, anchorFrame)
    -- Set the maximum width for the description text
    local maxDescriptionWidth = 200

    -- Create or reuse the tooltip frame
    if not ConsumeTracker_ItemsTooltip then
        -- Create the frame
        local tooltipFrame = CreateFrame("Frame", "ConsumeTracker_ItemsTooltip", UIParent)
        tooltipFrame:SetFrameStrata("TOOLTIP")
        tooltipFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        tooltipFrame:SetBackdropColor(0, 0, 0, 1)

        -- Item icon
        local icon = tooltipFrame:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(32)
        icon:SetHeight(32)
        icon:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 10, -10)
        tooltipFrame.icon = icon

        -- Item name
        local title = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
        title:SetJustifyH("LEFT")
        tooltipFrame.title = title

        -- Item description
        local description = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
        description:SetWidth(maxDescriptionWidth)
        description:SetJustifyH("LEFT")
        description:SetTextColor(1, 1, 1)
        tooltipFrame.description = description

        -- Mats text
        local mats = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mats:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -10)
        mats:SetJustifyH("LEFT")
        tooltipFrame.mats = mats

        ConsumeTracker_ItemsTooltip = tooltipFrame
    end

    local tooltipFrame = ConsumeTracker_ItemsTooltip

    -- Get item info
    local itemName = consumablesList[itemID] or "Unknown Item"
    local itemTexture = consumablesTexture[itemID] or "Interface\\Icons\\INV_Misc_QuestionMark"
    local itemDescription = consumablesDescription[itemID] or ""

    -- Set icon, title, and description
    tooltipFrame.icon:SetTexture(itemTexture)
    tooltipFrame.title:SetText(itemName)
    tooltipFrame.description:SetText(itemDescription)

        local mats = consumablesMats[itemID] or {}
    local matsText = ""

    if type(mats) == "table" and next(mats) then
        local index = 0
        local divider = ""
        for _, mat in ipairs(mats) do
            index = index + 1
            if index > 1 then
                divider = " | "
            else
                divider = ""
            end

            matsText =   matsText .. divider .. "|cff4ac9ff" .. mat .. "|r" 
        end
    else
        matsText = "|cff696969No materials specified for this item.|r"
    end

    tooltipFrame.mats:SetText(matsText)

    -- Adjust the height of the description based on its content
    tooltipFrame.description:SetWidth(maxDescriptionWidth)
    tooltipFrame.description:SetText(itemDescription)
    local descriptionHeight = tooltipFrame.description:GetHeight()

    -- Adjust tooltip height based on content
    local totalHeight = 80 + descriptionHeight
    tooltipFrame:SetHeight(totalHeight)

    -- Set the width of the tooltip
    local titleWidth = math.max(tooltipFrame.title:GetStringWidth() + 70, tooltipFrame.mats:GetStringWidth() + 20)
    local maxWidth = math.max(titleWidth, maxDescriptionWidth + 20)
    tooltipFrame:SetWidth(maxWidth)

    -- Position the tooltip
    if anchorFrame then
        tooltipFrame:ClearAllPoints()
        tooltipFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPRIGHT", 0, 0)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        tooltipFrame:ClearAllPoints()
        tooltipFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 10, y / scale - 10)
    end

    tooltipFrame:Show()
end

function ShowTooltip(tab, text)
    ConsumeTrackerTooltip.text:SetText(text)
    ConsumeTrackerTooltip:SetPoint("BOTTOMLEFT", tab, "TOPLEFT", 0, 0)
    ConsumeTrackerTooltip:Show()
end

function HideTooltip()
    ConsumeTrackerTooltip:Hide()
end



-- Scan Functions ---------------------------------------------------------------------------------------
function ConsumeTracker_ScanPlayerInventory()
    local delayFrameInv = CreateFrame("Frame")
    local delayStartTime = GetTime()
    local delay = 0.5

    delayFrameInv:SetScript("OnUpdate", function()
        if GetTime() - delayStartTime >= delay then
            local playerName = UnitName("player")
            local realmName = GetRealmName()
            local faction = UnitFactionGroup("player")

            -- Initialize data structure without faction separation
            ConsumeTracker_Data[realmName] = ConsumeTracker_Data[realmName] or {}
            
            -- Store faction information with player data for display purposes
            if not ConsumeTracker_Data[realmName][playerName] then
                ConsumeTracker_Data[realmName][playerName] = {
                    faction = faction  -- Store faction information with the character
                }
            else
                ConsumeTracker_Data[realmName][playerName].faction = faction
            end
            
            -- Initialize inventory data
            ConsumeTracker_Data[realmName][playerName]["inventory"] = {}

            -- Scan bags
            for bag = 0, 4 do
                local numSlots = GetContainerNumSlots(bag)
                if numSlots then
                    for slot = 1, numSlots do
                        local link = GetContainerItemLink(bag, slot)
                        if link then
                            local _, _, itemID = string.find(link, "item:(%d+)")
                            if itemID then
                                itemID = tonumber(itemID)
                                if consumablesList[itemID] then
                                    local _, itemCount = GetContainerItemInfo(bag, slot)
                                    if itemCount and itemCount ~= 0 then
                                        if itemCount < 0 then itemCount = -itemCount end
                                        ConsumeTracker_Data[realmName][playerName]["inventory"][itemID] = (ConsumeTracker_Data[realmName][playerName]["inventory"][itemID] or 0) + itemCount
                                    end
                                end
                            end
                        end
                    end
                end
            end

            ConsumeTracker_UpdateUseButtons()
            ConsumeTracker_UpdateManagerContent()
            ConsumeTracker_UpdateTabStates()
            delayFrameInv:SetScript("OnUpdate", nil)
        end
    end)
end

function ConsumeTracker_ScanPlayerBank()
    if not isBankOpen then return end

    local delayFrameBank = CreateFrame("Frame")
    local delayStartTime = GetTime()
    local delay = 0.5

    delayFrameBank:SetScript("OnUpdate", function()
        if GetTime() - delayStartTime >= delay then
            local playerName = UnitName("player")
            local realmName = GetRealmName()
            local faction = UnitFactionGroup("player")

            -- Initialize data structure without faction separation
            ConsumeTracker_Data[realmName] = ConsumeTracker_Data[realmName] or {}
            
            -- Update faction information (in case it changed or was missing)
            if not ConsumeTracker_Data[realmName][playerName] then
                ConsumeTracker_Data[realmName][playerName] = {
                    faction = faction
                }
            else
                ConsumeTracker_Data[realmName][playerName].faction = faction
            end
            
            -- Initialize bank data if it doesn't exist yet
            ConsumeTracker_Data[realmName][playerName]["bank"] = {}
            
            -- Create a temporary table to track what we find
            local tempBankData = {}

            for bag = -1, 10 do
                if bag == -1 or (bag >= 5 and bag <= 10) then
                    local numSlots = GetContainerNumSlots(bag)
                    if numSlots then
                        for slot = 1, numSlots do
                            local link = GetContainerItemLink(bag, slot)
                            if link then
                                local _, _, itemID = string.find(link, "item:(%d+)")
                                if itemID then
                                    itemID = tonumber(itemID)
                                    if consumablesList[itemID] then
                                        local _, itemCount = GetContainerItemInfo(bag, slot)
                                        if itemCount and itemCount ~= 0 then
                                            if itemCount < 0 then itemCount = -itemCount end
                                            tempBankData[itemID] = (tempBankData[itemID] or 0) + itemCount
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Update only the items we found, preserve existing data for items we didn't scan
            for itemID, count in pairs(tempBankData) do
                ConsumeTracker_Data[realmName][playerName]["bank"][itemID] = count
            end

            ConsumeTracker_UpdateManagerContent()
            ConsumeTracker_UpdateTabStates()
            delayFrameBank:SetScript("OnUpdate", nil)
        end
    end)
end

function ConsumeTracker_ScanPlayerMail()
    if not isMailOpen then return end

    local delayFrameMail = CreateFrame("Frame")
    local delayStartTime = GetTime()
    local delay = 0.5

    delayFrameMail:SetScript("OnUpdate", function()
        if GetTime() - delayStartTime >= delay then
            local playerName = UnitName("player")
            local realmName = GetRealmName()
            local faction = UnitFactionGroup("player")

            -- Initialize data structure without faction separation
            ConsumeTracker_Data[realmName] = ConsumeTracker_Data[realmName] or {}
            
            -- Update faction information
            if not ConsumeTracker_Data[realmName][playerName] then
                ConsumeTracker_Data[realmName][playerName] = {
                    faction = faction
                }
            else
                ConsumeTracker_Data[realmName][playerName].faction = faction
            end
            
            -- Initialize mail data
            ConsumeTracker_Data[realmName][playerName]["mail"] = {}

            local numInboxItems = GetInboxNumItems()
            if numInboxItems and numInboxItems > 0 then
                for mailIndex = 1, numInboxItems do
                    local itemName, _, itemCount = GetInboxItem(mailIndex)
                    if itemName and itemCount and itemCount > 0 then
                        local itemID = consumablesNameToID[itemName]
                        if itemID and consumablesList[itemID] then
                            ConsumeTracker_Data[realmName][playerName]["mail"][itemID] = (ConsumeTracker_Data[realmName][playerName]["mail"][itemID] or 0) + itemCount
                        end
                    end
                end
            end

            ConsumeTracker_UpdateManagerContent()
            ConsumeTracker_UpdateTabStates()
            delayFrameMail:SetScript("OnUpdate", nil)
        end
    end)
end





-- Multi-Account Data Handling --------------------------------------------------------------------------


    local Converter = LibStub("LibCompress", true)


-- SEND DATA
    local countdownFrame = CreateFrame("Frame")
    countdownFrame:Hide()
    local countdownTimer = 0
    local Syncing = false
    local ProgressBar = 0
    local total_time_stored = 0
    local BarHeight = 0

    local function SyncInProgress(syncing, totalTime)
        if syncing then
            sendDataButton:Disable()
            sendDataButton:SetAlpha(1) -- Keep full opacity to see progress
            sendDataButton.isSyncing = true
            
            -- Hide text, show progress bar
            sendDataButton.text:Hide()
            sendDataButton.checkmark:Hide()
            sendDataButton.progressBar:SetWidth(0)
            sendDataButton.progressBar:Show()
            
            LeaveChannelButton:Disable()
            LeaveChannelButton:SetAlpha(0.5)
            joinChannelButton:Disable()
            joinChannelButton:SetAlpha(0.5)
            resetButton:Disable()
            resetButton:SetAlpha(0.5)

            -- Old progress bar (removed - now using mini button progress bar)
            -- ProgressBarFrame:Show()
            -- ProgressBarFrame_Text:Show()

            ProgressBar = totalTime
            if total_time_stored == 0 then
                total_time_stored = totalTime
            end
            countdownTimer = 0
            BarHeight = 0
            -- ProgressBarFrame_fill:SetHeight(0)

            countdownFrame:Show()
        else
            sendDataButton.isSyncing = false
            
            -- Show checkmark briefly, then restore text
            sendDataButton.progressBar:Hide()
            sendDataButton.checkmark:Show()
            
            -- Delay to show checkmark for 1.5 seconds before restoring text
            local checkmarkFrame = CreateFrame("Frame")
            local checkmarkTimer = 0
            checkmarkFrame:SetScript("OnUpdate", function()
                checkmarkTimer = checkmarkTimer + arg1
                if checkmarkTimer >= 1.5 then
                    sendDataButton.checkmark:Hide()
                    sendDataButton.text:Show()
                    sendDataButton:Enable()
                    sendDataButton:SetAlpha(1)
                    checkmarkFrame:SetScript("OnUpdate", nil)
                end
            end)
            
            LeaveChannelButton:Enable()
            LeaveChannelButton:SetAlpha(1)
            joinChannelButton:Enable()
            joinChannelButton:SetAlpha(1)
            resetButton:Enable()
            resetButton:SetAlpha(1)

            -- ProgressBarFrame:Hide()
            -- ProgressBarFrame_Text:Hide()
            -- ProgressBarFrame_fill:SetHeight(0)
            ProgressBar = 0
            total_time_stored = 0
            BarHeight = 0
            -- ProgressBarFrame_fill:Hide()

            countdownFrame:Hide()
        end
        Syncing = syncing
    end

    countdownFrame:SetScript("OnUpdate", function()
        if Syncing and ProgressBar > 0 then
            countdownTimer = countdownTimer + arg1
            if countdownTimer >= 1 then
                ProgressBar = ProgressBar - 1
                if BarHeight < 492 then
                    BarHeight = 492 - (492 / (total_time_stored - 1)) * (ProgressBar - 1)
                    if BarHeight > 492 then
                        BarHeight = 492
                    end
                end
                -- ProgressBarFrame_fill:Show()
                -- ProgressBarFrame_fill:SetHeight(BarHeight)
                
                -- Update mini progress bar in sync button
                local buttonWidth = sendDataButton:GetWidth() - 4 -- Account for padding
                local progress = 1 - (ProgressBar / total_time_stored)
                local miniWidth = buttonWidth * progress
                if miniWidth < 0 then miniWidth = 0 end
                if miniWidth > buttonWidth then miniWidth = buttonWidth end
                sendDataButton.progressBar:SetWidth(miniWidth)
                
                countdownTimer = 0
            end
        end
    end)

    function PushData()
        if not ConsumeTracker_Options.Channel or ConsumeTracker_Options.Channel == "" or
           not ConsumeTracker_Options.Password or ConsumeTracker_Options.Password == "" then
            return
        end

        local realmName = GetRealmName()
        local dataTable = ConsumeTracker_Data[realmName]  -- Send all data, not just current faction
        local serialized = Converter:TableToString(dataTable)
        local compressed = lzw:compress(serialized)
        local data = EncodeMessage(compressed)

        local channelName = DecodeMessage(ConsumeTracker_Options.Channel)
        local channelNumber = GetChannelName(channelName)
        local length = string.len(data)
        local chunkSize = 100
        local pos = 1
        local queue = {}
        while pos <= length do
            local chunk = string.sub(data, pos, pos + chunkSize - 1)
            pos = pos + chunkSize
            table.insert(queue, chunk)
        end

        local totalMessages = table.getn(queue)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r |cffffffffData pushing started in|r |cffffc0c0[" .. DecodeMessage(ConsumeTracker_Options.Channel) .. "]|r|cffffffff. Please wait...|r")
        SendChatMessage("CM_SYNC_STARTED", "CHANNEL", nil, channelNumber)
        SyncInProgress(true, totalMessages)

        local receivedChunks = {}
        local sendFrame = CreateFrame("Frame")
        local eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")

        local state = "IDLE"
        local currentIndex = 0
        local sendTimeout = 2
        local lockoutDuration = 10
        local lockedOutUntil = 0
        local waitingForVerification = false
        local verificationElapsed = 0
        local verificationWaitTime = 1
        local currentStartTime = 0

        eventFrame:SetScript("OnEvent", function()
            if event == "CHAT_MSG_CHANNEL" then
                local msg = arg1
                local iStart, iEnd, msgIndex, chunk = string.find(msg, "^CM_(%d+):(.+)$")
                if msgIndex and chunk then
                    msgIndex = tonumber(msgIndex)
                    receivedChunks[msgIndex] = chunk
                    if state == "WAITING" and msgIndex == currentIndex + 1 then
                        table.remove(queue, 1)
                        currentIndex = currentIndex + 1
                        state = "IDLE"
                    end
                end
            end
        end)

        local function verifyData()
            for i=1, totalMessages do
                if not receivedChunks[i] then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r Data validation |cffff0000failed|r|cffffffff!|r")
                    return
                end
            end
            local reconstructed = table.concat(receivedChunks, "")
            if reconstructed == data then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r Data validation |cff00ff00succeeded|r|cffffffff!|r")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r Data validation |cffff0000failed|r|cffffffff!|r")
            end
        end

        sendFrame:SetScript("OnUpdate", function()
            local now = GetTime()

            if waitingForVerification then
                verificationElapsed = verificationElapsed + arg1
                if verificationElapsed >= verificationWaitTime then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r Data pushing |cff00ff00finished|r|cffffffff!|r")
                    verifyData()
                    SendChatMessage("CM_SYNC_STOPPED", "CHANNEL", nil, channelNumber)
                    SyncInProgress(false, 0)
                    eventFrame:UnregisterEvent("CHAT_MSG_CHANNEL")
                    sendFrame:SetScript("OnUpdate", nil)
                    sendFrame:Hide()
                end
                return
            end

            if table.getn(queue) == 0 then
                waitingForVerification = true
                verificationElapsed = 0
                return
            end

            if state == "LOCKED" then
                if now >= lockedOutUntil then
                    state = "IDLE"
                else
                    return
                end
            end

            if state == "IDLE" then
                local nextMsg = queue[1]
                if nextMsg then
                    SendChatMessage("CM_" .. (currentIndex + 1) .. ":" .. nextMsg, "CHANNEL", nil, channelNumber)
                    currentStartTime = now
                    state = "WAITING"
                end
            elseif state == "WAITING" then
                if now - currentStartTime > sendTimeout then
                    state = "LOCKED"
                    lockedOutUntil = now + lockoutDuration
                end
            end
        end)

        sendFrame:Show()
    end


-- READ DATA


    local collecting = false
    local collectedChunks = {}
    local collectingFrom = ""
    local collectingCount = 0
    local dataComplete = false
    local eventFrame = nil
    local channelName = ""

    local function ResetCollection()
        collecting = false
        collectingFrom = ""
        collectedChunks = {}
        collectingCount = 0
        dataComplete = false
    end

    -- Adjusted to accept 'sender' as a parameter
    local function StopCollecting(sender)
        collecting = false

        if sendDataButton then
            sendDataButton:Enable()
            sendDataButton.icon:SetDesaturated(false)
        end

        local total = table.getn(collectedChunks)
        if total > 0 then
            local i = 1
            local finalString = ""
            while i <= total do
                if collectedChunks[i] then
                    finalString = finalString .. collectedChunks[i]
                end
                i = i + 1
            end
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r |cffffffffData |cff00ff00successfully|r retrieved from|r |cff00ccff" 
                .. sender .. "|r|cffffffff (" 
                .. total .. " chunks & " .. string.len(finalString) .. " data length)|r"
            )
            combineVariableTables(finalString)
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") .. ":|r |cffffffffData transmission |cffff0000failed|r from|r |cff00ccff" 
                .. sender .. "|r"
            )
        end
    end

    local function StartCollecting(sender)
        collecting = true
        collectingFrom = sender
        collectedChunks = {}
        collectingCount = 0
        dataComplete = false

        if sendDataButton then
            sendDataButton:Disable()
            sendDataButton.icon:SetDesaturated(true)
        end

        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffffff" .. GetAddOnMetadata("ConsumeTracker", "Title") 
            .. ":|r |cffffffffReceiving data from|r |cff00ccff" 
            .. sender .. "|r|cffffffff...|r"
        )
    end

    local function OnChatMessage()
        if event == "CHAT_MSG_CHANNEL" then
            local msg = arg1
            local sender = arg2
            local chName = arg9

            if chName == channelName and channelName ~= "" then
                if msg == "CM_SYNC_STARTED" then
                    if sender ~= UnitName("player") and not collecting then
                        StartCollecting(sender)
                    end
                elseif msg == "CM_SYNC_STOPPED" then
                    if collecting and sender == collectingFrom then
                        StopCollecting(sender)   -- Pass 'sender' here
                        ResetCollection()
                    end
                else
                    if collecting and sender == collectingFrom then
                        local iStart, iEnd, msgIndex, chunk = string.find(msg, "^CM_(%d+):(.+)$")
                        if msgIndex and chunk then
                            msgIndex = tonumber(msgIndex)
                            collectedChunks[msgIndex] = chunk
                            collectingCount = collectingCount + 1
                        end
                    end
                end
            end
        end
    end

    function ReadData(mode)
        if not ConsumeTracker_Options.Channel or ConsumeTracker_Options.Channel == "" then
            return
        end

        channelName = DecodeMessage(ConsumeTracker_Options.Channel)
        local channelNumber = GetChannelName(channelName)

        if not channelNumber or channelNumber == 0 then
            return
        end

        if mode == "start" then
            if not eventFrame then
                eventFrame = CreateFrame("Frame")
                eventFrame:SetScript("OnEvent", OnChatMessage)
            end
            eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
        elseif mode == "stop" then
            if eventFrame then
                eventFrame:UnregisterEvent("CHAT_MSG_CHANNEL")
                if collecting then
                    StopCollecting(collectingFrom)  -- Pass 'collectingFrom'
                    ResetCollection()
                end
            end
        end
    end

    -- Register for PLAYER_LOGIN (or VARIABLES_LOADED in 1.12) to start listening automatically
    local startupFrame = CreateFrame("Frame")
    startupFrame:RegisterEvent("PLAYER_LOGIN")
    startupFrame:SetScript("OnEvent", function()
        if event == "PLAYER_LOGIN" then
            ReadData("start")
        end
    end)


    function combineVariableTables(compressed_message)
        local receivedTable = {}
        local realmName = GetRealmName()

        local decoded = DecodeMessage(compressed_message)
        local uncompressed = lzw:decompress(decoded)
        receivedTable = Converter:StringToTable(uncompressed)

        -- Initialize if needed
        ConsumeTracker_Data[realmName] = ConsumeTracker_Data[realmName] or {}
        
        -- Auto-select new characters
        ConsumeTracker_Options["Characters"] = ConsumeTracker_Options["Characters"] or {}
        for characterName, charData in pairs(receivedTable) do
            if type(charData) == "table" and characterName ~= "faction" then
                if ConsumeTracker_Options["Characters"][characterName] == nil then
                    ConsumeTracker_Options["Characters"][characterName] = true
                end
            end
        end

        -- Replace character data completely instead of merging
        for characterName, charData in pairs(receivedTable) do
            if type(charData) == "table" then
                -- Create a new table for this character
                ConsumeTracker_Data[realmName][characterName] = {}
                
                -- Copy faction data
                if charData.faction then
                    ConsumeTracker_Data[realmName][characterName].faction = charData.faction
                end
                
                -- Copy inventory data
                if type(charData.inventory) == "table" then
                    ConsumeTracker_Data[realmName][characterName].inventory = {}
                    for itemID, count in pairs(charData.inventory) do
                        ConsumeTracker_Data[realmName][characterName].inventory[itemID] = count
                    end
                end
                
                -- Copy bank data
                if type(charData.bank) == "table" then
                    ConsumeTracker_Data[realmName][characterName].bank = {}
                    for itemID, count in pairs(charData.bank) do
                        ConsumeTracker_Data[realmName][characterName].bank[itemID] = count
                    end
                end
                
                -- Copy mail data
                if type(charData.mail) == "table" then
                    ConsumeTracker_Data[realmName][characterName].mail = {}
                    for itemID, count in pairs(charData.mail) do
                        ConsumeTracker_Data[realmName][characterName].mail[itemID] = count
                    end
                end
            end
        end
        
        ConsumeTracker_UpdateAllContent()
    end

-- BASE64 ENCODE AND DECODE --------------------------------------------------------------------------------------------------

    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local d = {}
    do
        local i = 1
        while i <= string.len(b) do
            local c = string.sub(b, i, i)
            d[c] = i - 1
            i = i + 1
        end
    end

    function EncodeMessage(data)
        local encoded = {}
        local length = string.len(data)
        local i = 1
        while i <= length do
            local c1 = string.byte(data, i, i) i = i + 1
            local c2 = (i <= length) and string.byte(data, i, i) or nil i = i + 1
            local c3 = (i <= length) and string.byte(data, i, i) or nil i = i + 1

            local o1 = bit.rshift(c1, 2)
            local o2 = bit.bor(bit.lshift(bit.band(c1, 3),4), (c2 and bit.rshift(c2, 4) or 0))
            local o3 = (c2 and bit.bor(bit.lshift(bit.band(c2,15),2), (c3 and bit.rshift(c3,6) or 0)) or 64)
            local o4 = (c3 and bit.band(c3,63) or 64)

            table.insert(encoded, string.sub(b, o1+1, o1+1))
            table.insert(encoded, string.sub(b, o2+1, o2+1))
            if o3 ~= 64 then
                table.insert(encoded, string.sub(b, o3+1, o3+1))
            else
                table.insert(encoded, "=")
            end
            if o4 ~= 64 then
                table.insert(encoded, string.sub(b, o4+1, o4+1))
            else
                table.insert(encoded, "=")
            end
        end
        return table.concat(encoded, "")
    end

    function DecodeMessage(str)
        local decoded = {}
        local length = string.len(str)
        local i = 1
        while i <= length do
            local c1 = string.sub(str, i, i) i = i + 1
            local c2 = string.sub(str, i, i) i = i + 1
            if (not c2) or (c1 == '=') or (c2 == '=') then
                break
            end
            local c3 = string.sub(str, i, i) i = i + 1
            local c4 = string.sub(str, i, i) i = i + 1

            local dc1 = d[c1]
            local dc2 = d[c2]
            local dc3 = (c3 and c3 ~= '=' and d[c3]) or nil
            local dc4 = (c4 and c4 ~= '=' and d[c4]) or nil

            local o1 = bit.bor(bit.lshift(dc1, 2), bit.rshift(dc2, 4))
            table.insert(decoded, string.char(o1))

            if dc3 then
                local o2 = bit.bor(bit.lshift(bit.band(dc2, 15),4), bit.rshift(dc3, 2))
                table.insert(decoded, string.char(o2))
                if dc4 then
                    local o3 = bit.bor(bit.lshift(bit.band(dc3, 3),6), dc4)
                    table.insert(decoded, string.char(o3))
                end
            end
        end
        return table.concat(decoded, "")
    end


-- Action Bar ---------------------------------------------------------------------------------------


function ConsumeTracker_RestoreActionBarPosition()
    if not ConsumeTracker_ActionBar then return end
    
    local point = ConsumeTracker_GetCharacterSetting("ActionBarPoint")
    local relativeTo = ConsumeTracker_GetCharacterSetting("ActionBarRelativeTo")
    local relativePoint = ConsumeTracker_GetCharacterSetting("ActionBarRelativePoint")
    local xOfs = ConsumeTracker_GetCharacterSetting("ActionBarXOfs")
    local yOfs = ConsumeTracker_GetCharacterSetting("ActionBarYOfs")
    
    ConsumeTracker_ActionBar:ClearAllPoints()
    if point and xOfs and yOfs then
        ConsumeTracker_ActionBar:SetPoint(point, UIParent, relativePoint or point, xOfs, yOfs)
    else
        -- Default position
        ConsumeTracker_ActionBar:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
end

function ConsumeTracker_SaveActionBarPosition()
    if not ConsumeTracker_ActionBar then return end
    
    local point, relativeTo, relativePoint, xOfs, yOfs = ConsumeTracker_ActionBar:GetPoint()
    ConsumeTracker_SetCharacterSetting("ActionBarPoint", point)
    ConsumeTracker_SetCharacterSetting("ActionBarRelativePoint", relativePoint)
    ConsumeTracker_SetCharacterSetting("ActionBarXOfs", xOfs)
    ConsumeTracker_SetCharacterSetting("ActionBarYOfs", yOfs)
end

function ConsumeTracker_CreateActionBar()
    if ConsumeTracker_ActionBar then return end

    local actionBar = CreateFrame("Frame", "ConsumeTracker_ActionBar", UIParent)
    actionBar:SetWidth(40)
    actionBar:SetHeight(40)
    
    -- Position will be set via RestoreActionBarPosition shortly
    
    actionBar:SetMovable(true)
    actionBar:EnableMouse(true)
    actionBar:SetClampedToScreen(true)
    
    -- Dragging Logic
    actionBar:SetScript("OnMouseDown", function()
        if IsShiftKeyDown() and arg1 == "LeftButton" then
            this:StartMoving()
            this.isMoving = true
        end
    end)
    actionBar:SetScript("OnMouseUp", function()
        if this.isMoving then
            this:StopMovingOrSizing()
            this.isMoving = false
            ConsumeTracker_SaveActionBarPosition()
        end
    end)
    actionBar:SetScript("OnHide", function()
        if this.isMoving then
            this:StopMovingOrSizing()
            this.isMoving = false
            ConsumeTracker_SaveActionBarPosition()
        end
    end)

    ConsumeTracker_ActionBar = actionBar
    ConsumeTracker_ActionBar.buttons = {}
    
    ConsumeTracker_RestoreActionBarPosition()
end

function ConsumeTracker_UpdateActionBar()
    if not ConsumeTracker_ActionBar then
        ConsumeTracker_CreateActionBar()
    end
    
    local showActionBar = ConsumeTracker_Options.showActionBar
    if showActionBar == nil then showActionBar = false end
    ConsumeTracker_Options.showActionBar = (ConsumeTracker_Options.showActionBar == nil) and true or ConsumeTracker_Options.showActionBar
    showActionBar = ConsumeTracker_Options.showActionBar

    if not showActionBar then
        ConsumeTracker_ActionBar:Hide()
        return
    end

    local items = {}
    -- Collect selected items
    for itemID, isSelected in pairs(ConsumeTracker_SelectedItems) do
        if isSelected and consumablesList[itemID] then
            table.insert(items, itemID)
        end
    end
    
    table.sort(items, function(a, b) 
        local nameA = consumablesList[a] or ""
        local nameB = consumablesList[b] or ""
        return nameA < nameB
    end)

    if table.getn(items) == 0 then
        ConsumeTracker_ActionBar:Hide()
        return
    end

    ConsumeTracker_ActionBar:Show()

    local btnSize = 36
    local spacing = 4
    local totalWidth = (btnSize + spacing) * table.getn(items) - spacing
    ConsumeTracker_ActionBar:SetWidth(totalWidth)
    ConsumeTracker_ActionBar:SetHeight(btnSize)
    
    -- unique scale logic
    local scale = ConsumeTracker_GetCharacterSetting("actionBarScale") or ConsumeTracker_Options.actionBarScale or 1
    ConsumeTracker_ActionBar:SetScale(scale)

    -- Hide old buttons
    for _, btn in ipairs(ConsumeTracker_ActionBar.buttons) do
        btn:Hide()
    end

    local realmName = GetRealmName()
    local playerName = UnitName("player")
    
    -- Ensure data is initialized
    if not ConsumeTracker_Data[realmName] then ConsumeTracker_Data[realmName] = {} end
    if not ConsumeTracker_Data[realmName][playerName] then ConsumeTracker_Data[realmName][playerName] = {} end
    if not ConsumeTracker_Data[realmName][playerName].inventory then ConsumeTracker_Data[realmName][playerName].inventory = {} end

    local playerInventory = ConsumeTracker_Data[realmName][playerName].inventory

    -- Lazy scan if inventory seems empty but bags might be loaded
    if (not playerInventory or next(playerInventory) == nil) and GetContainerNumSlots(0) > 0 then
         ConsumeTracker_ScanPlayerInventory()
         playerInventory = ConsumeTracker_Data[realmName][playerName].inventory
    end

    for i, itemID in ipairs(items) do
        local btn = ConsumeTracker_ActionBar.buttons[i]
        if not btn then
            btn = CreateFrame("Button", "ConsumeTracker_ActionBarButton"..i, ConsumeTracker_ActionBar, "ActionButtonTemplate")
            btn:SetWidth(btnSize)
            btn:SetHeight(btnSize)
            btn:RegisterForDrag("LeftButton")
            ConsumeTracker_ActionBar.buttons[i] = btn
        end

        btn:ClearAllPoints()
        btn:SetPoint("LEFT", ConsumeTracker_ActionBar, "LEFT", (i-1)*(btnSize+spacing), 0)
        btn:Show()

        local texture = consumablesTexture[itemID] or "Interface\\Icons\\INV_Misc_QuestionMark"
        local icon = getglobal(btn:GetName().."Icon")
        if icon then icon:SetTexture(texture) end

        -- Count
        local count = playerInventory[itemID] or 0
        local countText = getglobal(btn:GetName().."Count")
        if countText then 
             if count > 0 then
                 countText:SetText(count)
                 countText:SetTextColor(0, 1, 0) -- Green
                 icon:SetVertexColor(1.0, 1.0, 1.0) -- Normal
             else
                 countText:SetText("0")
                 countText:SetTextColor(1, 0, 0) -- Red
                 icon:SetVertexColor(0.4, 0.4, 0.4) -- Gray/Darkened
             end
        end

        local thisItemID = itemID
        
        local buffName = consumablesBuffs and consumablesBuffs[itemID]
        local buffType = consumablesBuffTypes and consumablesBuffTypes[itemID]
        local buffId = consumablesBuffIds and consumablesBuffIds[itemID]
        
        -- Checkmark / Timer Logic
        local checkmark = getglobal(btn:GetName().."Checkmark")
        if not checkmark then
            checkmark = btn:CreateTexture(btn:GetName().."Checkmark", "OVERLAY")
            checkmark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            checkmark:SetPoint("CENTER", btn, "CENTER", 0, 0)
            checkmark:SetWidth(26)
            checkmark:SetHeight(26)
        end
        checkmark:Hide() -- Always hide checkmark now, user wants timer

        local timerText = getglobal(btn:GetName().."Timer")
        if not timerText then
            timerText = btn:CreateFontString(btn:GetName().."Timer", "OVERLAY", "GameFontNormalLarge") -- Larger font
            timerText:SetPoint("CENTER", btn, "CENTER", 0, 0)
            timerText:SetTextColor(1, 1, 0) -- Yellow
        end
        
        -- Store buff info on button for the OnUpdate script
        btn.buffName = buffName
        btn.buffType = buffType
        btn.buffId = buffId
        btn.timerText = timerText

        -- Initial Update
        local isActive, timeLeft = ConsumeTracker_IsBuffActive(buffName, buffType, buffId)
        if buffName and isActive then
            timerText:Show()
            if timeLeft then
                if timeLeft >= 3600 then
                    timerText:SetText(math.floor((timeLeft / 3600) + 0.5) .. "h")
                elseif timeLeft >= 60 then
                    timerText:SetText(math.floor((timeLeft / 60) + 0.5) .. "m")
                else
                    timerText:SetText(math.floor(timeLeft + 0.5) .. "s")
                end
            else
                timerText:SetText("") -- Active but no time
            end
        else
            timerText:Hide()
        end

        -- OnClick
        btn:SetScript("OnClick", function()
             local bag, slot = ConsumeTracker_FindItemInBags(thisItemID)
             if bag and slot then
                 UseContainerItem(bag, slot)
             else
                 -- do nothing
             end
        end)

        -- Dragging
        btn:SetScript("OnDragStart", function()
            if IsShiftKeyDown() then
                ConsumeTracker_ActionBar:StartMoving()
                ConsumeTracker_ActionBar.isMoving = true
            end
        end)
        btn:SetScript("OnDragStop", function()
            ConsumeTracker_ActionBar:StopMovingOrSizing()
            ConsumeTracker_ActionBar.isMoving = false
            ConsumeTracker_SaveActionBarPosition()
        end)
        
        -- Tooltip
        btn:SetScript("OnEnter", function()
            ConsumeTracker_ShowItemsTooltip(thisItemID, this)
        end)
        btn:SetScript("OnLeave", function()
             if ConsumeTracker_ItemsTooltip then
                ConsumeTracker_ItemsTooltip:Hide()
             end
        end)
        
        -- Per-Button Update Script for Timer
        btn:SetScript("OnUpdate", function()
            -- Throttle updates to ~0.2s
            if (this.updateTimer or 0) > GetTime() then return end
            this.updateTimer = GetTime() + 0.2
            
            if this.buffName then
                local active, time = ConsumeTracker_IsBuffActive(this.buffName, this.buffType, this.buffId)
                if active then
                    this.timerText:Show()
                    if time then
                        if time >= 3600 then
                            this.timerText:SetText(math.floor((time / 3600) + 0.5) .. "h")
                        elseif time >= 60 then
                            this.timerText:SetText(math.floor((time / 60) + 0.5) .. "m")
                        else
                            this.timerText:SetText(math.ceil(time) .. "s")
                        end
                    else
                         this.timerText:SetText("") 
                    end
                else
                    this.timerText:Hide()
                end
            else
                this.timerText:Hide()
            end
        end)
    end
end
