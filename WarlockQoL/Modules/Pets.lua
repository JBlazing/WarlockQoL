local addonName, ns = ...

-- Demon Bar module: when you have no pet, a button appears. Click it to
-- expand a row with each demon you know; click a demon to summon it. Your
-- click casts; the addon never casts by itself. Independent of the Soul
-- Shards module: it shows as soon as you know any summon. It sits under the
-- shard counter when that exists, otherwise at its own default spot.
--
-- Showing the bar uses a visibility state driver (no pet and not dead),
-- which the client runs securely, so it appears even in combat when your
-- pet dies. Expanding/collapsing the row only works out of combat; the
-- open/closed state is saved, so a row left open stays usable in combat.
-- Settings live in WarlockQoLDB.modules.pets, exposed as ns.petDB.

local Pets = {}
ns.Pets = Pets

local mod = {
    name = "pets",
    title = "Demon Bar",
    defaults = {
        expanded = false, -- demon row open (saved so it stays open in combat)
        point = nil,      -- dragged position, used only while not under the counter
    },
}

-- Summon spells. Only the ones you know are shown. Entries with a reagent
-- are shown only while that item is in your bags.
local PET_SPELLS = {
    { id = 688,   name = "Imp",        icon = "Interface\\Icons\\Spell_Shadow_SummonImp" },
    { id = 697,   name = "Voidwalker", icon = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker" },
    { id = 712,   name = "Succubus",   icon = "Interface\\Icons\\Spell_Shadow_SummonSuccubus" },
    { id = 691,   name = "Felhunter",  icon = "Interface\\Icons\\Spell_Shadow_SummonFelHunter" },
    { id = 30146, name = "Felguard",   icon = "Interface\\Icons\\Spell_Shadow_SummonFelGuard" },
    { id = 1122,  name = "Infernal",   icon = "Interface\\Icons\\Spell_Shadow_SummonInfernal",
      reagent = 5565,  reagentName = "Infernal Stone" },
    { id = 18540, name = "Doomguard (Ritual of Doom)", icon = "Interface\\Icons\\Spell_Shadow_AntiMagicShell",
      reagent = 16583, reagentName = "Demonic Figurine" },
}

local function HasReagent(itemID)
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not getCount then
        return false
    end
    local n = ns.Plain(getCount(itemID, false))
    return n ~= nil and n > 0
end

-- Demon bar button uses the Fel Domination icon. Left-click opens the
-- list; right-click casts Fel Domination if you know it.
local TOGGLE_ICON = { id = 18708, icon = "Interface\\Icons\\Spell_Nature_RemoveCurse" }

local BUTTON_SIZE = 30
local GAP = 3
-- Hidden while you are dead or mounted; otherwise shown only when you have
-- no pet. "@player" matters: a bare [dead] would test your target instead.
-- Flight paths have no macro condition, so Layout handles those (below).
local VISIBILITY = "[@player,dead] hide; [mounted] hide; [nopet] show; hide"

local function OnTaxi()
    return UnitOnTaxi and ns.Plain(UnitOnTaxi("player")) and true or false
end

-- Used when there is no shard counter to sit under.
local DEFAULT_POINT = { "CENTER", UIParent, "CENTER", 0, -215 }

local container, toggle
local flyout = {}
local driverOn = false
local attachedTo = nil

local function SpellIcon(entry)
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = ns.Plain(C_Spell.GetSpellTexture(entry.id))
        if tex then
            return tex
        end
    end
    return entry.icon
end

function Pets.Known()
    local list = {}
    for _, entry in ipairs(PET_SPELLS) do
        if ns.KnowsSpell(entry.id) and (not entry.reagent or HasReagent(entry.reagent)) then
            list[#list + 1] = entry
        end
    end
    return list
end

local function AddBorder(b)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
end

local function ShowSpellTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if self.spellID and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(self.spellID)
    else
        GameTooltip:AddLine(self.label or "Summon")
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

local function CreateFlyoutButton(i)
    local b = CreateFrame("Button", "WarlockQoL_Pet" .. i, container, "SecureActionButtonTemplate")
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    if i == 1 then
        b:SetPoint("LEFT", toggle, "RIGHT", GAP + 2, 0)
    else
        b:SetPoint("LEFT", flyout[i - 1], "RIGHT", GAP, 0)
    end
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    b.icon = icon
    AddBorder(b)
    b:SetScript("OnEnter", ShowSpellTooltip)
    b:SetScript("OnLeave", HideTooltip)
    b:Hide()
    flyout[i] = b
    return b
end

-- Rebuild the row and the visibility driver. Out of combat only.
function Pets.Layout()
    if not container or InCombatLockdown() then return end
    local db = ns.petDB
    local known = Pets.Known()

    -- Only shown when you know at least one summonable demon, and never on
    -- a flight path.
    if #known == 0 or not db.enabled or OnTaxi() then
        if driverOn then
            UnregisterStateDriver(container, "visibility")
            driverOn = false
        end
        container:Hide()
        return
    end

    toggle.icon:SetTexture(SpellIcon(TOGGLE_ICON))
    -- Right-click casts Fel Domination, only if you know it.
    toggle.felDomKnown = ns.KnowsSpell(TOGGLE_ICON.id)
    if toggle.felDomKnown then
        toggle:SetAttribute("type2", "spell")
        toggle:SetAttribute("spell2", TOGGLE_ICON.id)
    else
        toggle:SetAttribute("type2", nil)
        toggle:SetAttribute("spell2", nil)
    end
    for i, entry in ipairs(known) do
        local b = flyout[i] or CreateFlyoutButton(i)
        b:SetAttribute("spell", entry.id)
        b.spellID = entry.id
        b.label = "Summon " .. entry.name
        b.icon:SetTexture(SpellIcon(entry))
        if db.expanded then b:Show() else b:Hide() end
    end
    for i = #known + 1, #flyout do
        flyout[i]:Hide()
    end
    toggle.arrow:SetText(db.expanded and "<" or ">")

    if not driverOn then
        RegisterStateDriver(container, "visibility", VISIBILITY)
        driverOn = true
    end
end

-- Gap under the shard counter: room for the Create Healthstone / Delete
-- extra row when one of those buttons is showing, otherwise directly under.
local ROW_GAP = -30
local NO_ROW_GAP = -2
local rowShown = false

local function Anchor()
    container:ClearAllPoints()
    local p = ns.petDB and ns.petDB.point
    if attachedTo then
        container:SetPoint("TOPLEFT", attachedTo, "BOTTOMLEFT", 0, rowShown and ROW_GAP or NO_ROW_GAP)
    elseif p then
        container:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        container:SetPoint(DEFAULT_POINT[1], DEFAULT_POINT[2], DEFAULT_POINT[3],
            DEFAULT_POINT[4], DEFAULT_POINT[5])
    end
end

-- Called by the Soul Shards module whenever its button row changes. The bar
-- is protected, so a change in combat is applied once combat ends.
local anchorQueued = false

function Pets.SetButtonRowShown(shown)
    shown = shown and true or false
    if shown == rowShown then return end
    rowShown = shown
    if not container or not attachedTo then return end
    if not InCombatLockdown() then
        Anchor()
        return
    end
    if anchorQueued then return end
    anchorQueued = true
    ns.RunOutOfCombat(function()
        anchorQueued = false
        if container then Anchor() end
    end, true)
end

-- Dragging: only while the bar stands alone (you don't know Drain Soul,
-- so there is no shard counter to follow), and never in combat because
-- the bar is a protected frame.
function Pets.CanDrag()
    return attachedTo == nil
end

local function OnDragStart()
    if not Pets.CanDrag() then
        return
    end
    if InCombatLockdown() then
        ns.Print("Can't move the demon bar in combat.")
        return
    end
    container:StartMoving()
    container.moving = true
end

local function OnDragStop()
    if not container.moving then
        return
    end
    container.moving = false
    container:StopMovingOrSizing()
    -- Position is kept in our settings, not the client's layout cache.
    container:SetUserPlaced(false)
    local point, _, relPoint, x, y = container:GetPoint(1)
    ns.petDB.point = { point, relPoint, x, y }
end

function Pets.ResetPosition()
    ns.petDB.point = nil
    ns.RunOutOfCombat(function()
        if container then Anchor() end
        ns.Print("Demon bar position reset.")
    end)
end

-- Called by the Soul Shards module when its counter exists. The bar is a
-- protected frame, so re-anchoring waits for combat to end.
function Pets.AttachTo(display)
    attachedTo = display
    ns.RunOutOfCombat(function()
        if container then Anchor() end
    end, true)
end

-- Must be called out of combat.
function Pets.Create()
    container = CreateFrame("Frame", "WarlockQoL_PetBar", UIParent, "SecureHandlerStateTemplate")
    container:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    Anchor()
    container:Hide()

    -- Secure so right-click can cast Fel Domination (type2/spell2). Left
    -- click has no secure action; the hooked insecure handler below opens
    -- or closes the demon list.
    toggle = CreateFrame("Button", "WarlockQoL_PetToggle", container,
        "SecureActionButtonTemplate,BackdropTemplate")
    toggle:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    toggle:RegisterForClicks("AnyUp", "AnyDown")
    toggle:SetPoint("LEFT", container, "LEFT", 0, 0)
    local icon = toggle:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    toggle.icon = icon
    local arrow = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    arrow:SetPoint("LEFT", toggle, "RIGHT", 0, 0)
    toggle.arrow = arrow
    AddBorder(toggle)

    -- Drag the bar by its main button (a drag does not count as a click).
    toggle:RegisterForDrag("LeftButton")
    toggle:SetScript("OnDragStart", OnDragStart)
    toggle:SetScript("OnDragStop", OnDragStop)

    -- Clicks are registered for down and up (the secure cast follows the
    -- ActionButtonUseKeyDown setting), so toggle only on the release.
    toggle:HookScript("OnClick", function(_, button, down)
        if button ~= "LeftButton" or down then
            return
        end
        if InCombatLockdown() then
            ns.Print("Can't open or close the demon list in combat. Leave it open and it stays usable in combat.")
            return
        end
        ns.petDB.expanded = not ns.petDB.expanded
        Pets.Layout()
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("No demon summoned")
        GameTooltip:AddLine(ns.petDB.expanded and "Left-click: hide the demon list."
            or "Left-click: show the demons you know.", 0.6, 0.6, 0.6, true)
        if self.felDomKnown then
            GameTooltip:AddLine("Right-click: cast Fel Domination (next summon is instant).",
                0.6, 0.6, 0.6, true)
        end
        if Pets.CanDrag() then
            GameTooltip:AddLine("Drag: move the demon bar.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", HideTooltip)

    Pets.Layout()
end

-- Layout now, or once when combat ends (bag updates in combat would
-- otherwise queue many copies).
local layoutQueued = false

function Pets.RequestLayout()
    if not InCombatLockdown() then
        Pets.Layout()
        return
    end
    if layoutQueued then return end
    layoutQueued = true
    ns.RunOutOfCombat(function()
        layoutQueued = false
        Pets.Layout()
    end, true)
end

-- Module wiring --------------------------------------------------------

-- Core.lua only calls this for Warlocks.
function mod:OnEnable()
    ns.petDB = self.db
    -- One-time carry-over from when the bar was part of Soul Shards.
    if not self.db.migrated then
        local old = ns.rootDB and ns.rootDB.modules and ns.rootDB.modules.shards
        if old then
            if old.showPets == false then self.db.enabled = false end
            if old.petsExpanded ~= nil then self.db.expanded = old.petsExpanded end
            old.showPets, old.petsExpanded = nil, nil
        end
        self.db.migrated = true
    end

    ns.RunOutOfCombat(function()
        Pets.Create()
    end, true)
    -- Spells learned, or bags changed (reagents gained or used up).
    ns.On("SPELLS_CHANGED", Pets.RequestLayout)
    ns.On("BAG_UPDATE_DELAYED", Pets.RequestLayout)
    -- Flight paths take and give back control of your character.
    ns.On("PLAYER_CONTROL_LOST", function()
        Pets.RequestLayout()
        -- The taxi flag can lag the event slightly; check once more.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, Pets.RequestLayout)
        end
    end)
    ns.On("PLAYER_CONTROL_GAINED", Pets.RequestLayout)
end

-- /wqol pets on | off applies immediately.
function mod:OnToggle()
    ns.RunOutOfCombat(Pets.Layout)
end

function mod:Probe()
    ns.Print("Pets: " .. Pets.ProbeLine())
end

mod.commands = {
    reset = {
        help = "move the demon bar back to its default spot (when not under the shard counter)",
        run = function()
            Pets.ResetPosition()
        end,
    },
}

ns.RegisterModule(mod)

function Pets.ProbeLine()
    local names = {}
    for _, entry in ipairs(Pets.Known()) do
        names[#names + 1] = entry.name .. " (" .. entry.id .. ")"
    end
    local reagents = {}
    for _, entry in ipairs(PET_SPELLS) do
        if entry.reagent and ns.KnowsSpell(entry.id) then
            reagents[#reagents + 1] = entry.reagentName .. " " .. (HasReagent(entry.reagent) and "yes" or "no")
        end
    end
    return "shown demons: " .. (#names > 0 and table.concat(names, ", ") or "none")
        .. (#reagents > 0 and ("  reagents: " .. table.concat(reagents, ", ")) or "")
        .. "  Fel Domination known " .. (ns.KnowsSpell(TOGGLE_ICON.id) and "yes" or "no")
        .. "  UnitOnTaxi " .. (UnitOnTaxi and ns.Show(UnitOnTaxi("player")) or "NO")
        .. "  RegisterStateDriver " .. (RegisterStateDriver and "yes" or "NO")
end
