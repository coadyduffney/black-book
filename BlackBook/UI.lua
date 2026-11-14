local _, ns = ...

local UI = {}
ns.UI = UI

local FRAME_WIDTH, FRAME_HEIGHT = 440, 420
local ROW_HEIGHT = 20
local COLUMN_GAP = 8

local frame

local function Plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

local function FormatDate(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M", timestamp) or "never"
end

local function FormatAgo(timestamp)
    if not timestamp then
        return ""
    end
    local seconds = time() - timestamp
    if seconds < 60 then
        return "just now"
    elseif seconds < 3600 then
        return floor(seconds / 60) .. "m ago"
    elseif seconds < 86400 then
        return floor(seconds / 3600) .. "h ago"
    end
    return floor(seconds / 86400) .. "d ago"
end

local function ClassColoredName(entry)
    local color = entry.class and RAID_CLASS_COLORS[entry.class]
    return color and color:WrapTextInColorCode(entry.name) or entry.name
end

-- Your kills against them, then their kills against you; green when you're ahead.
local function FormatShortRecord(entry)
    local text = entry.kills .. "-" .. entry.deaths
    if entry.kills > entry.deaths then
        return GREEN_FONT_COLOR:WrapTextInColorCode(text)
    elseif entry.kills < entry.deaths then
        return RED_FONT_COLOR:WrapTextInColorCode(text)
    end
    return text
end

local function LayOutColumns(columns)
    local x = 6
    for _, column in ipairs(columns) do
        column.x = x
        column.justify = column.justify or "RIGHT"
        x = x + column.width + COLUMN_GAP
    end
    return columns
end

local TABS = {
    {
        label = "Deaths",
        filter = ns.IsListed,
        emptyText = "Nobody has killed you in open-world PvP yet.",
        sortKey = "deaths",
        columns = LayOutColumns({
            { key = "name", label = "Name", width = 120, justify = "LEFT" },
            { key = "deaths", label = "Killed you", width = 70 },
            { key = "assists", label = "Assists", width = 55 },
            { key = "record", label = "Record", width = 55 },
            { key = "lastSeen", label = "Last", width = 60 },
        }),
    },
    {
        label = "Kills",
        filter = function(entry) return entry.kills > 0 end,
        emptyText = "You haven't killed anyone in open-world PvP yet.",
        sortKey = "kills",
        columns = LayOutColumns({
            { key = "name", label = "Name", width = 170, justify = "LEFT" },
            { key = "kills", label = "Kills", width = 50 },
            { key = "record", label = "Record", width = 60 },
            { key = "lastKill", label = "Last", width = 70 },
        }),
    },
}

local function GetCurrentTab()
    return TABS[ns.db.window.tab] or TABS[1]
end

local function GetSortValue(entry, key)
    if key == "name" then
        return entry.name:lower()
    elseif key == "record" then
        return entry.kills - entry.deaths
    end
    return entry[key] or 0
end

local function GetCellText(entry, key)
    if key == "name" then
        return ClassColoredName(entry)
    elseif key == "record" then
        return FormatShortRecord(entry)
    elseif key == "lastSeen" or key == "lastKill" then
        return FormatAgo(entry[key])
    end
    return entry[key]
end

local function BuildSortedList(tab)
    local list = {}
    for _, entry in pairs(ns.db.players) do
        if tab.filter(entry) then
            list[#list + 1] = entry
        end
    end

    table.sort(list, function(a, b)
        local left, right = GetSortValue(a, tab.sortKey), GetSortValue(b, tab.sortKey)
        if left ~= right then
            if tab.sortAscending then
                return left < right
            end
            return left > right
        end
        return a.name < b.name
    end)

    local rows = {}
    for index, entry in ipairs(list) do
        rows[index] = { entry = entry, index = index }
    end
    return rows
end

local function ShowRowTooltip(row)
    local entry = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ClassColoredName(entry))
    local levelText = entry.level and ("Level " .. (entry.level == -1 and "??" or entry.level)) or ""
    local className = entry.class and LOCALIZED_CLASS_NAMES_MALE[entry.class]
    local description = strtrim(levelText .. " " .. (entry.race or "") .. " " .. (className or ""))
    if description ~= "" then
        GameTooltip:AddLine(description, 1, 1, 1)
    end
    if entry.levelSeen then
        GameTooltip:AddLine("Level seen " .. FormatAgo(entry.levelSeen), 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Your record", ns.FormatRecord(entry), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("Assists on your death", entry.assists, nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("First seen", FormatDate(entry.firstSeen), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("Last killed you", FormatDate(entry.lastDeath), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("Last killed by you", FormatDate(entry.lastKill), nil, nil, nil, 1, 1, 1)
    if entry.assists > 0 then
        GameTooltip:AddDoubleLine("Last assist", FormatDate(entry.lastAssist), nil, nil, nil, 1, 1, 1)
    end
    if entry.lastZone then
        GameTooltip:AddDoubleLine("Last seen in", entry.lastZone, nil, nil, nil, 1, 1, 1)
    end
    if entry.lastSpell then
        GameTooltip:AddDoubleLine("Last killing blow on you", entry.lastSpell, nil, nil, nil, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to remove", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

StaticPopupDialogs["BLACKBOOK_REMOVE"] = {
    text = "Remove %s from your Black Book? Their kills and deaths will be erased.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, name) ns.RemoveEntry(name) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Rows and header buttons are shared between tabs, so each column's text is
-- created on first use and re-anchored for whichever tab is showing.
local function PlaceColumnText(text, column)
    text:ClearAllPoints()
    text:SetPoint("LEFT", column.x, 0)
    text:SetWidth(column.width)
    text:SetJustifyH(column.justify)
end

local function InitRow(row, rowData)
    if not row.columns then
        row:SetHeight(ROW_HEIGHT)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, 0.03)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)
        row.columns = {}

        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self)
            StaticPopup_Show("BLACKBOOK_REMOVE", self.entry.name, nil, self.entry.name)
        end)
    end

    for _, text in pairs(row.columns) do
        text:Hide()
    end

    local entry = rowData.entry
    for _, column in ipairs(GetCurrentTab().columns) do
        local text = row.columns[column.key]
        if not text then
            text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetWordWrap(false)
            row.columns[column.key] = text
        end
        PlaceColumnText(text, column)
        text:SetText(GetCellText(entry, column.key))
        text:Show()
    end

    row.entry = entry
    row.stripe:SetShown(rowData.index % 2 == 0)
end

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(ROW_HEIGHT)
    header.buttons = {}

    local function GetButton(key)
        local button = header.buttons[key]
        if not button then
            button = CreateFrame("Button", nil, header)
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.label:SetAllPoints()
            button:SetScript("OnClick", function(self)
                local tab = GetCurrentTab()
                if tab.sortKey == self.key then
                    tab.sortAscending = not tab.sortAscending
                else
                    tab.sortKey = self.key
                    tab.sortAscending = self.key == "name"
                end
                UI:Refresh()
            end)
            button.key = key
            header.buttons[key] = button
        end
        return button
    end

    function header:Update()
        for _, button in pairs(self.buttons) do
            button:Hide()
        end

        local tab = GetCurrentTab()
        for _, column in ipairs(tab.columns) do
            local button = GetButton(column.key)
            button:ClearAllPoints()
            button:SetPoint("LEFT", column.x, 0)
            button:SetSize(column.width, ROW_HEIGHT)
            button.label:SetJustifyH(column.justify)

            local arrow = ""
            if column.key == tab.sortKey then
                arrow = tab.sortAscending and " ^" or " v"
            end
            button.label:SetText(column.label .. arrow)
            button:Show()
        end
    end

    return header
end

local function SavePosition(self)
    local point, _, relativePoint, x, y = self:GetPoint()
    local saved = ns.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function RestorePosition(self)
    local saved = ns.db.window
    self:ClearAllPoints()
    if saved.point then
        self:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        self:SetPoint("CENTER")
    end
end

local function SelectTab(id)
    ns.db.window.tab = id
    PanelTemplates_SetTab(frame, id)
    UI:Refresh()
end

local function CreateTabs(f)
    for id, tab in ipairs(TABS) do
        local button = CreateFrame("Button", "BlackBookFrameTab" .. id, f, "PanelTabButtonTemplate")
        button:SetID(id)
        button:SetText(tab.label)
        button:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
        if PanelTemplates_TabResize then
            PanelTemplates_TabResize(button, 0)
        end
    end
    f.Tabs[1]:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 8, 2)
    PanelTemplates_SetNumTabs(f, #TABS)
end

local function CreateMainFrame()
    local f = CreateFrame("Frame", "BlackBookFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())

    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not f.TitleText then
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("Black Book")

    f.header = CreateHeader(f)
    f.header:SetPoint("TOPLEFT", 12, -30)
    f.header:SetPoint("TOPRIGHT", -30, -30)

    f.scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    f.scrollBox:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
    f.scrollBox:SetPoint("BOTTOMRIGHT", -30, 32)

    f.scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    f.scrollBar:SetPoint("TOPLEFT", f.scrollBox, "TOPRIGHT", 6, 0)
    f.scrollBar:SetPoint("BOTTOMLEFT", f.scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(f.scrollBox, f.scrollBar, view)

    f.emptyText = f.scrollBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.emptyText:SetPoint("CENTER")
    f.emptyText:SetWidth(FRAME_WIDTH - 80)

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.footer:SetPoint("BOTTOMLEFT", 14, 12)

    CreateTabs(f)
    RestorePosition(f)
    return f
end

local function GetFooterText(tab, rows)
    if tab == TABS[1] then
        local deaths = 0
        for _, row in ipairs(rows) do
            deaths = deaths + row.entry.deaths
        end
        return Plural(#rows, "player") .. ", " .. Plural(deaths, "death")
    end

    local kills = 0
    for _, row in ipairs(rows) do
        kills = kills + row.entry.kills
    end
    return format("%s, kill streak: %d (best %d)", Plural(kills, "kill"), ns.db.streak, ns.db.bestStreak)
end

function UI:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    local tab = GetCurrentTab()
    local rows = BuildSortedList(tab)

    frame.header:Update()
    frame.scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    frame.emptyText:SetText(tab.emptyText)
    frame.emptyText:SetShown(#rows == 0)
    frame.footer:SetText(GetFooterText(tab, rows))
end

function UI:Toggle()
    if not frame then
        frame = CreateMainFrame()
        frame:SetScript("OnShow", function() SelectTab(ns.db.window.tab) end)
    end
    frame:SetShown(not frame:IsShown())
end
