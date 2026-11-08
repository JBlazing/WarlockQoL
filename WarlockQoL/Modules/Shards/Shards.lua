local addonName, ns = ...

-- Soul Shards module: shard counter with a cap, auto-delete of extras,
-- and Create Healthstone button. (The demon bar is its own module,
-- Modules\Pets.lua; it sits under this counter when the counter exists.)
-- Display: UI.lua. Trimming + healthstone: Trim.lua.
-- Settings live in WarlockQoLDB.modules.shards, exposed as ns.shardDB.

ns.SHARD_ITEM_ID = 6265 -- Soul Shard (bag item); overridable

local Print = ns.Print

local mod = {
    name = "shards",
    title = "Soul Shards",
    slashHint = "or /sscap",
    reloadOnToggle = true,
    defaults = {
        cap = 20,             -- keep this many shards; extras are deleted
        nearOffset = 2,       -- turn yellow this many shards before the cap
        autoDelete = true,    -- delete extras whenever bags change
        sound = true,
        locked = false,
        hidden = false,
        point = nil,
        blockedOnBuild = nil, -- set if the client blocked auto-delete on a build
        shardItemID = 6265,   -- override with /sscap item <id>
        forceMode = nil,      -- nil = detect, or "item" / "power" (/sscap mode)
    },
}

local function SafeNumber(v)
    if v == nil or ns.IsSecret(v) or type(v) ~= "number" then
        return nil
    end
    return v
end

---------------------------------------------------------------------------
-- Shard source: bag item (classic-style) or Enum.PowerType.SoulShards
-- (modern-style). Probed at login; not assumed.
---------------------------------------------------------------------------

local function ShardPowerType()
    if Enum and Enum.PowerType and Enum.PowerType.SoulShards then
        return Enum.PowerType.SoulShards
    end
    return nil
end

local function HasItemCount()
    return ((C_Item and C_Item.GetItemCount) or GetItemCount) and true or false
end

local function DetectMode()
    local forced = ns.shardDB.forceMode
    if forced == "item" and HasItemCount() then
        return "item"
    elseif forced == "power" and ShardPowerType() then
        return "power"
    end
    local pt = ShardPowerType()
    if pt and UnitPowerMax then
        local max = SafeNumber(UnitPowerMax("player", pt))
        if max and max > 0 then
            return "power"
        end
    end
    if HasItemCount() then
        return "item"
    end
    return nil
end

function ns.ReadShards()
    if ns.mode == "power" then
        local pt = ShardPowerType()
        return SafeNumber(UnitPower("player", pt)), SafeNumber(UnitPowerMax("player", pt))
    elseif ns.mode == "item" then
        local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
        return SafeNumber(getCount(ns.SHARD_ITEM_ID, false)), nil
    end
    return nil, nil
end

---------------------------------------------------------------------------
-- Refresh + alert
---------------------------------------------------------------------------

local function Alert(count, cap)
    local msg = "Soul Shards at cap (" .. count .. "/" .. cap .. ")"
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 0.58, 0.51, 0.79, 1)
    else
        Print(msg)
    end
    if ns.shardDB.sound and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING)
    end
end

function ns.Refresh()
    if not ns.display then return end
    local db = ns.shardDB
    local count, nativeMax = ns.ReadShards()
    local cap = nativeMax or db.cap

    if not count then
        ns.UpdateDisplay(nil, cap, "unknown")
        ns.Trim.UpdateButton()
        return
    end

    local state
    if count >= cap then
        state = "full"
    elseif count >= cap - db.nearOffset then
        state = "near"
    else
        state = "ok"
    end
    ns.UpdateDisplay(count, cap, state)

    if state == "full" then
        if not ns.alerted then
            ns.alerted = true
            Alert(count, cap)
        end
    else
        ns.alerted = false
    end
    ns.Trim.UpdateButton()
end

-- Shared by the slash command and the double-click editor.
-- Returns true if the cap was changed.
function ns.SetCap(n)
    n = tonumber(n)
    if not n then
        Print("Cap must be a number.")
        return false
    end
    n = math.floor(n)
    if n < 1 then
        Print("Cap must be at least 1.")
        return false
    end
    ns.shardDB.cap = n
    ns.alerted = false
    Print("Cap set to " .. n .. ". Shards above it are deleted now (out of combat).")
    if ns.mode == "power" then
        Print("Note: shards are a power bar on this client, so its native max is used and nothing is deleted.")
    end
    ns.Refresh()
    ns.Trim.Begin()
    return true
end

---------------------------------------------------------------------------
-- Enable: runs at PLAYER_LOGIN for Warlocks (Core.lua checks the class)
---------------------------------------------------------------------------

local function OnPowerChanged(unit, powerToken)
    if powerToken == "SOUL_SHARDS" then
        ns.Refresh()
    end
end

local function OnDeathChanged()
    ns.Trim.UpdateButton()
end

local function OnActionBlocked(blockedAddon, func)
    ns.Trim.OnActionBlocked(blockedAddon, func)
end

-- Drain Soul ranks 1-4. The module only starts once you know one of them.
local DRAIN_SOUL_IDS = { 1120, 8288, 8289, 11675 }

local function KnowsDrainSoul()
    for _, id in ipairs(DRAIN_SOUL_IDS) do
        if ns.KnowsSpell(id) then
            return true
        end
    end
    return false
end

local started = false
local Start

-- Core.lua only calls this for Warlocks.
function mod:OnEnable()
    if not self.db.enabled then return end
    ns.shardDB = self.db
    self.db.debug = nil -- removed setting
    ns.SHARD_ITEM_ID = self.db.shardItemID

    if KnowsDrainSoul() then
        Start(self)
        return
    end
    -- Not learned yet (low level): wait, and start as soon as it is.
    ns.On("SPELLS_CHANGED", function()
        if not started and KnowsDrainSoul() then
            ns.RunOutOfCombat(function()
                if not started then
                    Start(mod)
                end
            end, true)
        end
    end)
end

Start = function(self)
    started = true
    ns.mode = DetectMode()
    if not ns.mode then
        Print("No Soul Shard source found on this client. Type /wqol probe and share the output.")
        return
    end

    -- If this exact build blocked auto-delete before, don't trip it again.
    if self.db.blockedOnBuild and self.db.blockedOnBuild == ns.BuildString() then
        ns.autoBlocked = true
    else
        self.db.blockedOnBuild = nil
    end

    ns.display = ns.CreateDisplay(self.db)

    if ns.mode == "power" then
        ns.On("UNIT_POWER_UPDATE", OnPowerChanged, "player")
        ns.On("UNIT_MAXPOWER", OnPowerChanged, "player")
    else
        ns.trimButton = ns.CreateTrimButton(ns.display)
        ns.RunOutOfCombat(function()
            ns.healthstoneButton = ns.CreateHealthstoneButton(ns.display)
            ns.Trim.UpdateButton()
        end)
        ns.On("PLAYER_DEAD", OnDeathChanged)
        ns.On("PLAYER_ALIVE", OnDeathChanged)   -- also fires on release to ghost
        ns.On("PLAYER_UNGHOST", OnDeathChanged)
        ns.On("ADDON_ACTION_BLOCKED", OnActionBlocked)
        ns.On("ADDON_ACTION_FORBIDDEN", OnActionBlocked)
    end
    -- The demon bar (separate module) moves under the counter.
    if ns.Pets then
        ns.Pets.AttachTo(ns.display)
    end

    ns.On("PLAYER_REGEN_ENABLED", function()
        ns.Trim.OnRegenEnabled()
    end)
    ns.On("BAG_UPDATE_DELAYED", function() -- shards and demon reagents
        ns.Refresh()
        ns.Trim.OnBags()
    end)
    ns.On("PLAYER_ENTERING_WORLD", function()
        ns.Refresh()
        ns.Trim.Begin()
    end)
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Probe lines (shown by /wqol probe)
---------------------------------------------------------------------------

local function Has(v)
    return v and "yes" or "NO"
end

function mod:Probe()
    Print("Shards: C_Item.GetItemCount " .. Has(C_Item and C_Item.GetItemCount)
        .. "  GetItemCount " .. Has(GetItemCount))
    local pt = ShardPowerType()
    Print("Shards: Enum.PowerType.SoulShards " .. ns.Show(pt)
        .. "  UnitPowerMax " .. (pt and ns.Show(UnitPowerMax("player", pt)) or "n/a"))
    local C = C_Container
    Print("Shards: C_Container GetContainerNumSlots " .. Has(C and C.GetContainerNumSlots)
        .. "  GetContainerItemID " .. Has(C and C.GetContainerItemID)
        .. "  GetContainerItemInfo " .. Has(C and C.GetContainerItemInfo))
    Print("Shards: PickupContainerItem " .. Has(C and C.PickupContainerItem)
        .. "  SplitContainerItem " .. Has(C and C.SplitContainerItem)
        .. "  DeleteCursorItem " .. Has(DeleteCursorItem)
        .. "  GetCursorInfo " .. Has(GetCursorInfo))
    Print("Shards: IsPlayerSpell " .. Has(IsPlayerSpell) .. "  IsSpellKnown " .. Has(IsSpellKnown)
        .. "  best Create Healthstone " .. ns.Show(ns.Trim.BestHealthstoneSpell())
        .. "  healthstone in bags " .. (ns.Trim.HasHealthstone() and "yes" or "no"))
    if C_EventUtils and C_EventUtils.IsEventValid then
        Print("Shards: BAG_UPDATE_DELAYED valid " .. ns.Show(C_EventUtils.IsEventValid("BAG_UPDATE_DELAYED"))
            .. "  ADDON_ACTION_BLOCKED valid "
            .. ns.Show(C_EventUtils.IsEventValid("ADDON_ACTION_BLOCKED")))
    end
    Print("Shards: Drain Soul known " .. (KnowsDrainSoul() and "yes" or "no")
        .. "  module started " .. (started and "yes" or "no"))
    if ns.shardDB then
        Print("Shards: active mode " .. ns.Show(ns.mode)
            .. "  auto-delete " .. (ns.shardDB.autoDelete and "on" or "off")
            .. (ns.autoBlocked and " (blocked by client on this build)" or ""))
    else
        Print("Shards: module not active (disabled, or not a Warlock).")
    end
end

---------------------------------------------------------------------------
-- Slash commands: /wqol shards <command>, or the /sscap shortcut
---------------------------------------------------------------------------

local HELP = {
    "Double-click the shard display to type a new cap.",
    "/sscap <number>  set the cap; shards above it are deleted",
    "/sscap auto  toggle auto-delete of shards above the cap",
    "/sscap delete  delete one extra shard now (out of combat)",
    "/sscap near <number>  yellow warning this many before the cap",
    "/sscap lock | unlock  lock the display in place",
    "/sscap show | hide  toggle the display",
    "/sscap sound  toggle the alert sound",
    "/sscap pets  toggle the demon bar (same as /wqol pets on | off)",
    "/sscap reset  move the display back to default",
    "/sscap status  explain why shards are or are not being trimmed",
    "/sscap mode auto | item | power  how shards are read (then /reload)",
    "/sscap item <id>  set the Soul Shard item ID (then /reload)",
    "/wqol shards on | off  turn the whole module on or off (then /reload)",
    "/wqol probe  print API capability info for this build",
    "(/wqol shards <command> works the same as /sscap <command>)",
}

function mod:slash(msg)
    local db = ns.shardDB
    if not db then
        Print("Soul Shards module is not active (disabled, or not a Warlock).")
        return
    end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not started and msg ~= "probe" then
        Print("Soul Shards starts once you learn Drain Soul.")
        return
    end
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    local n = tonumber(cmd)

    if n then
        ns.SetCap(n)
        return
    elseif cmd == "auto" then
        db.autoDelete = not db.autoDelete
        Print("Auto-delete " .. (db.autoDelete and "on." or "off."))
        if db.autoDelete and ns.autoBlocked then
            Print("The client blocked auto-delete on this build, so it stays off. Use the button or /sscap delete.")
        end
    elseif cmd == "delete" then
        ns.Trim.DeleteManual()
    elseif cmd == "near" and tonumber(arg) then
        db.nearOffset = math.max(0, math.floor(tonumber(arg)))
        Print("Near warning at cap - " .. db.nearOffset .. ".")
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        Print(db.locked and "Display locked." or "Display unlocked.")
    elseif cmd == "show" or cmd == "hide" then
        db.hidden = (cmd == "hide")
        ns.RunOutOfCombat(function()
            if ns.display then
                if db.hidden then ns.display:Hide() else ns.display:Show() end
            end
            ns.Trim.UpdateButton()
        end)
    elseif cmd == "pets" then
        -- Shortcut for /wqol pets on | off (the demon bar is its own module).
        local pets = ns.modules.pets
        if pets and pets.db then
            pets.db.enabled = not pets.db.enabled
            Print("Demon Bar " .. (pets.db.enabled and "on." or "off."))
            pets:OnToggle()
        end
        return
    elseif cmd == "sound" then
        db.sound = not db.sound
        Print("Alert sound " .. (db.sound and "on." or "off."))
    elseif cmd == "reset" then
        db.point = nil
        ns.RunOutOfCombat(function()
            if ns.display then ns.RestorePosition(ns.display, db) end
            Print("Position reset.")
        end)
    elseif cmd == "status" then
        if not ns.mode then
            Print("No Soul Shard source found on this client.")
            return
        end
        ns.Trim.Status()
        return
    elseif cmd == "mode" and (arg == "auto" or arg == "item" or arg == "power") then
        db.forceMode = (arg ~= "auto") and arg or nil
        Print("Shard mode set to " .. arg .. ". Type /reload to apply.")
        return
    elseif cmd == "item" and tonumber(arg) then
        db.shardItemID = math.floor(tonumber(arg))
        Print("Soul Shard item ID set to " .. db.shardItemID .. ". Type /reload to apply.")
        return
    elseif cmd == "probe" then
        self:Probe()
        return
    else
        for _, line in ipairs(HELP) do
            Print(line)
        end
        return
    end
    ns.Refresh()
    ns.Trim.Begin()
end

SLASH_WARLOCKQOLSHARDS1 = "/sscap"
SlashCmdList.WARLOCKQOLSHARDS = function(msg)
    mod:slash(msg)
end

ns.RegisterModule(mod)
