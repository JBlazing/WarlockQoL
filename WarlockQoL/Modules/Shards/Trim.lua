local addonName, ns = ...

-- Shard trimming: whenever your bags change (or you log in, or combat
-- ends) and you hold more bag Soul Shards than the cap, delete the extras.
-- Core.lua wires the events; this file holds the logic.
--
-- Safety rules:
--   * Never touches anything in combat. Work waits for PLAYER_REGEN_ENABLED.
--   * Never acts while the cursor holds something (you are moving items);
--     it simply tries again on the next bag update.
--   * Checks the cursor holds a Soul Shard (item 6265) before deleting;
--     anything else is put back with ClearCursor().
--   * Deletes one slot per bag update, so item locks settle in between.
--   * If a delete does not lower the count, it backs off for 30 seconds.
--   * If the client blocks the call (ADDON_ACTION_BLOCKED / FORBIDDEN),
--     auto-delete turns off for this build and the manual button appears.

local Trim = {}
ns.Trim = Trim

local PASS_SECONDS = 10      -- give up on a trim pass after this long
local BACKOFF_SECONDS = 30   -- wait this long after a delete that did nothing
local FIRST_BAG = 0
-- Includes the reagent bag slot on clients that have one.
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

local C = C_Container
local GetNumSlots = C and C.GetContainerNumSlots
local GetItemID = C and C.GetContainerItemID
local GetItemInfo = C and C.GetContainerItemInfo
local PickupItem = C and C.PickupContainerItem
local SplitItem = C and C.SplitContainerItem

local pendingCombat = false
local backoffUntil = 0
local pass = nil   -- { started, attempts, maxAttempts, deleted, lastExcess }

---------------------------------------------------------------------------
-- Healthstones: if you have none and know Create Healthstone, an extra
-- shard is spent on a healthstone (you click the button) instead of
-- being deleted.
---------------------------------------------------------------------------

-- Minor, Lesser, normal, Greater, Major, each with the two Improved
-- Healthstone talent variants.
local HEALTHSTONE_ITEMS = {
    5512, 19004, 19005,
    5511, 19006, 19007,
    5509, 19008, 19009,
    5510, 19010, 19011,
    9421, 19012, 19013,
}

-- Create Healthstone ranks, highest first.
local CREATE_HEALTHSTONE_SPELLS = { 11730, 11729, 5699, 6202, 6201 }

local KnowsSpell = ns.KnowsSpell -- defined in Core.lua

function Trim.BestHealthstoneSpell()
    for _, id in ipairs(CREATE_HEALTHSTONE_SPELLS) do
        if KnowsSpell(id) then
            return id
        end
    end
    return nil
end

function Trim.HasHealthstone()
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    if getCount then
        for _, id in ipairs(HEALTHSTONE_ITEMS) do
            local n = ns.Plain(getCount(id, false))
            if n and n > 0 then
                return true
            end
        end
    end
    -- Fallback in case Forever uses different item IDs (English names only).
    if GetNumSlots and GetItemInfo then
        for bag = FIRST_BAG, LAST_BAG do
            local slots = ns.Plain(GetNumSlots(bag)) or 0
            for slot = 1, slots do
                local info = GetItemInfo(bag, slot)
                local link = info and ns.Plain(info.hyperlink)
                if link and link:lower():find("healthstone", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

-- Returns the Create Healthstone spell ID to offer, or nil.
function Trim.WantHealthstone()
    if ns.mode ~= "item" or Trim.HasHealthstone() then
        return nil
    end
    return Trim.BestHealthstoneSpell()
end

function Trim.Supported()
    if GetNumSlots and GetItemID and GetItemInfo and PickupItem
        and DeleteCursorItem and GetCursorInfo and ClearCursor then
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Bag work
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Soul Shard bags (Soul Pouch, Felcloth Bag, Core Felcloth Bag, ...):
-- while one is equipped, the cap is the total size of the soul bags and
-- extras are only ever deleted from regular bags.
---------------------------------------------------------------------------

local SOUL_BAG_FAMILY = 4   -- bagFamily bit for Soul Shard bags
local GetFreeSlots = (C and C.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local band = bit and bit.band

local function IsSoulBag(bag)
    -- The backpack (bag 0) can never be a soul bag.
    if bag < 1 or not GetFreeSlots then return false end
    local _, family = GetFreeSlots(bag)
    family = ns.Plain(family)
    if type(family) ~= "number" or family <= 0 then return false end
    if band then
        return band(family, SOUL_BAG_FAMILY) ~= 0
    end
    return family % (SOUL_BAG_FAMILY * 2) >= SOUL_BAG_FAMILY
end

-- Total slots in equipped Soul Shard bags (0 if none).
function Trim.SoulBagSlots()
    if not GetNumSlots then return 0 end
    local total = 0
    for bag = 1, LAST_BAG do
        if IsSoulBag(bag) then
            total = total + (ns.Plain(GetNumSlots(bag)) or 0)
        end
    end
    return total
end

-- The cap in use: soul bag size while one is equipped, else the set cap.
-- Second return is true when the soul bag size is being used.
function ns.ShardCap()
    if ns.mode == "item" then
        local soul = Trim.SoulBagSlots()
        if soul > 0 then
            return soul, true
        end
    end
    return ns.shardDB.cap, false
end

function Trim.Excess()
    if ns.mode ~= "item" or not ns.shardDB then
        return 0
    end
    local count = ns.ReadShards()
    if not count then
        return 0
    end
    local excess = count - ns.ShardCap()
    if excess < 0 then
        return 0
    end
    return excess
end

-- Last unlocked shard in the regular bags, searching from the back.
-- Soul Shard bags are skipped: the shards kept there are the ones under
-- the cap, so extras are always taken from regular bags.
-- Second return when nothing usable is found: true if a shard exists but
-- is locked (normal, retry later), false if no shard was seen at all.
local function FindShardSlot()
    local sawLocked = false
    for bag = LAST_BAG, FIRST_BAG, -1 do
        local slots = IsSoulBag(bag) and 0 or (ns.Plain(GetNumSlots(bag)) or 0)
        for slot = slots, 1, -1 do
            if ns.Plain(GetItemID(bag, slot)) == ns.SHARD_ITEM_ID then
                local info = GetItemInfo(bag, slot)
                if info and not ns.Plain(info.isLocked) then
                    return bag, slot, ns.Plain(info.stackCount) or 1
                end
                sawLocked = true
            end
        end
    end
    return nil, sawLocked
end

-- Deletes up to `excess` shards from one slot.
-- Returns ok, reason, quiet (quiet = normal "try later", don't print).
local function DeleteOne(excess)
    if GetCursorInfo() then
        return false, "your cursor is holding something", true
    end
    local bag, slot, stack = FindShardSlot()
    if not bag then
        if slot then
            return false, "shard is locked", true
        end
        return false, "the count says you are over the cap but no shard was found in your"
            .. " regular bags " .. FIRST_BAG .. "-" .. LAST_BAG .. ". Run /sscap status"
    end
    if stack > excess then
        if not SplitItem then
            return false, "shards are stacked and this client has no split API"
        end
        SplitItem(bag, slot, excess)
    else
        PickupItem(bag, slot)
    end

    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or ns.Plain(itemID) ~= ns.SHARD_ITEM_ID then
        ClearCursor()
        return false, "cursor check failed, nothing deleted"
    end
    DeleteCursorItem()
    return true
end

---------------------------------------------------------------------------
-- Passes
---------------------------------------------------------------------------

local function EndPass()
    if pass and pass.deleted > 0 then
        ns.Print("Deleted " .. pass.deleted .. " extra Soul Shard"
            .. (pass.deleted == 1 and "" or "s") .. ".")
    end
    pass = nil
    Trim.UpdateButton()
end

local function AutoAllowed()
    return ns.shardDB.autoDelete and not ns.autoBlocked and Trim.Supported()
end

-- One step of an automatic pass. Called again on each BAG_UPDATE_DELAYED.
local function Step()
    if not pass then return end
    if not AutoAllowed() then
        EndPass()
        return
    end
    if InCombatLockdown() then
        pendingCombat = true
        EndPass()
        return
    end
    local excess = Trim.Excess()
    if excess <= 0 or Trim.WantHealthstone() then
        EndPass()
        return
    end
    -- The last delete should have lowered the count. If it did not, stop
    -- and back off instead of retrying on every bag update.
    if pass.lastExcess and excess >= pass.lastExcess then
        ns.Print("A delete did not lower your shard count. Pausing auto-delete for "
            .. BACKOFF_SECONDS .. " seconds. /sscap delete works by hand.")
        backoffUntil = GetTime() + BACKOFF_SECONDS
        EndPass()
        return
    end
    if GetTime() - pass.started > PASS_SECONDS or pass.attempts >= pass.maxAttempts then
        EndPass()
        return
    end

    pass.attempts = pass.attempts + 1
    pass.lastExcess = excess
    local ok, reason, quiet = DeleteOne(excess)
    if ok then
        pass.deleted = pass.deleted + 1
    else
        if not quiet then
            ns.Print("Could not delete a shard: " .. reason .. ".")
            backoffUntil = GetTime() + BACKOFF_SECONDS
        end
        EndPass()
    end
end

function Trim.Begin()
    if pass then
        Step()
        return
    end
    if not AutoAllowed() or GetTime() < backoffUntil then
        Trim.UpdateButton()
        return
    end
    local excess = Trim.Excess()
    if excess <= 0 then
        return
    end
    -- Keep the extra shard for a healthstone; the button offers the cast.
    if Trim.WantHealthstone() then
        Trim.UpdateButton()
        return
    end
    if InCombatLockdown() then
        pendingCombat = true
        return
    end
    pass = { started = GetTime(), attempts = 0, maxAttempts = excess + 2, deleted = 0 }
    Step()
end

-- Manual delete: one slot per click or slash command. A click is a
-- hardware event, so this still works if the client blocks auto-delete.
function Trim.DeleteManual()
    if InCombatLockdown() then
        ns.Print("In combat. Try again after combat ends.")
        return
    end
    if not Trim.Supported() then
        ns.Print("This client is missing a bag API. Type /sscap probe and share the output.")
        return
    end
    local excess = Trim.Excess()
    if excess <= 0 then
        ns.Print("No shards above the cap.")
        Trim.UpdateButton()
        return
    end
    local ok, reason = DeleteOne(excess)
    if not ok then
        ns.Print("Could not delete a shard: " .. reason .. ".")
    end
end

---------------------------------------------------------------------------
-- Event entry points (wired in Core.lua)
---------------------------------------------------------------------------

function Trim.OnBags()
    Trim.Begin()
    Trim.UpdateButton()
end

-- PLAYER_REGEN_DISABLED fires just before InCombatLockdown() turns true,
-- so track combat with our own flag for the delete button.
local inCombat = false

function Trim.InCombat()
    return inCombat or InCombatLockdown()
end

function Trim.OnRegenDisabled()
    inCombat = true
    Trim.UpdateButton()   -- hides the delete button for the fight
end

function Trim.OnRegenEnabled()
    inCombat = false
    if pendingCombat then
        pendingCombat = false
    end
    -- Bags may have changed during combat without a pass; check now.
    Trim.Begin()
    Trim.UpdateButton()
end

function Trim.OnActionBlocked(blockedAddon, func)
    if blockedAddon ~= addonName then return end
    ns.autoBlocked = true
    ns.shardDB.blockedOnBuild = ns.BuildString()
    pass = nil
    ns.Print("The client blocked " .. ns.Show(func) .. ". Auto-delete is off on this build."
        .. " Use the Delete button or /sscap delete instead.")
    Trim.UpdateButton()
end

---------------------------------------------------------------------------
-- Diagnostics: /sscap status
---------------------------------------------------------------------------

local function YesNo(v)
    return v and "yes" or "no"
end

function Trim.Status()
    local P = ns.Print
    local count, nativeMax = ns.ReadShards()
    P("mode " .. ns.Show(ns.mode) .. "  shard item ID " .. ns.Show(ns.SHARD_ITEM_ID)
        .. "  count " .. ns.Show(count) .. "  cap " .. ns.Show(nativeMax or ns.ShardCap())
        .. "  excess " .. Trim.Excess())
    local soul = Trim.SoulBagSlots()
    P("soul shard bag " .. (soul > 0 and ("yes (" .. soul .. " slots, used as the cap; set cap "
        .. ns.shardDB.cap .. " ignored)") or "no (set cap " .. ns.shardDB.cap .. " used)"))
    if ns.mode == "power" then
        P("Shards are read as a POWER BAR (max " .. ns.Show(nativeMax)
            .. "), so nothing is deleted. If your shards are bag items, type /sscap mode item")
    end
    P("autoDelete " .. YesNo(ns.shardDB.autoDelete) .. "  blocked by client " .. YesNo(ns.autoBlocked)
        .. "  bag APIs present " .. YesNo(Trim.Supported()))
    local backoff = backoffUntil - GetTime()
    P("in combat " .. YesNo(InCombatLockdown()) .. "  waiting for combat end " .. YesNo(pendingCombat)
        .. "  cursor busy " .. YesNo(GetCursorInfo() ~= nil)
        .. "  pass running " .. YesNo(pass ~= nil)
        .. "  backoff " .. (backoff > 0 and (math.ceil(backoff) .. "s") or "none"))

    local hsSpell = Trim.BestHealthstoneSpell()
    P("healthstone in bags " .. YesNo(Trim.HasHealthstone())
        .. "  Create Healthstone known " .. (hsSpell and ("yes (spell " .. hsSpell .. ")") or "no")
        .. "  -> extra shards " .. (Trim.WantHealthstone() and "kept for the Create Healthstone button" or "deleted"))
    P(ns.Stones.StatusLine())

    if not Trim.Supported() then return end
    local bag, slot, stack = FindShardSlot()
    if bag then
        P("next shard to delete: bag " .. bag .. " slot " .. slot .. " stack " .. ns.Show(stack))
    else
        P("no deletable shard found in bags " .. FIRST_BAG .. "-" .. LAST_BAG
            .. (slot and " (one is locked)" or ""))
    end

    -- List anything in the bags that looks like a shard, with its item ID,
    -- in case the Soul Shard ID is different on this client.
    local found = 0
    for b = FIRST_BAG, LAST_BAG do
        local slots = ns.Plain(GetNumSlots(b)) or 0
        for s = 1, slots do
            local info = GetItemInfo(b, s)
            local link = info and ns.Plain(info.hyperlink)
            local id = info and ns.Plain(info.itemID)
            if link and link:lower():find("shard", 1, true) and found < 10 then
                found = found + 1
                P("  bag " .. b .. " slot " .. s .. ": " .. link .. " id " .. ns.Show(id)
                    .. " x" .. ns.Show(info.stackCount))
            end
        end
    end
    if found == 0 then
        P("  no item with \"shard\" in its name found in bags " .. FIRST_BAG .. "-" .. LAST_BAG .. ".")
    end
end

-- Buttons under the display:
--   * Create Healthstone: you have no healthstone, know the spell and hold
--     at least one shard, at any shard count (secure button; only changed
--     out of combat, re-run on combat end; hidden while dead by its holder)
--   * Firestone / Spellstone row under the healthstone row: two half-width
--     Create buttons, or one Apply button while a stone is in your bags
--     (see Stones.lua)
--   * Delete extra: over the cap, no healthstone to make, auto-delete
--     is off or blocked, and out of combat (hidden on PLAYER_REGEN_DISABLED,
--     shown again on PLAYER_REGEN_ENABLED)
function Trim.UpdateButton()
    if not ns.shardDB then return end
    local excess = Trim.Excess()
    local visible = excess > 0 and not ns.shardDB.hidden
    local count = ns.mode == "item" and ns.ReadShards() or nil
    local hsSpell = nil
    if not ns.shardDB.hidden and count and count >= 1 then
        hsSpell = Trim.WantHealthstone()
    end

    local hs = ns.healthstoneButton
    if hs and not InCombatLockdown() then
        if hsSpell then
            hs:SetAttribute("type", "spell")
            hs:SetAttribute("spell", hsSpell)
            hs.spellID = hsSpell
            hs:Show()
        else
            hs:Hide()
        end
    end
    local hsShown = hs and hs:IsShown()

    local del = ns.trimButton
    if del then
        -- Plain, non-secure button, so it can be hidden any time, combat
        -- included. Covers ghosts too. A secret value counts as alive.
        local dead = UnitIsDeadOrGhost and ns.Plain(UnitIsDeadOrGhost("player"))
        if visible and not dead and not Trim.InCombat()
            and not hsSpell and not hsShown and not AutoAllowed() then
            del:SetText("Delete extra (" .. excess .. ")")
            del:Show()
        else
            del:Hide()
        end
    end

    local topRow = (hsShown or (del and del:IsShown())) and true or false

    -- Firestone (left) / Spellstone (right) row: secure, so only changed out
    -- of combat. Sits under the healthstone / delete row when that is
    -- showing, otherwise moves up directly under the counter.
    -- With a stone in your bags the row is one button that applies it to
    -- your weapon instead.
    local row = ns.stoneRow
    if row and not InCombatLockdown() then
        local state, a, b, c
        if not ns.shardDB.hidden then
            state, a, b, c = ns.Stones.RowState(count and count >= 1)
        end
        local any = false
        local apply = row.apply
        if state == "apply" then
            local stone, use, itemID = a, b, c
            apply:SetAttribute("type", "macro")
            apply:SetAttribute("macrotext", ns.Stones.ApplyMacro(use))
            apply.itemID = itemID
            apply:SetText("Apply " .. stone.label)
            local icon = itemID and C_Item and C_Item.GetItemIconByID
                and ns.Plain(C_Item.GetItemIconByID(itemID))
            apply.icon:SetTexture(icon or stone.icon)
            if apply.SetBackdropColor then
                local col = stone.color
                apply:SetBackdropColor(col.bg[1], col.bg[2], col.bg[3], col.bg[4])
                apply:SetBackdropBorderColor(col.border[1], col.border[2], col.border[3], col.border[4])
            end
            apply:Show()
            any = true
        else
            apply:Hide()
        end
        for _, stone in ipairs(ns.Stones.list) do
            local btn = row.buttons[stone.key]
            local spell = state == "create" and a[stone.key] or nil
            if spell then
                btn:SetAttribute("type", "spell")
                btn:SetAttribute("spell", spell)
                btn.spellID = spell
                btn.icon:SetTexture(ns.Stones.Icon(stone, spell))
                btn:Show()
                any = true
            else
                btn:Hide()
            end
        end
        row.active = any
        ns.AnchorStoneRow(row, topRow)
    end
    local rows = (topRow and 1 or 0) + ((row and row.active) and 1 or 0)

    -- The demon bar sits directly under the counter, below however many of
    -- these button rows are showing.
    if ns.Pets and ns.Pets.SetButtonRows then
        ns.Pets.SetButtonRows(rows)
    end
end
