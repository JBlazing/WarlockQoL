local addonName, ns = ...

-- Soulstone module: one button, shown only inside a dungeon or raid, while
-- the soulstone is not on cooldown (30 min after you use one) and you are
-- alive. It has two modes:
--   * no soulstone in bags: Create Soulstone (needs the spell and a shard),
--   * soulstone in bags:    Use Soulstone on your current target.
-- Your click casts; the addon never casts by itself. The button is a secure
-- frame, so it only appears or disappears out of combat (any change during
-- combat is applied when combat ends). Settings: WarlockQoLDB.modules.soulstone.

local Soulstone = {}
ns.Soulstone = Soulstone

local mod = {
    name = "soulstone",
    title = "Soulstone Button",
    defaults = {
        point = nil,         -- dragged position
        cooldownUntil = nil, -- time() when the soulstone cooldown ends (our own tracking)
    },
}

-- Minor, Lesser, normal, Greater, Major.
local SOULSTONE_ITEMS = { 5232, 16892, 16893, 16895, 16896 }
-- Create Soulstone ranks, highest first.
local CREATE_SOULSTONE_SPELLS = { 20757, 20756, 20755, 20752, 693 }
-- Soulstone Resurrection (cast when you use a soulstone), each rank.
local SOULSTONE_USE_SPELLS = {
    [20707] = true, [20762] = true, [20763] = true, [20764] = true, [20765] = true,
}
local SOULSTONE_COOLDOWN = 30 * 60
local GCD_MAX = 1.5 -- item cooldowns this short are just the global cooldown

local DEFAULT_POINT = { "CENTER", "CENTER", 0, -140 }
local WIDTH, HEIGHT = 150, 24

local C = C_Container
local GetNumSlots = C and C.GetContainerNumSlots
local GetSlotInfo = C and C.GetContainerItemInfo
local FIRST_BAG = 0
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

local holder, button
local timerToken = 0

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------

local function ItemCount(id)
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not getCount then return 0 end
    return ns.Plain(getCount(id, false)) or 0
end

function Soulstone.BestSpell()
    for _, id in ipairs(CREATE_SOULSTONE_SPELLS) do
        if ns.KnowsSpell(id) then
            return id
        end
    end
    return nil
end

function Soulstone.InGroupInstance()
    if not IsInInstance then return false end
    local inInstance, instanceType = IsInInstance()
    inInstance, instanceType = ns.Plain(inInstance), ns.Plain(instanceType)
    return inInstance and (instanceType == "party" or instanceType == "raid") or false
end

-- Finds a soulstone in your bags. Returns the value for the secure "item"
-- attribute ("item:<id>", or "<bag> <slot>" for the name fallback) and the
-- item ID when known, or nil if you have none.
function Soulstone.FindSoulstone()
    for i = #SOULSTONE_ITEMS, 1, -1 do -- best rank first
        local id = SOULSTONE_ITEMS[i]
        if ItemCount(id) > 0 then
            return "item:" .. id, id
        end
    end
    -- Fallback in case Forever uses different item IDs (English names only).
    if GetNumSlots and GetSlotInfo then
        for bag = FIRST_BAG, LAST_BAG do
            local slots = ns.Plain(GetNumSlots(bag)) or 0
            for slot = 1, slots do
                local info = GetSlotInfo(bag, slot)
                local link = info and ns.Plain(info.hyperlink)
                if link and link:lower():find("soulstone", 1, true) then
                    return bag .. " " .. slot, info and ns.Plain(info.itemID)
                end
            end
        end
    end
    return nil
end

function Soulstone.HasSoulstone()
    return Soulstone.FindSoulstone() ~= nil
end

-- Seconds left on the soulstone cooldown, 0 if ready. Uses the client's
-- item cooldown when it reports one, and our own record of when you last
-- used a soulstone (kept across logouts) otherwise.
function Soulstone.CooldownLeft()
    local left = 0
    local getCD = (C and C.GetItemCooldown) or GetItemCooldown
    if getCD then
        local now = GetTime()
        for _, id in ipairs(SOULSTONE_ITEMS) do
            local start, duration = getCD(id)
            start, duration = ns.Plain(start), ns.Plain(duration)
            if start and duration and start > 0 and duration > GCD_MAX then
                left = math.max(left, start + duration - now)
            end
        end
    end
    local untilT = mod.db and mod.db.cooldownUntil
    if untilT then
        local mine = untilT - time()
        if mine > 0 then
            left = math.max(left, mine)
        else
            mod.db.cooldownUntil = nil
        end
    end
    return left
end

-- Returns the Create Soulstone spell to offer, or nil, plus the reason.
function Soulstone.Want()
    if not mod.db or not mod.db.enabled then return nil, "module off" end
    if not Soulstone.InGroupInstance() then return nil, "not in a dungeon or raid" end
    local left = Soulstone.CooldownLeft()
    if left > 0 then return nil, "on cooldown (" .. math.ceil(left / 60) .. " min left)", left end
    -- Have one: the button uses it.
    local item, itemID = Soulstone.FindSoulstone()
    if item then
        return { kind = "use", item = item, itemID = itemID }, "shown (use soulstone)"
    end
    -- None: the button creates one.
    local spell = Soulstone.BestSpell()
    if not spell then return nil, "Create Soulstone not known" end
    if ItemCount(ns.SHARD_ITEM_ID or 6265) < 1 then return nil, "no Soul Shard" end
    return { kind = "create", spell = spell }, "shown (create soulstone)"
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------

local function Anchor()
    holder:ClearAllPoints()
    local p = mod.db.point
    if p then
        holder:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        holder:SetPoint(DEFAULT_POINT[1], UIParent, DEFAULT_POINT[2], DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

-- Re-check once the cooldown runs out, so the button comes back on its own.
local function ScheduleRecheck(seconds)
    if not (C_Timer and C_Timer.After) or not seconds or seconds <= 0 then return end
    timerToken = timerToken + 1
    local token = timerToken
    C_Timer.After(seconds + 1, function()
        if token == timerToken then
            Soulstone.RequestUpdate()
        end
    end)
end

-- Out of combat only (secure button).
function Soulstone.Update()
    if not button or InCombatLockdown() then return end
    local action, _, cdLeft = Soulstone.Want()
    ScheduleRecheck(cdLeft)
    if not action then
        holder:Hide()
        return
    end
    button.kind = action.kind
    if action.kind == "use" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", action.item)
        button:SetAttribute("spell", nil)
        button.spellID, button.itemID = nil, action.itemID
        button:SetText("Use Soulstone")
    else
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", action.spell)
        button:SetAttribute("item", nil)
        button.spellID, button.itemID = action.spell, nil
        button:SetText("Create Soulstone")
    end
    holder:Show()
end

local updateQueued = false

function Soulstone.RequestUpdate()
    if not InCombatLockdown() then
        Soulstone.Update()
        return
    end
    if updateQueued then return end
    updateQueued = true
    ns.RunOutOfCombat(function()
        updateQueued = false
        Soulstone.Update()
    end, true)
end

-- Must be called out of combat.
local function Create()
    -- The holder's visibility driver hides the button while you are dead
    -- (run by the client, so it works in combat). The holder itself is
    -- shown/hidden by Update for everything else.
    holder = CreateFrame("Frame", "WarlockQoL_SoulstoneHolder", UIParent, "SecureHandlerStateTemplate")
    holder:SetSize(WIDTH, HEIGHT)
    holder:SetFrameStrata("MEDIUM")
    holder:SetMovable(true)
    holder:SetClampedToScreen(true)
    Anchor()
    holder:Hide()

    local dead = CreateFrame("Frame", nil, holder, "SecureHandlerStateTemplate")
    dead:SetAllPoints(holder)
    if RegisterStateDriver then
        RegisterStateDriver(dead, "visibility", "[@player,dead] hide; show")
    end

    local b = CreateFrame("Button", "WarlockQoL_SoulstoneButton", dead,
        "SecureActionButtonTemplate,BackdropTemplate")
    b:SetAllPoints(dead)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")

    if b.SetBackdrop then
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        b:SetBackdropColor(0.25, 0.10, 0.30, 0.9)
        b:SetBackdropBorderColor(0.75, 0.45, 0.95, 1)
    end

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", b, "LEFT", 4, 0)
    icon:SetTexture("Interface\\Icons\\Spell_Shadow_SoulGem")

    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetText("Create Soulstone")
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- Drag to move (out of combat; a drag does not count as a click).
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        if InCombatLockdown() then
            ns.Print("Can't move the soulstone button in combat.")
            return
        end
        holder:StartMoving()
        holder.moving = true
    end)
    b:SetScript("OnDragStop", function()
        if not holder.moving then return end
        holder.moving = false
        holder:StopMovingOrSizing()
        holder:SetUserPlaced(false)
        local point, _, relPoint, x, y = holder:GetPoint(1)
        mod.db.point = { point, relPoint, x, y }
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if self.kind == "use" then
            if self.itemID and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(self.itemID)
            else
                GameTooltip:AddLine("Use Soulstone")
            end
            GameTooltip:AddLine("Click: use your soulstone on your current target.", 0.6, 0.6, 0.6, true)
        else
            if self.spellID and GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(self.spellID)
            else
                GameTooltip:AddLine("Create Soulstone")
            end
            GameTooltip:AddLine("You have no soulstone. Uses one Soul Shard.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:AddLine("Drag: move this button.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button = b
    Soulstone.Update()
end

---------------------------------------------------------------------------
-- Module wiring
---------------------------------------------------------------------------

local function OnSpellSucceeded(unit, castGUID, spellID)
    spellID = ns.Plain(spellID)
    if spellID and SOULSTONE_USE_SPELLS[spellID] then
        mod.db.cooldownUntil = time() + SOULSTONE_COOLDOWN
        Soulstone.RequestUpdate()
    end
end

-- Core.lua only calls this for Warlocks.
function mod:OnEnable()
    ns.RunOutOfCombat(Create, true)
    ns.On("PLAYER_ENTERING_WORLD", Soulstone.RequestUpdate)
    ns.On("ZONE_CHANGED_NEW_AREA", Soulstone.RequestUpdate)
    ns.On("BAG_UPDATE_DELAYED", Soulstone.RequestUpdate)
    ns.On("BAG_UPDATE_COOLDOWN", Soulstone.RequestUpdate)
    ns.On("SPELLS_CHANGED", Soulstone.RequestUpdate)
    ns.On("UNIT_SPELLCAST_SUCCEEDED", OnSpellSucceeded, "player")
end

-- /wqol soulstone on | off applies immediately.
function mod:OnToggle()
    ns.RunOutOfCombat(Soulstone.Update)
end

function mod:Probe()
    local _, reason = Soulstone.Want()
    ns.Print("Soulstone: best Create Soulstone " .. ns.Show(Soulstone.BestSpell())
        .. "  in dungeon/raid " .. (Soulstone.InGroupInstance() and "yes" or "no")
        .. "  soulstone in bags " .. (Soulstone.HasSoulstone() and "yes" or "no")
        .. "  cooldown left " .. math.ceil(Soulstone.CooldownLeft()) .. "s"
        .. "  -> " .. reason)
end

mod.commands = {
    status = {
        help = "explain why the soulstone button is or is not showing",
        run = function()
            local _, reason = Soulstone.Want()
            ns.Print("Soulstone button: " .. reason .. ".")
        end,
    },
    reset = {
        help = "move the soulstone button back to its default spot",
        run = function()
            mod.db.point = nil
            ns.RunOutOfCombat(function()
                if holder then Anchor() end
                ns.Print("Soulstone button position reset.")
            end)
        end,
    },
}

ns.RegisterModule(mod)
