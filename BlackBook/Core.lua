local addonName, ns = ...

local DB_VERSION = 3
-- The death recap is filled in shortly after PLAYER_DEAD, so poll for it briefly.
local RECAP_POLL_INTERVAL = 0.25
local RECAP_POLL_ATTEMPTS = 20
local MAX_NAMEPLATES = 40

local defaults = {
    version = DB_VERSION,
    announce = true,
    alerts = true,
    alertSound = true,
    -- Every player you have killed, or who has killed you or assisted on your death, keyed by name.
    players = {},
    streak = 0,
    bestStreak = 0,
    window = { tab = 1 },
    minimap = { hide = false, angle = 225 },
}

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

local function Plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

-- The Black Book itself: players who have killed you or assisted on your death.
function ns.IsListed(entry)
    return entry.deaths > 0 or entry.assists > 0
end

function ns.FormatRecord(entry)
    return Plural(entry.kills, "kill") .. ", " .. Plural(entry.deaths, "death")
end

-- Death recap names cross-realm players as "Name-Realm", with spaces removed from the realm.
local function MakeKey(name, realm)
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm:gsub("%s", "")
    end
    return name
end
ns.MakeKey = MakeKey

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

-- Level -1 means the player is too far above you to see their level.
local function SetLevel(entry, level)
    level = Readable(level)
    if type(level) == "number" and level ~= 0 then
        entry.level = level
        entry.levelSeen = time()
    end
end

function ns.UpdateLevel(entry, unit)
    SetLevel(entry, UnitLevel(unit))
end

-- Returns name, realm, englishClass, localizedRace and level for a player GUID, as far as known.
local function GetPlayerInfo(guid)
    local ok, _, englishClass, localizedRace, _, _, name, realm, level = pcall(GetPlayerInfoByGUID, guid)
    if not ok then
        return nil
    end
    return Readable(name), Readable(realm), Readable(englishClass), Readable(localizedRace), Readable(level)
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

local function GetCurrentZone()
    local zone = GetRealZoneText()
    local subZone = GetSubZoneText()
    if subZone and subZone ~= "" and subZone ~= zone then
        zone = subZone .. ", " .. zone
    end
    return zone
end

local function FindEntryByGUID(guid)
    for _, entry in pairs(ns.db.players) do
        if entry.guid == guid then
            return entry
        end
    end
end

local function GetOrCreateEntry(guid, name, now)
    local entry = FindEntryByGUID(guid) or ns.db.players[name]
    if not entry then
        entry = { name = name, kills = 0, deaths = 0, assists = 0, firstSeen = now }
        ns.db.players[name] = entry
    end
    entry.guid = guid

    local _, _, englishClass, localizedRace, level = GetPlayerInfo(guid)
    entry.class = englishClass or entry.class
    entry.race = localizedRace or entry.race
    if level then
        SetLevel(entry, level)
    else
        local unit = FindUnitByGUID(guid)
        if unit then
            ns.UpdateLevel(entry, unit)
        end
    end

    entry.lastSeen = now
    entry.lastZone = GetCurrentZone()
    return entry
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

local function RecordDeath(killer, assisters)
    local now = time()
    local assisterNames = {}

    for _, source in ipairs(assisters) do
        local entry = GetOrCreateEntry(source.guid, source.name, now)
        entry.assists = entry.assists + 1
        entry.lastAssist = now
        assisterNames[#assisterNames + 1] = source.name
    end

    local killerEntry
    if killer then
        killerEntry = GetOrCreateEntry(killer.guid, killer.name, now)
        killerEntry.deaths = killerEntry.deaths + 1
        killerEntry.lastDeath = now
        killerEntry.lastSpell = killer.spell
    end

    if ns.db.announce then
        local assistText = #assisterNames > 0 and (" Assisted by " .. table.concat(assisterNames, ", ") .. ".") or ""
        if killerEntry then
            ns.Print(format("%s killed you.%s Your record against them: %s.",
                killer.name, assistText, ns.FormatRecord(killerEntry)))
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

local function RecordKill(victimGUID)
    ns.db.streak = ns.db.streak + 1
    ns.db.bestStreak = max(ns.db.bestStreak, ns.db.streak)

    local name, realm = GetPlayerInfo(victimGUID)
    if not name then
        local unit = FindUnitByGUID(victimGUID)
        if unit then
            name, realm = UnitName(unit)
            name, realm = Readable(name), Readable(realm)
        end
    end

    local entry
    if name then
        entry = GetOrCreateEntry(victimGUID, MakeKey(name, realm), time())
        entry.kills = entry.kills + 1
        entry.lastKill = entry.lastSeen
    end

    if ns.db.announce then
        local streakText = format("Kill streak: %d.", ns.db.streak)
        if entry then
            ns.Print(format("You killed %s! %s Your record against them: %s.",
                entry.name, streakText, ns.FormatRecord(entry)))
        else
            ns.Print("You killed a player! " .. streakText)
        end
    end

    ns.UI:Refresh()
end

function ns.RemoveEntry(key)
    ns.db.players[key] = nil
    ns.UI:Refresh()
end

function ns.ResetAll()
    wipe(ns.db.players)
    ns.db.streak = 0
    ns.db.bestStreak = 0
    ns.UI:Refresh()
    ns.Print("All entries and streaks have been erased.")
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
    text = "Erase every name in your Black Book, along with your kills and streaks?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.ResetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local HELP_LINES = {
    { "", "show or hide the window" },
    { "help", "list these commands" },
    { "announce", "toggle the chat messages for your kills and deaths" },
    { "alerts", "toggle the warning when a listed player is nearby" },
    { "sound", "toggle the warning sound" },
    { "minimap", "show or hide the minimap button" },
    { "streak", "show your current and best kill streak" },
    { "test", "show a sample warning" },
    { "last", "explain how your last death was read" },
    { "reset", "erase all entries and streaks" },
}

local function PrintHelp()
    ns.Print("Commands (/bbook works too):")
    for _, line in ipairs(HELP_LINES) do
        local command = line[1] == "" and "/blackbook" or ("/blackbook " .. line[1])
        print(format("  |cffffd100%s|r - %s", command, line[2]))
    end
end

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
    elseif command == "streak" then
        ns.Print(format("Kill streak: %d. Best: %d.", ns.db.streak, ns.db.bestStreak))
    elseif command == "test" then
        ns.ShowAlert({ name = UnitName("player"), class = select(2, UnitClass("player")), kills = 2, deaths = 5, assists = 1 })
    elseif command == "reset" then
        StaticPopup_Show("BLACKBOOK_RESET")
    elseif command == "last" then
        PrintLastRecap()
    elseif command == "help" then
        PrintHelp()
    else
        ns.Print(format("Unknown command \"%s\". Type /blackbook help for a list of commands.", command))
    end
end

function BlackBook_OnAddonCompartmentClick()
    ns.UI:Toggle()
end

local function Migrate(db)
    if db.version < 2 then
        for _, entry in pairs(db.killers or {}) do
            entry.assists = entry.assists or 0
            entry.firstSeen = entry.firstSeen or entry.firstKill
            entry.lastSeen = entry.lastSeen or entry.lastKill
        end
    end

    -- Version 3 tracks your kills too: "count" became "deaths", and "lastKill" now means your kill.
    if db.version < 3 then
        if db.killers then
            db.players = db.killers
            db.killers = nil
        end
        for _, entry in pairs(db.players) do
            entry.deaths = entry.count or 0
            entry.lastDeath = entry.lastKill
            entry.kills = 0
            entry.count, entry.lastKill, entry.firstKill = nil, nil, nil
        end
    end

    db.version = DB_VERSION
end

local events = {}

function events.ADDON_LOADED(loadedName)
    if loadedName ~= addonName then
        return
    end
    BlackBookDB = BlackBookDB or {}
    MergeDefaults(BlackBookDB, defaults)
    Migrate(BlackBookDB)
    ns.db = BlackBookDB
end

function events.PLAYER_LOGIN()
    -- Remember any recap that already exists so a death from before login is not counted again.
    lastRecapIdentity = ReadLatestRecap()
end

function events.PLAYER_DEAD()
    if ns.db.streak > 0 then
        if ns.db.announce then
            ns.Print(format("Your kill streak of %d has ended.", ns.db.streak))
        end
        ns.db.streak = 0
        ns.UI:Refresh()
    end

    if IsInInstance() then
        return
    end
    ProcessDeath(1)
end

function events.PARTY_KILL(attackerGUID, targetGUID)
    attackerGUID, targetGUID = Readable(attackerGUID), Readable(targetGUID)
    if type(attackerGUID) ~= "string" or type(targetGUID) ~= "string" then
        return
    end
    if not targetGUID:find("^Player%-") or IsInInstance() then
        return
    end
    if attackerGUID ~= UnitGUID("player") and attackerGUID ~= UnitGUID("pet") then
        return
    end
    RecordKill(targetGUID)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    events[event](...)
end)
for event in pairs(events) do
    eventFrame:RegisterEvent(event)
end
