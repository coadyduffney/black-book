local _, ns = ...

local UI = {}
ns.UI = UI

local FRAME_WIDTH, FRAME_HEIGHT = 400, 420
local ROW_HEIGHT = 20
local COLUMNS = {
    { key = "name", label = "Name", x = 6, width = 150, justify = "LEFT" },
    { key = "count", label = "Kills", x = 160, width = 45, justify = "RIGHT" },
    { key = "assists", label = "Assists", x = 212, width = 55, justify = "RIGHT" },
    { key = "lastSeen", label = "Last", x = 275, width = 70, justify = "RIGHT" },
}

local function FormatDate(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M", timestamp) or "never"
end

local sortKey, sortAscending = "count", false
local frame

local function FormatAgo(timestamp)
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

local function Compare(a, b)
    local left, right = a[sortKey], b[sortKey]
    if left ~= right then
        if sortAscending then
            return left < right
        end
        return left > right
    end
    return a.name < b.name
end

local function BuildSortedList()
    local list = {}
    for _, entry in pairs(ns.db.killers) do
        list[#list + 1] = entry
    end
    table.sort(list, Compare)

    local rows = {}
    for index, entry in ipairs(list) do
        rows[index] = { entry = entry, index = index }
    end
    return rows
end

local function Plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

local function ShowRowTooltip(row)
    local entry = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ClassColoredName(entry))
    if entry.race or entry.class then
        local className = entry.class and LOCALIZED_CLASS_NAMES_MALE[entry.class]
        GameTooltip:AddLine(strtrim((entry.race or "") .. " " .. (className or "")), 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Times killed you", entry.count, nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("Assists on your death", entry.assists, nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("First seen", FormatDate(entry.firstSeen), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("Last kill", FormatDate(entry.lastKill), nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine("Last assist", FormatDate(entry.lastAssist), nil, nil, nil, 1, 1, 1)
    if entry.lastZone then
        GameTooltip:AddDoubleLine("Last seen in", entry.lastZone, nil, nil, nil, 1, 1, 1)
    end
    if entry.lastSpell then
        GameTooltip:AddDoubleLine("Last killing blow", entry.lastSpell, nil, nil, nil, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to remove", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

StaticPopupDialogs["BLACKBOOK_REMOVE"] = {
    text = "Remove %s from your Black Book?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, name) ns.RemoveKiller(name) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateColumnText(parent, column, fontObject)
    local text = parent:CreateFontString(nil, "OVERLAY", fontObject)
    text:SetPoint("LEFT", column.x, 0)
    text:SetWidth(column.width)
    text:SetJustifyH(column.justify)
    text:SetWordWrap(false)
    return text
end

local function InitRow(row, rowData)
    local entry = rowData.entry
    if not row.columns then
        row:SetHeight(ROW_HEIGHT)
        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, 0.03)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)

        row.columns = {}
        for _, column in ipairs(COLUMNS) do
            row.columns[column.key] = CreateColumnText(row, column, "GameFontHighlight")
        end

        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self)
            StaticPopup_Show("BLACKBOOK_REMOVE", self.entry.name, nil, self.entry.name)
        end)
    end

    row.entry = entry
    row.columns.name:SetText(ClassColoredName(entry))
    row.columns.count:SetText(entry.count)
    row.columns.assists:SetText(entry.assists)
    row.columns.lastSeen:SetText(FormatAgo(entry.lastSeen))
    row.stripe:SetShown(rowData.index % 2 == 0)
end

local function SavePosition(self)
    local point, _, relativePoint, x, y = self:GetPoint()
    ns.db.window = { point = point, relativePoint = relativePoint, x = x, y = y }
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

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(ROW_HEIGHT)
    header.labels = {}

    for _, column in ipairs(COLUMNS) do
        local button = CreateFrame("Button", nil, header)
        button:SetPoint("LEFT", column.x, 0)
        button:SetSize(column.width, ROW_HEIGHT)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetAllPoints()
        label:SetJustifyH(column.justify)
        header.labels[column.key] = label
        button.label = column.label

        button:SetScript("OnClick", function()
            if sortKey == column.key then
                sortAscending = not sortAscending
            else
                sortKey = column.key
                sortAscending = column.key == "name"
            end
            UI:Refresh()
        end)
    end

    function header:Update()
        for _, column in ipairs(COLUMNS) do
            local arrow = ""
            if column.key == sortKey then
                arrow = sortAscending and " ^" or " v"
            end
            self.labels[column.key]:SetText(column.label .. arrow)
        end
    end

    return header
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
    f.emptyText:SetText("Nobody has killed you in open-world PvP yet.")

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.footer:SetPoint("BOTTOMLEFT", 14, 12)

    RestorePosition(f)
    return f
end

function UI:Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    local rows = BuildSortedList()
    local totalDeaths = 0
    for _, row in ipairs(rows) do
        totalDeaths = totalDeaths + row.entry.count
    end

    frame.header:Update()
    frame.scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    frame.emptyText:SetShown(#rows == 0)
    frame.footer:SetText(Plural(#rows, "player") .. ", " .. Plural(totalDeaths, "kill"))
end

function UI:Toggle()
    if not frame then
        frame = CreateMainFrame()
        frame:SetScript("OnShow", function() UI:Refresh() end)
    end
    frame:SetShown(not frame:IsShown())
end
