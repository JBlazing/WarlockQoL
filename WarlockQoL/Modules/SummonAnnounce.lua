local addonName, ns = ...

-- Summon Announce: when you start Ritual of Summoning, tell the group who
-- you are summoning. Raid -> RAID, party -> PARTY.
-- It sends one message when you cast. It never casts anything itself.

-- Ritual of Summoning. Confirm on your build with "/wqol summon debug":
-- it prints the spell ID of each cast you start.
local RITUAL_IDS = {
    [698] = true,
}

local DEDUPE_SECONDS = 3   -- START and CHANNEL_START can both fire for one cast
local MAX_CHAT_LEN = 255

local mod = {
    name = "summon",
    title = "Summon Announce",
    defaults = {
        message = "Summoning {target} - please click the portal!",
        messageNoTarget = "Summoning - please click the portal!",
        debug = false,
    },
}

local lastAnnounce = 0

local function GroupChannel()
    -- Instance groups (dungeon finder style) have their own channel when
    -- you are not also in a normal group.
    if LE_PARTY_CATEGORY_INSTANCE and LE_PARTY_CATEGORY_HOME
        and ns.Plain(IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
        and not ns.Plain(IsInGroup(LE_PARTY_CATEGORY_HOME)) then
        return "INSTANCE_CHAT"
    end
    if ns.Plain(IsInRaid()) then
        return "RAID"
    end
    if ns.Plain(IsInGroup()) then
        return "PARTY"
    end
    return nil
end

-- Returns the label to put in the message, or nil if there is no target.
-- If the client hides the name, "%t" is used instead. The chat system may
-- replace it with your target's name, but that is NOT verified for messages
-- sent by an addon on Forever.
local function TargetLabel()
    local exists = UnitExists("target")
    if ns.IsSecret(exists) then
        return "%t"
    end
    if not exists then
        return nil
    end
    local name = UnitName("target")
    if name == nil or ns.IsSecret(name) then
        return "%t"
    end
    return name
end

local function BuildMessage()
    local label = TargetLabel()
    local msg
    if label then
        msg = (mod.db.message:gsub("{target}", function() return label end))
    else
        msg = mod.db.messageNoTarget
    end
    return msg:sub(1, MAX_CHAT_LEN)
end

local function SendChat(msg, channel)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then
        ns.Print("No chat API found on this client. Type /wqol probe and share the output.")
        return
    end
    send(msg, channel)
end

local function Announce()
    local msg = BuildMessage()
    local channel = GroupChannel()
    if not channel then
        ns.Print("Not in a group. Would have said: " .. msg)
        return
    end
    SendChat(msg, channel)
end

local function OnCastStart(unit, castGUID, spellID)
    if not mod.db.enabled then return end
    spellID = ns.Plain(spellID)
    if mod.db.debug then
        ns.Print("cast started, spellID " .. ns.Show(spellID))
    end
    if not spellID or not RITUAL_IDS[spellID] then return end

    local now = GetTime()
    if now - lastAnnounce < DEDUPE_SECONDS then return end
    lastAnnounce = now
    Announce()
end

function mod:OnEnable()
    ns.On("UNIT_SPELLCAST_START", OnCastStart, "player")
    ns.On("UNIT_SPELLCAST_CHANNEL_START", OnCastStart, "player")
end

function mod:Probe()
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(698)
    end
    ns.Print("Summon: C_Spell.GetSpellName(698) " .. ns.Show(name)
        .. "  (nil can just mean not cached yet)")
    if C_EventUtils and C_EventUtils.IsEventValid then
        ns.Print("Summon: UNIT_SPELLCAST_START valid "
            .. ns.Show(C_EventUtils.IsEventValid("UNIT_SPELLCAST_START"))
            .. "  UNIT_SPELLCAST_CHANNEL_START valid "
            .. ns.Show(C_EventUtils.IsEventValid("UNIT_SPELLCAST_CHANNEL_START")))
    end
end

mod.commands = {
    msg = {
        help = "<text>  set the message. {target} is replaced by the name.",
        run = function(self, arg)
            if arg == "" then
                ns.Print("Current: " .. self.db.message)
                return
            end
            self.db.message = arg
            ns.Print("Message set: " .. arg)
        end,
    },
    notarget = {
        help = "<text>  message used when you have no target",
        run = function(self, arg)
            if arg == "" then
                ns.Print("Current: " .. self.db.messageNoTarget)
                return
            end
            self.db.messageNoTarget = arg
            ns.Print("No-target message set: " .. arg)
        end,
    },
    test = {
        help = "preview the message and channel without sending it",
        run = function()
            ns.Print("Channel: " .. (GroupChannel() or "none (not in a group)"))
            ns.Print("Message: " .. BuildMessage())
        end,
    },
    debug = {
        help = "toggle printing the spell ID of each cast you start",
        run = function(self)
            self.db.debug = not self.db.debug
            ns.Print("Summon debug " .. (self.db.debug and "on." or "off."))
        end,
    },
}

ns.RegisterModule(mod)
