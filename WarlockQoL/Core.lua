local addonName, ns = ...

-- Core: saved variables, one shared event frame, module registry, slash
-- commands. Feature files in Modules\ call ns.RegisterModule.

local PREFIX = "|cff9482c9Warlock QoL:|r "

function ns.Print(msg)
    print(PREFIX .. msg)
end

-- Secret values (Midnight addon disarmament) look like normal numbers,
-- strings or booleans but throw on compare, concat or arithmetic.
function ns.IsSecret(v)
    if issecretvalue then
        return issecretvalue(v) == true
    end
    return false
end

-- Returns v if it is safe to inspect, otherwise nil.
function ns.Plain(v)
    if v == nil or ns.IsSecret(v) then
        return nil
    end
    return v
end

function ns.Show(v)
    if v == nil then return "nil" end
    if ns.IsSecret(v) then return "<secret>" end
    return tostring(v)
end

-- True if the player knows the spell. A secret answer counts as unknown.
function ns.KnowsSpell(id)
    if IsPlayerSpell and ns.Plain(IsPlayerSpell(id)) then
        return true
    end
    if IsSpellKnown and ns.Plain(IsSpellKnown(id)) then
        return true
    end
    return false
end

function ns.BuildString()
    local version, build = GetBuildInfo()
    return ns.Show(version) .. "." .. ns.Show(build)
end

---------------------------------------------------------------------------
-- Events: one frame. handlers[event] holds the listeners for that event.
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end)

-- ns.On(event, fn)            normal event
-- ns.On(event, fn, "player")  unit event, filtered by the client
function ns.On(event, fn, unit)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if unit then
            eventFrame:RegisterUnitEvent(event, unit)
        else
            eventFrame:RegisterEvent(event)
        end
    end
    list[#list + 1] = fn
end

---------------------------------------------------------------------------
-- Combat queue: work on protected frames (secure buttons, and frames they
-- are anchored to) waits here until PLAYER_REGEN_ENABLED.
---------------------------------------------------------------------------

local combatQueue = {}

function ns.RunOutOfCombat(fn, quiet)
    if InCombatLockdown() then
        combatQueue[#combatQueue + 1] = fn
        if not quiet then
            ns.Print("In combat. That will happen when combat ends.")
        end
    else
        fn()
    end
end

-- Registered first, so the queue runs before module combat-end listeners.
ns.On("PLAYER_REGEN_ENABLED", function()
    local queue = combatQueue
    combatQueue = {}
    for i = 1, #queue do
        queue[i]()
    end
end)

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------

ns.modules = {}
local moduleOrder = {}

-- mod = { name = "key", title = "Shown name", defaults = {...},
--         OnEnable = function(mod) end,
--         commands = { sub = { help = "...", run = function(mod, arg) end } },
--         -- or, for a module with its own parser:
--         slash = function(mod, rest) end, slashHint = "...",
--         reloadOnToggle = true }  -- on/off needs /reload
function ns.RegisterModule(mod)
    ns.modules[mod.name] = mod
    moduleOrder[#moduleOrder + 1] = mod
end

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = v
        end
    end
end

ns.On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    if type(WarlockQoLDB) ~= "table" then
        WarlockQoLDB = {}
    end
    if type(WarlockQoLDB.modules) ~= "table" then
        WarlockQoLDB.modules = {}
    end
    for _, mod in ipairs(moduleOrder) do
        local saved = WarlockQoLDB.modules[mod.name]
        if type(saved) ~= "table" then
            saved = {}
            WarlockQoLDB.modules[mod.name] = saved
        end
        ApplyDefaults(saved, mod.defaults or {})
        if saved.enabled == nil then
            saved.enabled = true
        end
        mod.db = saved
    end
    ns.rootDB = WarlockQoLDB
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.rootDB then return end
    local _, classFile = UnitClass("player")
    if not ns.IsSecret(classFile) and classFile ~= "WARLOCK" then
        ns.isWarlock = false
        return
    end
    ns.isWarlock = true
    for _, mod in ipairs(moduleOrder) do
        if mod.OnEnable then
            mod:OnEnable()
        end
    end
end)

---------------------------------------------------------------------------
-- Capability probe
---------------------------------------------------------------------------

local function Has(v)
    return v and "yes" or "NO"
end

local function Probe()
    local version, build, _, interface = GetBuildInfo()
    ns.Print("build " .. ns.Show(version) .. "." .. ns.Show(build)
        .. "  interface " .. ns.Show(interface))
    ns.Print("WOW_PROJECT_ID " .. ns.Show(WOW_PROJECT_ID)
        .. "  MAINLINE " .. ns.Show(WOW_PROJECT_MAINLINE)
        .. "  CLASSIC " .. ns.Show(WOW_PROJECT_CLASSIC)
        .. "  CAMELOT " .. ns.Show(WOW_PROJECT_CAMELOT))
    ns.Print("issecretvalue " .. Has(issecretvalue)
        .. "  C_ChatInfo.SendChatMessage " .. Has(C_ChatInfo and C_ChatInfo.SendChatMessage)
        .. "  SendChatMessage " .. Has(SendChatMessage))
    ns.Print("IsInRaid " .. ns.Show(IsInRaid and IsInRaid())
        .. "  IsInGroup " .. ns.Show(IsInGroup and IsInGroup())
        .. "  UnitName(target) " .. ns.Show(UnitName("target")))
    for _, mod in ipairs(moduleOrder) do
        if mod.Probe then
            mod:Probe()
        end
    end
end

---------------------------------------------------------------------------
-- Slash commands: /wqol <module> <command> [arg]
---------------------------------------------------------------------------

local function PrintHelp()
    ns.Print("/wqol probe  print API capability info for this build")
    for _, mod in ipairs(moduleOrder) do
        ns.Print((mod.title or mod.name) .. (mod.db and mod.db.enabled and "" or "  |cffff5555(off)|r"))
        ns.Print("  /wqol " .. mod.name .. " on | off")
        if mod.slash then
            ns.Print("  /wqol " .. mod.name .. " help  " .. (mod.slashHint or "list commands"))
        end
        if mod.commands then
            for sub, c in pairs(mod.commands) do
                ns.Print("  /wqol " .. mod.name .. " " .. sub .. "  " .. (c.help or ""))
            end
        end
    end
end

SLASH_WARLOCKQOL1 = "/wqol"
SlashCmdList.WARLOCKQOL = function(msg)
    if not ns.rootDB then return end
    msg = (msg or ""):match("^%s*(.-)%s*$")
    local first, rest = msg:match("^(%S*)%s*(.*)$")
    first = first:lower()

    if first == "probe" then
        Probe()
        return
    end

    local mod = ns.modules[first]
    if not mod then
        PrintHelp()
        return
    end

    local sub, arg = rest:match("^(%S*)%s*(.*)$")
    sub = sub:lower()
    if sub == "on" or sub == "off" then
        mod.db.enabled = (sub == "on")
        ns.Print((mod.title or mod.name) .. (mod.db.enabled and " enabled." or " disabled.")
            .. (mod.reloadOnToggle and " Type /reload to apply." or ""))
        if mod.OnToggle then
            mod:OnToggle()
        end
        return
    end
    if mod.slash then
        mod:slash(rest)
        return
    end
    local c = mod.commands and mod.commands[sub]
    if c then
        c.run(mod, arg)
    else
        PrintHelp()
    end
end
