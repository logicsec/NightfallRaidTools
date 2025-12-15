-- Raid Inspect Module
ConsumeTracker = ConsumeTracker or {}
ConsumeTracker.Modules = ConsumeTracker.Modules or {}
ConsumeTracker.Modules["RaidInspect"] = {}
local Module = ConsumeTracker.Modules["RaidInspect"]

Module.Label = "Raid Inspect"
Module.Icon = "Interface\\Icons\\INV_Misc_Spyglass_03"

-- Reference icon mappings from IconMappings.lua (with defensive fallback)
RaidInspect_Icons = RaidInspect_Icons or {}
Module.classColors = RaidInspect_Icons.classColors or {}
Module.raceIcons = RaidInspect_Icons.raceIcons or {}
Module.classIcons = RaidInspect_Icons.classIcons or {}
Module.specIcons = RaidInspect_Icons.specIcons or {}

-- Storage for raid member rows
Module.raidRows = {}

-- Inspection System
Module.inspectCache = {}      -- { [unitName] = { [slotId] = texture/link, ... } }
Module.inspectQueue = {}      -- { unitId, unitId, ... }
Module.lastInspectTime = 0
Module.INSPECT_INTERVAL = 0.2 -- Faster inspections (5 per sec)
Module.isInspectRunning = false

-- Create hidden tooltip for scanning enchant names
local scanTooltip = CreateFrame("GameTooltip", "RaidInspect_ScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
Module.scanTooltip = scanTooltip

-- Extract enchant name from item link via tooltip scanning
function Module:GetEnchantFromLink(link)
    if not link then return nil end
    
    -- Parse the item string to check for enchant ID
    local _, _, itemString = string.find(link, "^|c%x+|H(.+)|h%[.*%]")
    if not itemString then return nil end
    
    -- itemString format: item:itemID:enchantID:suffixID:uniqueID
    local _, _, enchantId = string.find(itemString, "item:%d+:(%d+)")
    if not enchantId or enchantId == "0" then return nil end
    
    -- Use tooltip scanning to get enchant name
    self.scanTooltip:ClearLines()
    self.scanTooltip:SetHyperlink(itemString)
    
    -- Scan tooltip lines for green text (enchant lines are typically green)
    for i = 2, self.scanTooltip:NumLines() do
        local line = getglobal("RaidInspect_ScanTooltipTextLeft" .. i)
        if line then
            local r, g, b = line:GetTextColor()
            local text = line:GetText()
            -- Green text (enchants) have high g value and low r/b values
            if text and g > 0.9 and r < 0.2 and b < 0.2 then
                return text
            end
        end
    end
    
    return nil
end

function Module:OnInitialize()
    -- Create update frame for inspection queue
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame:Hide()
    self.updateFrame:SetScript("OnUpdate", function() self:OnUpdate(arg1) end)
    
    -- Register for inspection events
    self.eventFrame = CreateFrame("Frame")
    self.eventFrame:SetScript("OnEvent", function() self:OnInspectionEvent() end)
end

function Module:OnEnable(contentFrame)
    -- Called when this module is selected
    if not self.isBuilt then
        self:BuildUI(contentFrame)
        self.isBuilt = true
    end
    
    -- Register events
    self.eventFrame:RegisterEvent("INSPECT_TALENT_READY") -- Turtle/Vanilla+
    self.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    self.eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    
    -- Start queue processor
    self.updateFrame:Show()
    
    -- Reset expanded state and hide back button when module is shown
    if self.backButton then
        self.backButton:Hide()
    end
    
    -- Refresh raid data when module is shown
    self:RefreshRaidData()
    
    if contentFrame.headerBg then contentFrame.headerBg:Show() end
end

function Module:OnDisable(contentFrame)
    -- Stop queue processor
    self.updateFrame:Hide()
    self.eventFrame:UnregisterAllEvents()
end


-- ===========================================
-- INSPECTION QUEUE LOGIC
-- ===========================================




-- ===========================================
-- INSPECTION QUEUE LOGIC
-- ===========================================

function Module:QueueInspect(unitId)
    -- Avoid duplicates
    for _, unit in ipairs(self.inspectQueue) do
        if unit == unitId then return end
    end
    table.insert(self.inspectQueue, unitId)
end

function Module:OnUpdate(elapsed)
    -- Process queue
    if table.getn(self.inspectQueue) == 0 then return end
    
    local now = GetTime()
    if (now - self.lastInspectTime) < self.INSPECT_INTERVAL then return end
    
    -- Pop next unit
    local unitId = table.remove(self.inspectQueue, 1)
    
    -- Verify unit exists and is in range
    if UnitExists(unitId) and UnitIsVisible(unitId) and CheckInteractDistance(unitId, 1) then
        self.currentInspectUnit = unitId
        NotifyInspect(unitId)
        self.lastInspectTime = now
    else
        -- Re-queue if not visible? Or just skip? Skip for now to avoid stuck queue
    end
end

function Module:OnInspectionEvent()
    if event == "GET_ITEM_INFO_RECEIVED" then
        self:RefreshRaidData()
        return
    end

    if event == "INSPECT_TALENT_READY" or event == "UNIT_INVENTORY_CHANGED" then
        if not self.currentInspectUnit then return end
        
        local unitId = self.currentInspectUnit
        local unitName = UnitName(unitId)
        if not unitName then return end
        
        -- Initialize cache entry
        if not self.inspectCache[unitName] then
            self.inspectCache[unitName] = {
                gear = {},
                ilvl = 0
            }
        end
        
        -- Scrape Gear
        local gearData = self.inspectCache[unitName].gear
        local links = self.inspectCache[unitName].links or {}
        self.inspectCache[unitName].links = links
        
        for slot = 1, 19 do -- 1-19 covers all visible slots
            local texture = GetInventoryItemTexture(unitId, slot)
            if texture then
                gearData[slot] = texture
                links[slot] = GetInventoryItemLink(unitId, slot)
            end
        end
        
        -- Update UI if this unit is visible
        self:RefreshRowForUnit(unitName)
        
        -- Clear current unit to be safe
        
        -- Clear current unit to be safe
        if event == "INSPECT_TALENT_READY" then
            self.currentInspectUnit = nil
        end
    end
end

function Module:RefreshRowForUnit(unitName)
    -- Find the row for this unit and update gear icons
    for _, row in ipairs(self.raidRows) do
        if row.unitName == unitName then
            self:UpdateRowGear(row, unitName)
            break
        end
    end
end

function Module:UpdateRowGear(row, unitName)
    local data = self.inspectCache[unitName]
    if not data or not data.gear then return end
    
    -- Slots 1-19 map to standard inventory slots
    -- We want to display specific slots, e.g., Head(1), Neck(2), Shoulder(3), Shirt(4), Chest(5), Waist(6), Legs(7), Feet(8), Wrist(9), Hands(10), Ring1(11), Ring2(12), Trinket1(13), Trinket2(14), Back(15), MainHand(16), OffHand(17), Ranged(18), Tabard(19)
    -- Let's display primary gear slots in order
    local displaySlots = {1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18} 
    
    -- Update Horizontal Scroll View (Collapsed)
    for i, slotId in ipairs(displaySlots) do
        local btn = row.gearIcons[i]
        if btn then
            local texture = data.gear[slotId]
            local link = data.links and data.links[slotId]
            
            local icon = btn.icon or btn:GetNormalTexture()
            if texture then
                icon:SetTexture(texture)
                icon:SetAlpha(1.0)
                btn.link = link -- Store link on button
                
                -- Rarity Border Update
                if link and btn.border then
                    local _, _, quality = GetItemInfo(link)
                    if quality and quality >= 2 then -- Green or better
                        local r, g, b = GetItemQualityColor(quality)
                        btn.border:SetVertexColor(r, g, b)
                        btn.border:Show()
                    else
                        btn.border:Hide()
                    end
                elseif btn.border then
                     btn.border:Hide()
                end
            else
                icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                icon:SetAlpha(0.2)
                btn.link = nil
                if btn.border then btn.border:Hide() end
            end
        end
    end
    
    -- Update Detail View (Expanded)
    if row.detailButtons then
        for slot, btn in pairs(row.detailButtons) do
            local texture = data.gear[slot]
            local link = data.links and data.links[slot]
            
            local icon = btn.icon
            if texture then
                icon:SetTexture(texture)
                icon:SetAlpha(1.0)
                btn.link = link
                
                -- Update Item Name
                if btn.itemName then
                    local name = GetItemInfo(link)
                    if name then
                        local _, _, quality = GetItemInfo(link)
                        local r, g, b = GetItemQualityColor(quality or 1)
                        btn.itemName:SetText(name)
                        btn.itemName:SetTextColor(r, g, b)
                    else
                        -- Fallback: Parse name and color from link
                        local _, _, nameColor = string.find(link, "|c(%x+)|H")
                        local _, _, fallbackName = string.find(link, "%[(.-)%]")
                        
                        if fallbackName then
                             btn.itemName:SetText(fallbackName)
                             if nameColor and string.len(nameColor) == 8 then
                                 local r = tonumber(string.sub(nameColor, 3, 4), 16) or 255
                                 local g = tonumber(string.sub(nameColor, 5, 6), 16) or 255
                                 local b = tonumber(string.sub(nameColor, 7, 8), 16) or 255
                                 btn.itemName:SetTextColor(r/255, g/255, b/255)
                             else
                                 btn.itemName:SetTextColor(1, 1, 1)
                             end
                        else
                             btn.itemName:SetText("Loading...")
                             btn.itemName:SetTextColor(0.7, 0.7, 0.7)
                        end
                    end
                end
                
                -- Update Enchant Text
                if btn.enchantText then
                    local enchantName = self:GetEnchantFromLink(link)
                    if enchantName then
                        btn.enchantText:SetText(enchantName)
                    else
                        btn.enchantText:SetText("")
                    end
                end
                
                -- Rarity Border Update
                if link and btn.border then
                    local _, _, quality = GetItemInfo(link)
                    if quality and quality >= 2 then
                        local r, g, b = GetItemQualityColor(quality)
                        btn.border:SetVertexColor(r, g, b)
                        btn.border:Show()
                    else
                         btn.border:Hide()
                    end
                elseif btn.border then
                    btn.border:Hide()
                end
            else
                icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                icon:SetAlpha(0.2)
                btn.link = nil
                if btn.itemName then btn.itemName:SetText("") end
                if btn.enchantText then btn.enchantText:SetText("") end
                if btn.border then btn.border:Hide() end
            end
        end
    end
end

function Module:BuildUI(parent)
    local moduleContent = parent

    -- Module Header Background
    local headerBg = moduleContent:CreateTexture(nil, "BACKGROUND")
    headerBg:SetTexture(0.15, 0.15, 0.15, 0.8)
    headerBg:SetPoint("TOPLEFT", moduleContent, "TOPLEFT", 0, -35)
    headerBg:SetPoint("TOPRIGHT", moduleContent, "TOPRIGHT", 0, 0)
    headerBg:SetHeight(34)
    moduleContent.headerBg = headerBg

    -- Module Header Title
    local moduleTitle = moduleContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    moduleTitle:SetText("Raid Inspect")
    moduleTitle:SetPoint("TOPLEFT", moduleContent, "TOPLEFT", 10, -10)
    moduleTitle:SetTextColor(1, 0.82, 0)

    -- Back Button (Top Right) - Custom Gold Theme
    local backButton = CreateFrame("Button", "RaidInspect_BackButton", moduleContent)
    backButton:SetWidth(80)
    backButton:SetHeight(22)
    backButton:SetPoint("TOPRIGHT", moduleContent, "TOPRIGHT", -10, -42)
    backButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    backButton:SetBackdropColor(0, 0, 0, 0) -- Transparent background
    backButton:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold border
    
    local btnText = backButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER", backButton, "CENTER", 0, 0)
    btnText:SetText("Go Back")
    btnText:SetTextColor(1, 0.82, 0) -- Gold text
    backButton.text = btnText
    
    backButton:Hide()
    self.backButton = backButton
    
    backButton:SetScript("OnClick", function()
        -- Collapse all
        for _, r in ipairs(Module.raidRows) do
            r.isExpanded = false
        end
        Module:RebuildRowLayout()
        this:Hide()
        
        -- Reset scroll
        local scrollFrame = Module.equipmentScrollChild:GetParent()
        scrollFrame:SetVerticalScroll(0)
    end)

    -- Helper: Create Sub Tab
    local function CreateSubTab(tabParent, id, text, xOffset)
        local tab = CreateFrame("Button", "RaidInspect_SubTab_" .. id, tabParent)
        tab:SetWidth(100)
        tab:SetHeight(24)
        tab:SetPoint("TOPLEFT", tabParent, "TOPLEFT", xOffset, -40)

        -- Text
        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tabText:SetText(text)
        tabText:SetTextColor(0.6, 0.6, 0.6) -- Default Gray
        tab.text = tabText

        local activeLine = tab:CreateTexture(nil, "OVERLAY")
        activeLine:SetHeight(2)
        activeLine:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        activeLine:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        activeLine:Hide()
        tab.activeLine = activeLine

        return tab
    end

    -- Create Sub Tabs
    local subTabs = {}
    subTabs[1] = CreateSubTab(moduleContent, 1, "Equipment", 10)
    subTabs[2] = CreateSubTab(moduleContent, 2, "Talents", 115)
    moduleContent.subTabs = subTabs

    -- Tab Content Frames
    moduleContent.tabFrames = {}
    
    local contentWidth = 750 
    local contentHeight = 550
    local contentX = 0
    local contentY = -70

    local function CreateTabFrame(id)
        local f = CreateFrame("Frame", nil, moduleContent)
        local f = CreateFrame("Frame", nil, moduleContent)
        -- Dynamic Size: Anchor to TOPLEFT and BOTTOMRIGHT
        f:SetPoint("TOPLEFT", moduleContent, "TOPLEFT", contentX, contentY)
        f:SetPoint("BOTTOMRIGHT", moduleContent, "BOTTOMRIGHT", 0, 10)
        f:Hide()
        moduleContent.tabFrames[id] = f
        return f
    end

    local equipmentFrame = CreateTabFrame(1)
    local talentsFrame = CreateTabFrame(2)

    -- Tab switching logic
    local function ShowSubTab(tabId)
        for i, tab in ipairs(subTabs) do
            if i == tabId then
                tab.text:SetTextColor(1, 0.82, 0)
                tab.activeLine:Show()
                moduleContent.tabFrames[i]:Show()
            else
                tab.text:SetTextColor(0.6, 0.6, 0.6)
                tab.activeLine:Hide()
                moduleContent.tabFrames[i]:Hide()
            end
        end
    end

    subTabs[1]:SetScript("OnClick", function() ShowSubTab(1) end)
    subTabs[2]:SetScript("OnClick", function() ShowSubTab(2) end)

    -- Build Equipment Tab
    self:BuildEquipmentContent(equipmentFrame)
    
    -- Build Talents Tab
    self:BuildTalentsContent(talentsFrame)

    -- Show Equipment tab by default
    ShowSubTab(1)
end

function Module:BuildEquipmentContent(parent)
    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "RaidInspect_EquipScrollFrame", parent)
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
        local delta = arg1
        local current = this:GetVerticalScroll()
        local maxScroll = this.maxScroll or 0
        local newScroll = math.max(0, math.min(current - (delta * 30), maxScroll))
        this:SetVerticalScroll(newScroll)
    end)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Auto-resize scroll child width
    scrollFrame:SetScript("OnSizeChanged", function()
        if this.scrollChild then
            this.scrollChild:SetWidth(this:GetWidth())
        end
    end)
    
    parent.scrollFrame = scrollFrame
    parent.scrollChild = scrollChild
    self.equipmentScrollChild = scrollChild
    scrollFrame.scrollChild = scrollChild -- Link for script access

    -- "Not in Raid" message
    local notInRaidText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    notInRaidText:SetPoint("CENTER", parent, "CENTER", 0, 0)
    notInRaidText:SetText("Not in a raid group\n\nJoin a raid to see members")
    notInRaidText:SetTextColor(0.5, 0.5, 0.5)
    notInRaidText:Hide()
    self.notInRaidText = notInRaidText
end

function Module:GetRaidMembers()
    local members = {}
    local numRaid = GetNumRaidMembers()
    
    if numRaid == 0 then
        return members
    end
    
    for i = 1, numRaid do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
        
        if name then
            local unitId = "raid" .. i
            local race = UnitRace(unitId)
            local guildName = GetGuildInfo(unitId) or ""
            local sex = UnitSex(unitId) -- 1=unknown, 2=male, 3=female
            local gender = "Male"
            if sex == 3 then gender = "Female" end
            
            table.insert(members, {
                name = name,
                guild = guildName,
                class = fileName or "WARRIOR", -- fileName is the uppercase class token
                race = race or "Unknown",
                gender = gender,
                level = level or 60,
                online = online,
                unitId = unitId,
            })
        end
    end
    
    -- Sort by class for organization
    table.sort(members, function(a, b)
        if a.class == b.class then
            return a.name < b.name
        end
        return a.class < b.class
    end)
    
    return members
end

function Module:RefreshRaidData()
    if not self.equipmentScrollChild then return end
    
    local scrollChild = self.equipmentScrollChild
    
    -- Clear existing rows
    for _, row in ipairs(self.raidRows) do
        row:Hide()
    end
    self.raidRows = {}
    
    local members = self:GetRaidMembers()
    
    if table.getn(members) == 0 then
        self.notInRaidText:Show()
        scrollChild:SetHeight(1)
        return
    end
    
    self.notInRaidText:Hide()
    
    -- Calculate dynamic widths
    local scrollFrame = scrollChild:GetParent()
    local frameWidth = 780
    
    -- Subtract scrollbar spacing if needed (usually ~20px)
    local rowWidth = frameWidth 
    
    local rowHeight = 36
    local gearSlots = 16
    local gearIconSize = 20
    local gearSpacing = 2
    
    for i, player in ipairs(members) do
        local row = CreateFrame("Button", nil, scrollChild)
        row:SetWidth(rowWidth)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0) -- Position set by RebuildRowLayout
        
        -- Click to expand (Accordion style with auto-scroll)
        row:SetScript("OnClick", function()
            local wasExpanded = this.isExpanded
            
            -- Collapse all others
            for _, r in ipairs(Module.raidRows) do
                r.isExpanded = false
            end
            
            -- Toggle this one
            this.isExpanded = not wasExpanded
            
            Module:RebuildRowLayout()
            
            -- Scroll Logic
            local scrollFrame = Module.equipmentScrollChild:GetParent()
            local index = 0
            for idx, r in ipairs(Module.raidRows) do
                 if r == this then index = idx break end
            end
            
            if this.isExpanded then
                -- In "Filter Mode", row is at (0,0). Scroll to top.
                scrollFrame:SetVerticalScroll(0)
                Module.backButton:Show()
            else
                -- Collapsing: Return to this row's position in the full list
                local newScroll = (index - 1) * 36
                local maxScroll = scrollFrame.maxScroll or 0 
                scrollFrame:SetVerticalScroll(newScroll)
                Module.backButton:Hide()
            end
            scrollFrame:UpdateScrollChildRect()
        end)

        -- Detail Frame (Expanded View) - PaperDoll Layout
        local detailFrame = CreateFrame("Frame", nil, row)
        detailFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -rowHeight)
        detailFrame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        detailFrame:Hide()
        row.detailFrame = detailFrame
        
        -- CENTERED HEADER for Expanded View (centered on 600px effectiveWidth)
        local headerCenterX = 300 -- Center of the 600px paper doll layout
        
        local detailName = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        detailName:SetPoint("TOP", detailFrame, "TOPLEFT", headerCenterX, 15)
        detailName:SetText(player.name)
        detailName:SetTextColor(1, 1, 1) -- White
        
        local detailSub = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detailSub:SetPoint("TOP", detailName, "BOTTOM", 0, -4)
        
        -- Build subtitle: "Guild | Level Class"
        local subString = ""
        if player.guild and player.guild ~= "" then
            subString = "|cffa0a0a0" .. player.guild .. "|r  |  "
        end
        subString = subString .. "|cffffd100" .. player.level .. "|r "
        
        local cColor = self.classColors[player.class] or {1, 1, 1}
        local r = math.ceil(cColor[1]*255)
        local g = math.ceil(cColor[2]*255)
        local b = math.ceil(cColor[3]*255)
        local hex = string.format("ff%02x%02x%02x", r, g, b)
        subString = subString .. "|c" .. hex .. (player.class or "") .. "|r"
        
        detailSub:SetText(subString)
        
        -- Navigation Buttons (Back / Forward)
        local navBtnWidth = 30
        local navBtnHeight = 22
        
        local backNavBtn = CreateFrame("Button", nil, detailFrame)
        backNavBtn:SetWidth(navBtnWidth)
        backNavBtn:SetHeight(navBtnHeight)
        backNavBtn:SetPoint("TOP", detailFrame, "TOPLEFT", headerCenterX - 100, 18)
        backNavBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        backNavBtn:SetBackdropColor(0, 0, 0, 0)
        backNavBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
        local backNavText = backNavBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        backNavText:SetPoint("CENTER", backNavBtn, "CENTER", 0, 0)
        backNavText:SetText("<")
        backNavText:SetTextColor(1, 0.82, 0)
        backNavBtn.text = backNavText
        row.backNavBtn = backNavBtn
        
        local forwardNavBtn = CreateFrame("Button", nil, detailFrame)
        forwardNavBtn:SetWidth(navBtnWidth)
        forwardNavBtn:SetHeight(navBtnHeight)
        forwardNavBtn:SetPoint("TOP", detailFrame, "TOPLEFT", headerCenterX + 100, 18)
        forwardNavBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        forwardNavBtn:SetBackdropColor(0, 0, 0, 0)
        forwardNavBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
        local forwardNavText = forwardNavBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        forwardNavText:SetPoint("CENTER", forwardNavBtn, "CENTER", 0, 0)
        forwardNavText:SetText(">")
        forwardNavText:SetTextColor(1, 0.82, 0)
        forwardNavBtn.text = forwardNavText
        row.forwardNavBtn = forwardNavBtn
        
        -- Navigation button click handlers
        backNavBtn:SetScript("OnClick", function()
            Module:NavigateToPlayer(-1)
        end)
        forwardNavBtn:SetScript("OnClick", function()
            Module:NavigateToPlayer(1)
        end)
        
        -- "Not Scanned" text (hidden by default)
        local notScannedText = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        notScannedText:SetPoint("CENTER", detailFrame, "LEFT", headerCenterX, 0)
        notScannedText:SetText("Not Scanned")
        notScannedText:SetTextColor(0.5, 0.5, 0.5)
        notScannedText:Hide()
        row.notScannedText = notScannedText
        
        -- PaperDoll Slot Definitions (x, y offsets relative to center)
        -- Standard Inspect: 3 cols. Left (gear), Center (model/stats), Right (gear), Bottom (weapons)
        local slotSize = 37
        local slotSpace = 4
        
        -- DYNAMIC LAYOUT CALCULATIONS
        local effectiveWidth = 600
        local leftX = 70 -- Fixed left margin for labels
        local rightX = effectiveWidth - 70 - slotSize -- Mirrored right margin
        local centerX = effectiveWidth / 2
        
        local effectiveWidth = 600
        local leftX = 70 
        local rightX = effectiveWidth - 70 - slotSize 
        local centerX = effectiveWidth / 2
        
        local startY = -30 -- Moved up to give bottom room
        
        -- Map inventory slots to UI positions
        local paperDollLayout = {
            {slot=1, x=leftX, y=startY, side="LEFT", name="Head"}, 
            {slot=2, x=leftX, y=startY - (slotSize+slotSpace)*1, side="LEFT", name="Neck"}, 
            {slot=3, x=leftX, y=startY - (slotSize+slotSpace)*2, side="LEFT", name="Shoulder"}, 
            {slot=15, x=leftX, y=startY - (slotSize+slotSpace)*3, side="LEFT", name="Back"}, 
            {slot=5, x=leftX, y=startY - (slotSize+slotSpace)*4, side="LEFT", name="Chest"}, 
            {slot=4, x=leftX, y=startY - (slotSize+slotSpace)*5, side="LEFT", name="Shirt"}, 
            {slot=19, x=leftX, y=startY - (slotSize+slotSpace)*6, side="LEFT", name="Tabard"}, 
            {slot=9, x=leftX, y=startY - (slotSize+slotSpace)*7, side="LEFT", name="Wrist"}, 
            
            {slot=10, x=rightX, y=startY, side="RIGHT", name="Hands"}, 
            {slot=6, x=rightX, y=startY - (slotSize+slotSpace)*1, side="RIGHT", name="Waist"}, 
            {slot=7, x=rightX, y=startY - (slotSize+slotSpace)*2, side="RIGHT", name="Legs"}, 
            {slot=8, x=rightX, y=startY - (slotSize+slotSpace)*3, side="RIGHT", name="Feet"}, 
            {slot=11, x=rightX, y=startY - (slotSize+slotSpace)*4, side="RIGHT", name="Ring 1"}, 
            {slot=12, x=rightX, y=startY - (slotSize+slotSpace)*5, side="RIGHT", name="Ring 2"}, 
            {slot=13, x=rightX, y=startY - (slotSize+slotSpace)*6, side="RIGHT", name="Trinket 1"}, 
            {slot=14, x=rightX, y=startY - (slotSize+slotSpace)*7, side="RIGHT", name="Trinket 2"}, 
            
            {slot=16, x=centerX - 150, y=-400, side="BOTTOM", name="Main Hand"}, 
            {slot=17, x=centerX, y=-400, side="BOTTOM", name="Off Hand"}, 
            {slot=18, x=centerX + 150, y=-400, side="BOTTOM", name="Ranged"}, 
        }
        
        row.detailButtons = {}
        
        for _, pos in ipairs(paperDollLayout) do
            local btn = CreateFrame("Button", nil, detailFrame)
            btn:SetWidth(slotSize)
            btn:SetHeight(slotSize)
            btn:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", pos.x, pos.y)
            
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(btn)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetAlpha(0.3)
            btn.icon = icon
            
            -- Rarity Border
            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetPoint("CENTER", btn, "CENTER", 0, 0)
            border:SetWidth(slotSize * 1.7)
            border:SetHeight(slotSize * 1.7)
            border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            border:SetBlendMode("ADD")
            border:Hide()
            btn.border = border

            -- Slot Name (Outside)
            local slotName = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            if pos.side == "LEFT" then
                slotName:SetPoint("RIGHT", btn, "LEFT", -5, 0)
                slotName:SetJustifyH("RIGHT")
            elseif pos.side == "RIGHT" then
                slotName:SetPoint("LEFT", btn, "RIGHT", 5, 0)
                slotName:SetJustifyH("LEFT")
            else
                slotName:SetPoint("TOP", btn, "BOTTOM", 0, -5)
            end
            slotName:SetText(pos.name)
            slotName:SetTextColor(0.7, 0.7, 0.7)

            -- Item Name (Inside)
            local itemName = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            if pos.side == "LEFT" then
                itemName:SetPoint("TOPLEFT", btn, "TOPRIGHT", 5, 0)
                itemName:SetJustifyH("LEFT")
                itemName:SetWidth(240)
            elseif pos.side == "RIGHT" then
                itemName:SetPoint("TOPRIGHT", btn, "TOPLEFT", -5, 0)
                itemName:SetJustifyH("RIGHT")
                itemName:SetWidth(240)
            else
                -- Bottom Row: Text ABOVE icon
                itemName:SetPoint("BOTTOM", btn, "TOP", 0, 16)
                itemName:SetWidth(150)
            end
            itemName:SetText("")
            btn.itemName = itemName
            
            -- Enchant Text (Below Item Name)
            local enchantText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            if pos.side == "LEFT" then
                enchantText:SetPoint("TOPLEFT", itemName, "BOTTOMLEFT", 0, -2)
                enchantText:SetJustifyH("LEFT")
                enchantText:SetWidth(240)
            elseif pos.side == "RIGHT" then
                enchantText:SetPoint("TOPRIGHT", itemName, "BOTTOMRIGHT", 0, -2)
                enchantText:SetJustifyH("RIGHT")
                enchantText:SetWidth(240)
            else
                -- Bottom Row: Enchant below item name (above icon)
                enchantText:SetPoint("TOP", itemName, "BOTTOM", 0, -2)
                enchantText:SetWidth(150)
            end
            enchantText:SetText("")
            enchantText:SetTextColor(0.1, 1, 0.1) -- Green for enchants
            btn.enchantText = enchantText
            
            -- Tooltip scripts
            btn:SetScript("OnEnter", function()
                if this.link then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    local _, _, itemString = string.find(this.link, "^|c%x+|H(.+)|h%[.*%]")
                    if itemString then GameTooltip:SetHyperlink(itemString) else GameTooltip:SetHyperlink(this.link) end
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
            row.detailButtons[pos.slot] = btn
        end
        
        -- Gear Icons (Horizontal Scroll - Collapsed View)
        -- ... (keep existing code for collapsed view)
        
        -- Class-colored gradient background
        local color = self.classColors[player.class] or {0.5, 0.5, 0.5}
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        bg:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        bg:SetHeight(rowHeight)
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetGradientAlpha("HORIZONTAL", color[1], color[2], color[3], 0.6, color[1], color[2], color[3], 0)
        
        -- Dim if offline
        if not player.online then
            bg:SetGradientAlpha("HORIZONTAL", 0.3, 0.3, 0.3, 0.6, 0.3, 0.3, 0.3, 0)
        end
        
        -- Name-Guild (Anchor TOPLEFT)
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -5)
        nameText:SetWidth(100)
        nameText:SetJustifyH("LEFT")
        
        local displayName = player.name
        if player.guild and player.guild ~= "" then
            displayName = player.name .. "-\n" .. player.guild
        end
        nameText:SetText(displayName)
        
        if player.online then
            nameText:SetTextColor(color[1], color[2], color[3])
        else
            nameText:SetTextColor(0.5, 0.5, 0.5)
        end
        
        -- Race Icon (Anchor TOPLEFT)
        local raceGenderKey = player.race .. "_" .. player.gender
        local raceIcon = row:CreateTexture(nil, "ARTWORK")
        raceIcon:SetWidth(24)
        raceIcon:SetHeight(24)
        raceIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 110, -6)
        raceIcon:SetTexture(self.raceIcons[raceGenderKey] or self.raceIcons[player.race] or "Interface\\Icons\\INV_Misc_QuestionMark")
        
        -- Class Icon (Anchor Left of Race)
        local classIcon = row:CreateTexture(nil, "ARTWORK")
        classIcon:SetWidth(24)
        classIcon:SetHeight(24)
        classIcon:SetPoint("LEFT", raceIcon, "RIGHT", 4, 0)
        classIcon:SetTexture(self.classIcons[player.class] or "Interface\\Icons\\INV_Misc_QuestionMark")
        
        -- Spec Icon (placeholder - would need inspect for real data)
        local specIcon = row:CreateTexture(nil, "ARTWORK")
        specIcon:SetWidth(24)
        specIcon:SetHeight(24)
        specIcon:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
        specIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        
        -- Level (Anchor Left of Spec)
        local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        levelText:SetPoint("LEFT", specIcon, "RIGHT", 8, 0)
        levelText:SetText("L" .. player.level)
        levelText:SetTextColor(1, 0.82, 0)
        
        -- Store references for visibility toggle
        row.bg = bg
        row.nameText = nameText
        row.raceIcon = raceIcon
        row.classIcon = classIcon
        row.specIcon = specIcon
        row.levelText = levelText
        
        -- Gear Icons (Horizontal Scroll)
        local gearStartX = 250
        local availableWidth = rowWidth - gearStartX - 5
        
        -- Create scroll frame for gear
        local gearScroll = CreateFrame("ScrollFrame", nil, row)
        gearScroll:SetPoint("TOPLEFT", row, "TOPLEFT", gearStartX, 0)
        gearScroll:SetWidth(availableWidth)
        gearScroll:SetHeight(rowHeight)
        row.gearScroll = gearScroll -- Important ref for visibility toggle
        
        -- Create container for icons
        local gearContainer = CreateFrame("Frame", nil, gearScroll)
        gearContainer:SetWidth(1) -- Will expand
        gearContainer:SetHeight(rowHeight)
        gearScroll:SetScrollChild(gearContainer)
        row.gearScroll = gearScroll
        
        -- Enable mouse wheel for horizontal scroll
        gearScroll:EnableMouseWheel(true)
        gearScroll:SetScript("OnMouseWheel", function()
            local current = this:GetHorizontalScroll()
            local delta = arg1
            local new = math.max(0, current - (delta * 20))
            this:SetHorizontalScroll(new)
        end)
        
        row.gearIcons = {}
        row.unitName = player.name
        
        for slot = 1, 17 do -- 17 display slots
            local gearBtn = CreateFrame("Button", nil, gearContainer)
            gearBtn:SetWidth(gearIconSize)
            gearBtn:SetHeight(gearIconSize)
            gearBtn:SetPoint("LEFT", gearContainer, "LEFT", (slot-1) * (gearIconSize + gearSpacing), 0)
            
            local icon = gearBtn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(gearBtn)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetAlpha(0.3)
            gearBtn.icon = icon
            
            -- Tooltip scripts
            gearBtn:SetScript("OnEnter", function()
                if this.link then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    
                    -- Extract the "item:1234:..." part from the full link
                    -- Full link: |cff...|Hitem:1234...|h[Name]|h|r
                    local _, _, itemString = string.find(this.link, "^|c%x+|H(.+)|h%[.*%]")
                    
                    if itemString then
                        GameTooltip:SetHyperlink(itemString)
                    else
                        -- Fallback for standard links
                        GameTooltip:SetHyperlink(this.link)
                    end
                    GameTooltip:Show()
                end
            end)
            gearBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            
            row.gearIcons[slot] = gearBtn
        end
        
        -- Set container width based on icons
        gearContainer:SetWidth(17 * (gearIconSize + gearSpacing))
        
        table.insert(self.raidRows, row)
        
        -- Queue inspection if online
        if player.online then
            -- Check cache first
            if self.inspectCache[player.name] then
                self:UpdateRowGear(row, player.name)
            end
            
            -- If it's me, scrape immediately (no inspect needed)
            if player.name == UnitName("player") then
                -- Initialize cache entry
                local unitName = player.name
                if not self.inspectCache[unitName] then
                    self.inspectCache[unitName] = { gear = {}, links = {}, ilvl = 0 }
                end
                
                local gearData = self.inspectCache[unitName].gear
                local links = self.inspectCache[unitName].links
                
                for slot = 1, 19 do
                    local texture = GetInventoryItemTexture("player", slot)
                    if texture then
                        gearData[slot] = texture
                        links[slot] = GetInventoryItemLink("player", slot)
                    end
                end
                
                self:UpdateRowGear(row, unitName)
            else
                -- Queue for fresh data (or initially)
                self:QueueInspect(player.unitId)
            end
        end
    end
    
    -- Update scroll child height (Dynamic)
    self:RebuildRowLayout()
end

-- Navigate to adjacent player in expanded view
function Module:NavigateToPlayer(direction)
    -- direction: -1 for back, +1 for forward
    local currentIndex = 0
    for i, row in ipairs(self.raidRows) do
        if row.isExpanded then
            currentIndex = i
            break
        end
    end
    
    if currentIndex == 0 then return end
    
    local newIndex = currentIndex + direction
    if newIndex < 1 or newIndex > table.getn(self.raidRows) then return end
    
    -- Collapse current, expand new
    self.raidRows[currentIndex].isExpanded = false
    self.raidRows[newIndex].isExpanded = true
    
    self:RebuildRowLayout()
    
    -- Scroll to top
    local scrollFrame = self.equipmentScrollChild:GetParent()
    scrollFrame:SetVerticalScroll(0)
end

function Module:RebuildRowLayout()
    local scrollChild = self.equipmentScrollChild
    if not scrollChild then return end
    
    local scrollFrame = scrollChild:GetParent()
    local visibleHeight = scrollFrame:GetHeight() or 400
    
    local yOffset = 0
    local baseHeight = 36
    -- Maximize expanded height to fill view exactly so next row is seamless
    -- Ensure explicit height (500) to fit bottom text
    local expandedHeight = math.max(visibleHeight, 500)
    -- Check if ANY row is expanded
    local anyExpanded = false
    for _, row in ipairs(self.raidRows) do
        if row.isExpanded then 
            anyExpanded = true 
            break 
        end
    end
    
    for i, row in ipairs(self.raidRows) do
        -- If something is expanded, hide everything else
        if anyExpanded then
            if row.isExpanded then
                row:Show()
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
                row:SetHeight(expandedHeight)
                yOffset = expandedHeight -- Total Scroll Height will be just one expanded row
                row.detailFrame:Show()
                row.gearScroll:Hide()
                -- Hide collapsed elements
                if row.bg then row.bg:Hide() end
                if row.nameText then row.nameText:Hide() end
                if row.raceIcon then row.raceIcon:Hide() end
                if row.classIcon then row.classIcon:Hide() end
                if row.specIcon then row.specIcon:Hide() end
                if row.levelText then row.levelText:Hide() end
                
                -- Update Navigation Button States
                local totalRows = table.getn(self.raidRows)
                if row.backNavBtn then
                    if i == 1 then
                        -- At first player, disable back
                        row.backNavBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        if row.backNavBtn.text then row.backNavBtn.text:SetTextColor(0.3, 0.3, 0.3) end
                        row.backNavBtn:Disable()
                    else
                        row.backNavBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
                        if row.backNavBtn.text then row.backNavBtn.text:SetTextColor(1, 0.82, 0) end
                        row.backNavBtn:Enable()
                    end
                end
                if row.forwardNavBtn then
                    if i == totalRows then
                        -- At last player, disable forward
                        row.forwardNavBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                        if row.forwardNavBtn.text then row.forwardNavBtn.text:SetTextColor(0.3, 0.3, 0.3) end
                        row.forwardNavBtn:Disable()
                    else
                        row.forwardNavBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
                        if row.forwardNavBtn.text then row.forwardNavBtn.text:SetTextColor(1, 0.82, 0) end
                        row.forwardNavBtn:Enable()
                    end
                end
                
                -- Check if player is scanned (has cached data)
                local isScanned = self.inspectCache[row.unitName] and self.inspectCache[row.unitName].gear
                
                if isScanned then
                    -- Show gear slots, hide Not Scanned
                    if row.notScannedText then row.notScannedText:Hide() end
                    if row.detailButtons then
                        for _, btn in pairs(row.detailButtons) do
                            btn:Show()
                        end
                    end
                else
                    -- Hide gear slots, show Not Scanned
                    if row.notScannedText then row.notScannedText:Show() end
                    if row.detailButtons then
                        for _, btn in pairs(row.detailButtons) do
                            btn:Hide()
                        end
                    end
                end
            else
                row:Hide()
                row:SetHeight(1) -- Min height just in case
            end
        else
            -- Normal View
            row:Show()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            row:SetHeight(baseHeight)
            yOffset = yOffset + baseHeight
            row.detailFrame:Hide()
            row.gearScroll:Show()
            -- Show collapsed elements
            if row.bg then row.bg:Show() end
            if row.nameText then row.nameText:Show() end
            if row.raceIcon then row.raceIcon:Show() end
            if row.classIcon then row.classIcon:Show() end
            if row.specIcon then row.specIcon:Show() end
            if row.levelText then row.levelText:Show() end
        end
    end
    
    scrollChild:SetHeight(yOffset)
end



function Module:BuildTalentsContent(parent)
    local placeholder = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    placeholder:SetPoint("CENTER", parent, "CENTER", 0, 0)
    placeholder:SetText("Talents Tab\n(Coming Soon)")
    placeholder:SetTextColor(0.5, 0.5, 0.5)
end
