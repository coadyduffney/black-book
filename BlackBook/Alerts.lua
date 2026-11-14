local _, ns = ...

-- Nameplates flicker in and out at the edge of range, so only alert once per player per window.
local ALERT_COOLDOWN = 60
local ALERT_HOLD, ALERT_FADE = 4, 1
local ALERT_SOUND = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959

local lastAlerted = {}
local alertFrame

local Readable = ns.Readable

local function GetUnitFullName(unit)
    local name, realm = UnitName(unit)
    name, realm = Readable(name), Readable(realm)
    if type(name) ~= "string" then
        return nil
    end
    return ns.MakeKey(name, realm)
end

local function FindEntry(unit)
    local guid = Readable(UnitGUID(unit))
    local name = GetUnitFullName(unit)

    for _, entry in pairs(ns.db.players) do
        if guid and entry.guid == guid then
            return entry
        end
        if not entry.guid and name and entry.name == name then
            return entry
        end
    end
end

local function CreateAlertFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(800, 70)
    f:SetPoint("TOP", 0, -160)
    f:SetFrameStrata("HIGH")
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.title:SetPoint("TOP")
    f.title:SetTextColor(1, 0.2, 0.2)

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.subtitle:SetPoint("TOP", f.title, "BOTTOM", 0, -6)

    f.fadeOut = f:CreateAnimationGroup()
    local fade = f.fadeOut:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(ALERT_HOLD)
    fade:SetDuration(ALERT_FADE)
    f.fadeOut:SetScript("OnFinished", function() f:Hide() end)

    return f
end

function ns.ShowAlert(entry)
    alertFrame = alertFrame or CreateAlertFrame()

    local color = entry.class and RAID_CLASS_COLORS[entry.class]
    local coloredName = color and color:WrapTextInColorCode(entry.name) or entry.name
    local details = "Your record: " .. ns.FormatRecord(entry)

    alertFrame.title:SetText(coloredName .. " is nearby!")
    alertFrame.subtitle:SetText(details)
    alertFrame.fadeOut:Stop()
    alertFrame:SetAlpha(1)
    alertFrame:Show()
    alertFrame.fadeOut:Play()

    if ns.db.alertSound then
        PlaySound(ALERT_SOUND, "Master")
    end
    ns.Print(format("%s is nearby. %s.", coloredName, details))
end

local function CheckUnit(unit)
    if not ns.db or IsInInstance() then
        return
    end
    if not Readable(UnitIsPlayer(unit)) or not Readable(UnitIsEnemy("player", unit)) then
        return
    end

    local entry = FindEntry(unit)
    if not entry then
        return
    end

    ns.UpdateLevel(entry, unit)
    if not ns.db.alerts or not ns.IsListed(entry) then
        return
    end

    local now = GetTime()
    if lastAlerted[entry.name] and now - lastAlerted[entry.name] < ALERT_COOLDOWN then
        return
    end
    lastAlerted[entry.name] = now

    ns.ShowAlert(entry)
end

local events = {
    NAME_PLATE_UNIT_ADDED = function(unit) CheckUnit(unit) end,
    PLAYER_TARGET_CHANGED = function() CheckUnit("target") end,
    UPDATE_MOUSEOVER_UNIT = function() CheckUnit("mouseover") end,
}

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    events[event](...)
end)
for event in pairs(events) do
    eventFrame:RegisterEvent(event)
end
