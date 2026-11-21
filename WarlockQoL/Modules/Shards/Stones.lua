local addonName, ns = ...

-- Firestone and Spellstone: data and checks for the row under the Create
-- Healthstone button (UI.lua builds it, Trim.UpdateButton fills it).
--   * Neither stone in your bags: two half-width Create buttons
--     (Firestone left, Spellstone right), each shown when you know the
--     spell, hold a Soul Shard and don't hold that stone in your off-hand.
--   * Either stone in your bags: one full-width button that applies it to
--     your main-hand weapon.
-- Unlike healthstones, these do NOT hold back
-- shard auto-delete: many Warlocks never use one, and keeping a shard for
-- them would stop auto-delete for good.

local Stones = {}
ns.Stones = Stones

local INVSLOT_OFFHAND = INVSLOT_OFFHAND or 17

-- Order is the on-screen order, left to right.
Stones.list = {
    {
        key = "firestone",
        label = "Firestone",
        name = "firestone", -- English name fallback
        -- Create Firestone ranks, highest first: Major, Greater, normal, Lesser.
        spells = { 17953, 17952, 17951, 6366 },
        -- Lesser, normal, Greater, Major Firestone.
        items = { 1254, 13699, 13700, 13701 },
        icon = "Interface\\Icons\\INV_Ammo_FireTar",
        color = { bg = { 0.35, 0.12, 0.05, 0.9 }, border = { 1.00, 0.50, 0.20, 1 } },
    },
    {
        key = "spellstone",
        label = "Spellstone",
        name = "spellstone",
        -- Create Spellstone ranks, highest first: Major, Greater, normal.
        spells = { 17728, 17727, 2362 },
        -- Spellstone, Greater, Major.
        items = { 5522, 13602, 13603 },
        icon = "Interface\\Icons\\INV_Misc_Gem_Sapphire_01",
        color = { bg = { 0.08, 0.15, 0.35, 0.9 }, border = { 0.40, 0.60, 1.00, 1 } },
    },
}

local C = C_Container
local GetNumSlots = C and C.GetContainerNumSlots
local GetSlotInfo = C and C.GetContainerItemInfo
local FIRST_BAG = 0
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

function Stones.BestSpell(stone)
    for _, id in ipairs(stone.spells) do
        if ns.KnowsSpell(id) then
            return id
        end
    end
    return nil
end

local function LinkMatches(link, stone)
    return link and link:lower():find(stone.name, 1, true) ~= nil
end

-- Finds this stone in your bags (not equipped). Returns what to put after
-- /use ("item:<id>", or "<bag> <slot>" for the name fallback) and the item
-- ID when known, or nil. Best rank first.
function Stones.FindInBags(stone)
    if GetNumSlots and GetSlotInfo then
        local best, bestID, bestRank
        for bag = FIRST_BAG, LAST_BAG do
            local slots = ns.Plain(GetNumSlots(bag)) or 0
            for slot = 1, slots do
                local info = GetSlotInfo(bag, slot)
                local id = info and ns.Plain(info.itemID)
                local rank
                for i, itemID in ipairs(stone.items) do
                    if id == itemID then rank = i end
                end
                if rank and (not bestRank or rank > bestRank) then
                    best, bestID, bestRank = "item:" .. id, id, rank
                elseif not rank and not best and info and LinkMatches(ns.Plain(info.hyperlink), stone) then
                    best, bestID = bag .. " " .. slot, id -- name fallback
                end
            end
        end
        return best, bestID
    end
    -- No container API: count by ID only.
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    if getCount then
        for i = #stone.items, 1, -1 do
            local id = stone.items[i]
            local n = ns.Plain(getCount(id, false))
            if n and n > 0 then
                return "item:" .. id, id
            end
        end
    end
    return nil
end

-- The first stone (Firestone, then Spellstone) in your bags, as
-- stone, useString, itemID; or nil.
function Stones.AnyInBags()
    for _, stone in ipairs(Stones.list) do
        local use, id = Stones.FindInBags(stone)
        if use then
            return stone, use, id
        end
    end
    return nil
end

-- Held in the off-hand (by ID, or by name if Forever uses other IDs).
function Stones.Held(stone)
    local held = GetInventoryItemID and ns.Plain(GetInventoryItemID("player", INVSLOT_OFFHAND))
    if held then
        for _, id in ipairs(stone.items) do
            if held == id then
                return true
            end
        end
    end
    if GetInventoryItemLink and LinkMatches(ns.Plain(GetInventoryItemLink("player", INVSLOT_OFFHAND)), stone) then
        return true
    end
    return false
end

function Stones.Has(stone)
    return Stones.FindInBags(stone) ~= nil or Stones.Held(stone)
end

-- What the stone row should show:
--   "apply", stone, useString, itemID  a stone is in your bags: one button
--                                      that applies it to your weapon
--   "create", { [key] = spellID }      no stone in bags: Create buttons for
--                                      the ones you know (and don't hold)
--   nil                                nothing to show
-- hasShard: you hold at least one Soul Shard (needed to create).
function Stones.RowState(hasShard)
    if ns.mode ~= "item" then return nil end
    local stone, use, id = Stones.AnyInBags()
    if stone then
        return "apply", stone, use, id
    end
    if not hasShard then return nil end
    local spells, any = {}, false
    for _, s in ipairs(Stones.list) do
        if not Stones.Held(s) then
            spells[s.key] = Stones.BestSpell(s)
            any = any or spells[s.key] ~= nil
        end
    end
    if any then
        return "create", spells
    end
    return nil
end

-- Uses the stone, then targets the main-hand weapon slot, so one click
-- applies it (same as a "/use Firestone" + "/use 16" macro).
function Stones.ApplyMacro(useString)
    return "/use " .. useString .. "\n/use " .. (INVSLOT_MAINHAND or 16)
end

function Stones.Icon(stone, spellID)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = ns.Plain(C_Spell.GetSpellTexture(spellID))
        if tex then
            return tex
        end
    end
    return stone.icon
end

-- One line for /sscap status and /wqol probe.
function Stones.StatusLine()
    local parts = {}
    for _, stone in ipairs(Stones.list) do
        local spell = Stones.BestSpell(stone)
        parts[#parts + 1] = stone.label .. ": in bags " .. ns.Show(Stones.FindInBags(stone))
            .. ", off-hand " .. (Stones.Held(stone) and "yes" or "no")
            .. ", Create known " .. (spell and ("yes (spell " .. spell .. ")") or "no")
    end
    return table.concat(parts, "  ")
end
