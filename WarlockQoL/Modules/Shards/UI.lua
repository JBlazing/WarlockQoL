local addonName, ns = ...

-- Display widget. This is a plain, non-protected Frame, so showing, hiding
-- and moving it is allowed in combat. Nothing here touches Blizzard frames.

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local DOUBLE_CLICK_SECONDS = 0.4
local DISPLAY_WIDTH = 150 -- wide enough for "Create Healthstone" + icon

local STATE_COLORS = {
    ok      = { 1.00, 1.00, 1.00 },
    near    = { 1.00, 0.82, 0.00 },
    full    = { 1.00, 0.20, 0.20 },
    unknown = { 0.60, 0.60, 0.60 },
}

local function ShardIcon()
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(ns.SHARD_ITEM_ID)
        if icon and not ns.IsSecret(icon) then
            return icon
        end
    end
    return FALLBACK_ICON
end

function ns.RestorePosition(frame, db)
    frame:ClearAllPoints()
    local p = db.point
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Soul Shards")
    if self.count then
        GameTooltip:AddLine(self.count .. " / " .. self.cap, 1, 1, 1)
    else
        GameTooltip:AddLine("Count unavailable on this client.", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Double-click to set the max. Drag to move.", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("Type /sscap for more options.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

function ns.CreateDisplay(db)
    local f = CreateFrame("Frame", "WarlockQoL_ShardsDisplay", UIParent, "BackdropTemplate")
    -- Width shared with the buttons below, which anchor to both edges.
    f:SetSize(DISPLAY_WIDTH, 34)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0, 0, 0, 0.6)
        f:SetBackdropBorderColor(0.58, 0.51, 0.79, 1)
    end

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", f, "LEFT", 5, 0)
    icon:SetTexture(ShardIcon())
    f.icon = icon

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetText("-")
    f.text = text

    -- Double-click detection. Frames have no OnDoubleClick (only Buttons do),
    -- so time two mouse-ups. A drag in between does not count as a click.
    local lastClick = 0
    f:SetScript("OnMouseDown", function(self)
        self.dragged = false
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or self.dragged then
            return
        end
        local now = GetTime()
        if now - lastClick <= DOUBLE_CLICK_SECONDS then
            lastClick = 0
            ns.OpenCapEditor()
        else
            lastClick = now
        end
    end)

    f:SetScript("OnDragStart", function(self)
        self.dragged = true
        -- The secure Create Healthstone button is anchored to this frame,
        -- so moving it in combat would move a protected frame.
        if InCombatLockdown() then
            ns.Print("Can't move the display in combat.")
            return
        end
        if not db.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        db.point = { point, relPoint, x, y }
    end)
    f:SetScript("OnEnter", OnEnter)
    f:SetScript("OnLeave", OnLeave)

    ns.RestorePosition(f, db)
    if db.hidden then
        f:Hide()
    end
    return f
end

-- Cap editor: a small box of our own (not a StaticPopup, so nothing of
-- Blizzard's is touched). Enter or Set saves; Escape or X closes.
local editor

local function CreateCapEditor()
    local e = CreateFrame("Frame", "WarlockQoL_ShardsEditor", UIParent, "BackdropTemplate")
    e:SetSize(170, 70)
    e:SetFrameStrata("DIALOG")
    e:SetClampedToScreen(true)
    e:EnableMouse(true)
    if e.SetBackdrop then
        e:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        e:SetBackdropColor(0, 0, 0, 0.85)
        e:SetBackdropBorderColor(0.58, 0.51, 0.79, 1)
    end

    local label = e:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", e, "TOPLEFT", 10, -9)
    label:SetText("Max Soul Shards")

    local close = CreateFrame("Button", nil, e, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", e, "TOPRIGHT", -1, -1)

    local box = CreateFrame("EditBox", nil, e, "InputBoxTemplate")
    box:SetSize(50, 20)
    box:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", 16, 12)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    e.box = box

    local set = CreateFrame("Button", nil, e, "UIPanelButtonTemplate")
    set:SetSize(64, 22)
    set:SetPoint("LEFT", box, "RIGHT", 12, 0)
    set:SetText("Set")

    local function Commit()
        if ns.SetCap(box:GetText()) then
            e:Hide()
        else
            box:SetText(tostring(ns.shardDB.cap))
            box:HighlightText()
        end
    end
    box:SetScript("OnEnterPressed", Commit)
    set:SetScript("OnClick", Commit)
    box:SetScript("OnEscapePressed", function() e:Hide() end)
    e:SetScript("OnHide", function() box:ClearFocus() end)

    e:Hide()
    return e
end

function ns.OpenCapEditor()
    if not ns.display or not ns.shardDB then return end
    editor = editor or CreateCapEditor()
    editor:ClearAllPoints()
    editor:SetPoint("BOTTOM", ns.display, "TOP", 0, 4)
    editor.box:SetText(tostring(ns.shardDB.cap))
    editor:Show()
    editor.box:SetFocus()
    editor.box:HighlightText()
end

-- Create Healthstone button: our own SecureActionButton (type "spell").
-- Your click casts the spell; the addon never casts by itself. Parented to
-- UIParent so the display frame itself stays a normal frame. Attributes
-- and Show/Hide are only changed out of combat (see Trim.UpdateButton).
-- Must be created out of combat.
function ns.CreateHealthstoneButton(display)
    -- Holder hides the button while you are dead. The visibility driver is
    -- run by the client, so it works in combat too. The button's own
    -- Show/Hide (shards over cap, no healthstone) stays in Trim.UpdateButton.
    local holder = CreateFrame("Frame", "WarlockQoL_ShardsHealthstoneHolder", UIParent,
        "SecureHandlerStateTemplate")
    -- Same width as the counter: pinned to both of its bottom corners.
    holder:SetHeight(24)
    holder:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 0, -2)
    holder:SetPoint("TOPRIGHT", display, "BOTTOMRIGHT", 0, -2)
    holder:SetFrameStrata("MEDIUM")
    if RegisterStateDriver then
        RegisterStateDriver(holder, "visibility", "[@player,dead] hide; show")
    end

    local b = CreateFrame("Button", "WarlockQoL_ShardsHealthstoneButton", holder,
        "SecureActionButtonTemplate,BackdropTemplate")
    b:SetAllPoints(holder)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")

    if b.SetBackdrop then
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        b:SetBackdropColor(0.10, 0.30, 0.10, 0.9)
        b:SetBackdropBorderColor(0.30, 0.90, 0.30, 1)
    end

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", b, "LEFT", 4, 0)
    icon:SetTexture("Interface\\Icons\\INV_Stone_04")

    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetText("Create Healthstone")
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if self.spellID and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.spellID)
        else
            GameTooltip:AddLine("Create Healthstone")
        end
        GameTooltip:AddLine("You have no healthstone. Uses one Soul Shard.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", OnLeave)

    b:Hide()
    return b
end

-- Manual delete button, shown under the display only when needed. Plain
-- Button (not secure): the click is the hardware event.
function ns.CreateTrimButton(display)
    local b = CreateFrame("Button", "WarlockQoL_ShardsDeleteButton", display, "UIPanelButtonTemplate")
    -- Same width as the counter, like the healthstone button.
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 0, -2)
    b:SetPoint("TOPRIGHT", display, "BOTTOMRIGHT", 0, -2)
    b:SetText("Delete extra")
    b:SetScript("OnClick", function()
        ns.Trim.DeleteManual()
    end)
    b:Hide()
    return b
end

-- count and cap are plain numbers here; Core.lua filters secret values out
-- before calling. count == nil means "could not read".
function ns.UpdateDisplay(count, cap, state)
    local f = ns.display
    if not f then return end
    f.count, f.cap = count, cap
    local c = STATE_COLORS[state] or STATE_COLORS.unknown
    f.text:SetTextColor(c[1], c[2], c[3])
    if count then
        f.text:SetText(count .. " / " .. cap)
    else
        f.text:SetText("?")
    end
end
