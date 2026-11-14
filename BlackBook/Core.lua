local addonName, ns = ...

local DB_VERSION = 2
-- The death recap is filled in shortly after PLAYER_DEAD, so poll for it briefly.
local RECAP_POLL_INTERVAL = 0.25
local RECAP_POLL_ATTEMPTS = 20

local defaults = {
    version = DB_VERSION,
    announce = true,
    alerts = true,
    alertSound = true,
    killers = {},
    window = {},
    minimap = { hide = false, angle = 225 },
}

local MAX_NAMEPLATES = 40

local lastRecapIdentity

function ns.Print(msg)
    print("|cffc41e3aBlack Book|r: " .. msg)
end

-- Forever can hand addons secret values in restricted situations; treat those as missing.
local function Readable(value)
    if value ~= nil and issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end
ns.Readable = Readable

-- Only units the game has a token for can be inspected, so look where the player might be visible.
local function FindUnitByGUID(guid)
    for _, unit in ipairs({ "target", "mouseover", "focus" }) do
        if Readable(UnitGUID(unit)) == guid then
            return unit
        end
    end
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if Readable(UnitGUID(unit)) == guid then
            return unit
        end
    end
end

-- UnitLevel returns -1 for players too far above you to see their level.
function ns.UpdateLevel(entry, unit)
    local level = Readable(UnitLevel(unit))
    if type(level) == "number" and level ~= 0 then
        entry.level = level
        entry.levelSeen = time()
    end
end

local function MergeDefaults(target, source)
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

local function GetLatestRecapID()
    local ok, link = pcall(C_DeathRecap.GetRecapLink)
    link = ok and Readable(link)
    if type(link) ~= "string" then
        return nil
    end
    return tonumber(link:match("Hdeath:(%d+)"))
end

-- Returns an identity that changes with every new death, plus the recap events
-- (killing blow first), or nil if no recap is available yet.
local function ReadLatestRecap()
    local recapID = GetLatestRecapID()

    local okHas, hasEvents = pcall(C_DeathRecap.HasRecapEvents, recapID)
    if not okHas or not Readable(hasEvents) then
        return nil
    end

    local okEvents, events = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not okEvents or type(events) ~= "table" or not events[1] then
        return nil
    end

    return recapID or Readable(events[1].timestamp), events
end

-- Returns { guid, name, spell } if the recap event's damage came from another player.
local function GetPlayerSource(event)
    if Readable(event.hideCaster) then
        return nil
    end

    local guid = Readable(event.sourceGUID)
    local name = Readable(event.sourceName)
    if type(guid) ~= "string" or type(name) ~= "string" or name == "" then
        return nil
    end
    if not guid:find("^Player%-") or guid == UnitGUID("player") then
        return nil
    end

    local spell = Readable(event.spellName)
    if Readable(event.event) == "SWING_DAMAGE" then
        spell = ACTION_SWING or "Melee"
    end

    return { guid = guid, name = name, spell = spell }
end

-- Returns the player who landed the killing blow (or nil) and every other player
-- who damaged you within the recap, each listed once.
local function GetDeathParticipants(events)
    local killer = GetPlayerSource(events[1])
    local assisters = {}
    local seen = { [killer and killer.name or ""] = true }

    for i = 2, #events do
        local source = GetPlayerSource(events[i])
        if source and not seen[source.name] then
            seen[source.name] = true
            assisters[#assisters + 1] = source
        end
    end

    return killer, assisters
end

local function GetCurrentZone()
    local zone = GetRealZoneText()
    local subZone = GetSubZoneText()
    if subZone and subZone ~= "" and subZone ~= zone then
        zone = subZone .. ", " .. zone
    end
    return zone
end

local function GetOrCreateEntry(source, now)
    local entry = ns.db.killers[source.name]
    if not entry then
        entry = { name = source.name, count = 0, assists = 0, firstSeen = now }
        ns.db.killers[source.name] = entry
    end

    entry.guid = source.guid

    local unit = FindUnitByGUID(source.guid)
    if unit then
        ns.UpdateLevel(entry, unit)
    end

    local ok, _, englishClass, localizedRace = pcall(GetPlayerInfoByGUID, source.guid)
    if ok then
        entry.class = Readable(englishClass) or entry.class
        entry.race = Readable(localizedRace) or entry.race
    end

    entry.lastSeen = now
    entry.lastZone = GetCurrentZone()
    return entry
end

local function RecordDeath(killer, assisters)
    local now = time()
    local assisterNames = {}

    for _, source in ipairs(assisters) do
        local entry = GetOrCreateEntry(source, now)
        entry.assists = entry.assists + 1
        entry.lastAssist = now
        assisterNames[#assisterNames + 1] = source.name
    end

    local killerEntry
    if killer then
        killerEntry = GetOrCreateEntry(killer, now)
        killerEntry.count = killerEntry.count + 1
        killerEntry.firstKill = killerEntry.firstKill or now
        killerEntry.lastKill = now
        killerEntry.lastSpell = killer.spell
    end

    if ns.db.announce then
        local assistText = #assisterNames > 0 and (" Assisted by " .. table.concat(assisterNames, ", ") .. ".") or ""
        if killerEntry then
            local times = killerEntry.count == 1 and "once" or (killerEntry.count .. " times")
            ns.Print(format("%s has now killed you %s.%s", killer.name, times, assistText))
        else
            ns.Print("The killing blow wasn't from a player." .. assistText)
        end
    end

    ns.UI:Refresh()
end

local function ProcessDeath(attempt)
    local identity, events = ReadLatestRecap()
    if not identity or identity == lastRecapIdentity then
        if attempt < RECAP_POLL_ATTEMPTS then
            C_Timer.After(RECAP_POLL_INTERVAL, function() ProcessDeath(attempt + 1) end)
        end
        return
    end

    lastRecapIdentity = identity

    local killer, assisters = GetDeathParticipants(events)
    if killer or #assisters > 0 then
        RecordDeath(killer, assisters)
    end
end

function ns.RemoveKiller(key)
    ns.db.killers[key] = nil
    ns.UI:Refresh()
end

function ns.ResetAll()
    wipe(ns.db.killers)
    ns.UI:Refresh()
    ns.Print("All entries have been erased.")
end

local function PrintLastRecap()
    local _, events = ReadLatestRecap()
    if not events then
        ns.Print("No death recap is available.")
        return
    end

    local killingBlow = events[1]
    ns.Print(format("The last recap holds %d hits. Killing blow: source=%s, guid=%s, spell=%s",
        #events,
        tostring(Readable(killingBlow.sourceName)),
        tostring(Readable(killingBlow.sourceGUID)),
        tostring(Readable(killingBlow.spellName))))

    local killer, assisters = GetDeathParticipants(events)
    ns.Print(killer and "That counts as a player kill." or "That does not count as a player kill.")

    local assisterNames = {}
    for _, source in ipairs(assisters) do
        assisterNames[#assisterNames + 1] = source.name
    end
    ns.Print("Assists: " .. (#assisterNames > 0 and table.concat(assisterNames, ", ") or "none"))
end

StaticPopupDialogs["BLACKBOOK_RESET"] = {
    text = "Erase every name in your Black Book?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.ResetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

SLASH_BLACKBOOK1 = "/blackbook"
SLASH_BLACKBOOK2 = "/bbook"
SlashCmdList.BLACKBOOK = function(input)
    local command = strtrim(input or ""):lower()
    if command == "" or command == "show" then
        ns.UI:Toggle()
    elseif command == "announce" then
        ns.db.announce = not ns.db.announce
        ns.Print("Chat announcements " .. (ns.db.announce and "on." or "off."))
    elseif command == "alerts" then
        ns.db.alerts = not ns.db.alerts
        ns.Print("Nearby alerts " .. (ns.db.alerts and "on." or "off."))
    elseif command == "sound" then
        ns.db.alertSound = not ns.db.alertSound
        ns.Print("Alert sound " .. (ns.db.alertSound and "on." or "off."))
    elseif command == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        ns.UpdateMinimapButton()
        ns.Print("Minimap button " .. (ns.db.minimap.hide and "hidden." or "shown."))
    elseif command == "test" then
        ns.ShowAlert({ name = UnitName("player"), class = select(2, UnitClass("player")), count = 3, assists = 1 })
    elseif command == "reset" then
        StaticPopup_Show("BLACKBOOK_RESET")
    elseif command == "last" then
        PrintLastRecap()
    else
        ns.Print("Commands:")
        print("  /blackbook - show or hide the window")
        print("  /blackbook announce - toggle the chat message when players kill you")
        print("  /blackbook alerts - toggle the warning when a listed player is nearby")
        print("  /blackbook sound - toggle the warning sound")
        print("  /blackbook minimap - show or hide the minimap button")
        print("  /blackbook test - show a sample warning")
        print("  /blackbook last - explain how your last death was read")
        print("  /blackbook reset - erase all entries")
    end
end

function BlackBook_OnAddonCompartmentClick()
    ns.UI:Toggle()
end

local events = {}

function events.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then
        return
    end
    BlackBookDB = BlackBookDB or {}
    MergeDefaults(BlackBookDB, defaults)
    ns.db = BlackBookDB

    if ns.db.version < 2 then
        for _, entry in pairs(ns.db.killers) do
            entry.assists = entry.assists or 0
            entry.firstSeen = entry.firstSeen or entry.firstKill
            entry.lastSeen = entry.lastSeen or entry.lastKill
        end
        ns.db.version = 2
    end
end

function events.PLAYER_LOGIN()
    -- Remember any recap that already exists so a death from before login is not counted again.
    lastRecapIdentity = ReadLatestRecap()
end

function events.PLAYER_DEAD()
    if IsInInstance() then
        return
    end
    ProcessDeath(1)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    events[event](...)
end)
for event in pairs(events) do
    eventFrame:RegisterEvent(event)
end
