if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUITalents.lua
--  Dworak > Talents: the Unspent Talent Points reminder. While the player has
--  talent points left to spend it shows "Unspent Talent Points : N" on screen.
--  The label follows the UI Accent Color (Global Settings) live; the number
--  stays white. Moved in Unlock Mode ("Dworak" group, "Talent Reminder").
--
--  Its own addon: it registers its row in the "Dworak" section through
--  EllesmereUIDworak and needs nothing else from the other Dworak addons.
--  Settings live in the EllesmereUI profile store through
--  EllesmereUI.Lite.NewDB, like every suite module. No Reset button.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local DW = EllesmereUIDworak
if not DW then return end -- the Dworak core is off: nothing to register into

ns.FOLDER = ADDON_NAME

local TALENT_DEFAULTS = {
    profile = {
        talentsEnabled  = false,
        talentsTextSize = 16,
        talentsWidth    = 260,          -- unused since the frame fits its text; kept for old saves
        talentsFont     = "__global",   -- "__global" = the EUI Global Font
        talentsSound    = "none",       -- alert sound key, played when the reminder comes up
        talentsBgR = 0.05, talentsBgG = 0.05, talentsBgB = 0.05,
        talentsBgA      = 0,            -- background opacity 0..1 (0 = no background)
        talentsLabelColor = "accent",   -- "accent" = UI Accent Color, "custom" = talentsLabelR/G/B
        talentsLabelR = 1, talentsLabelG = 0.82, talentsLabelB = 0,
        -- talentsPosition (point, relPoint, x, y): set by Unlock Mode
    },
}
local DEFAULTS = TALENT_DEFAULTS.profile

local SV_NAME = "EllesmereUITalentsDB"
local db = EllesmereUI.Lite.NewDB(SV_NAME, TALENT_DEFAULTS)

-- The live profile table, re-opened after an EllesmereUI profile swap.
local function DB()
    local active = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if db._profileName ~= active then
        db = EllesmereUI.Lite.NewDB(SV_NAME, TALENT_DEFAULTS)
    end
    return db.profile
end

local function Get(key)
    local v = DB()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local function Set(key, value)
    DB()[key] = value
end

function ns.AccentHex()
    local c = EllesmereUI.ELLESMERE_GREEN
    local r, g, b = 0.05, 0.82, 0.62
    if c and c.r then r, g, b = c.r, c.g, c.b end
    if EllesmereUI.HexColor then return EllesmereUI.HexColor(r, g, b) end
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- One-time move: Talents first shipped inside Bag Slots and kept its talents*
-- keys in the Bag Slots profile. Takes them over, then clears them there.
local function MigrateFromBagSlots()
    local profiles = EllesmereUIDB and EllesmereUIDB.profiles
    if type(profiles) ~= "table" then return end
    local p = DB()
    for _, prof in pairs(profiles) do
        local old = type(prof) == "table" and type(prof.addons) == "table" and prof.addons.EllesmereUIBagSlots
        if type(old) == "table" then
            for _, k in ipairs({ "talentsEnabled", "talentsTextSize", "talentsWidth", "talentsPosition" }) do
                if old[k] ~= nil then
                    if p[k] == nil then p[k] = old[k] end
                    old[k] = nil
                end
            end
        end
    end
end

local UNLOCK_KEY = "EUI_DworakTalents"
local DEFAULT_POS = { point = "TOP", relPoint = "TOP", x = 0, y = -160 }

local frame, events
local unlocked = false

local function Enabled() return Get("talentsEnabled") == true end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == "number" then return v end
end

-- Unspent points: the client's own count when it has one, else level-based
-- (1 point per level from 10) minus the points spent in every tree.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, n = pcall(fn, ...)
    return ok and Plain(n) or nil
end

-- Trait talents (the WoW Forever talent window, Apply Changes): the unspent
-- points are the tree's currencies. Nil when the client has no trait talents.
local function TraitPoints()
    if not (C_ClassTalents and C_Traits and C_ClassTalents.GetActiveConfigID) then return nil end
    local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
    configID = ok and Plain(configID)
    if not configID then return nil end
    local trees = {}
    local okc, cfg = pcall(C_Traits.GetConfigInfo, configID)
    if okc and type(cfg) == "table" and type(cfg.treeIDs) == "table" then
        for _, t in ipairs(cfg.treeIDs) do trees[#trees + 1] = t end
    end
    if #trees == 0 and C_SpecializationInfo and C_ClassTalents.GetTraitTreeForSpec then
        local okS, specIndex = pcall(C_SpecializationInfo.GetSpecialization)
        local specID = okS and specIndex and select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
        local t = specID and Call(C_ClassTalents.GetTraitTreeForSpec, specID)
        if t then trees[1] = t end
    end
    if #trees == 0 then return nil end
    local total, seen = 0, {}
    for _, treeID in ipairs(trees) do
        local okT, list = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
        if okT and type(list) == "table" then
            for _, cur in ipairs(list) do
                local id, q = cur.traitCurrencyID, Plain(cur.quantity)
                if q and not seen[id or q] then
                    seen[id or q] = true
                    total = total + q
                end
            end
        end
    end
    return total
end

-- The classic API's spent points, level-based: 1 point per level from 10.
local function TabPoints()
    if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
    local tabs = Call(GetNumTalentTabs)
    if not tabs or tabs == 0 then return nil end
    local level = Plain(UnitLevel("player")) or 0
    local spent = 0
    for tab = 1, tabs do
        -- Classic: name, icon, pointsSpent, ...; later clients put it 5th.
        local ok, _, _, c, _, e = pcall(GetTalentTabInfo, tab)
        if ok then spent = spent + ((type(c) == "number" and c) or (type(e) == "number" and e) or 0) end
    end
    return math.max(0, math.max(0, level - 9) - spent)
end

-- Every source this client has, for /euitalents debug.
local function Sources()
    return {
        { "C_Traits currency", TraitPoints() },
        { "GetUnspentTalentPoints", Call(GetUnspentTalentPoints) },
        { "UnitCharacterPoints", Call(UnitCharacterPoints, "player") },
        { "Talent tabs (level)", TabPoints() },
    }
end

-- The highest count any direct API of this client reports (an API kept only
-- for compatibility reads 0, the one its talent window uses the real count).
-- The level-based count only when the client has no direct API at all.
local function UnspentPoints()
    local list = Sources()
    local best
    for i = 1, 3 do
        local n = list[i][2]
        if n and n > (best or -1) then best = n end
    end
    if best == nil then best = list[4][2] end
    return best or 0
end

local function TextHeight()
    return math.floor(Get("talentsTextSize") * 1.6 + 0.5)
end

local PAD_X, PAD_Y = 10, 4

-- The frame fits its text, plus padding around it for the background.
local function FrameSize()
    if frame and frame:GetWidth() > 0 then return frame:GetWidth(), frame:GetHeight() end
    return 200 + PAD_X * 2, TextHeight() + PAD_Y * 2
end

-- Own sound tables (the catalogue's contract: every consumer builds its own),
-- SharedMedia sounds appended at login once every addon has registered them.
local SOUND_PATHS, SOUND_NAMES, SOUND_ORDER = {}, { none = "None" }, { "none" }
if EllesmereUI.BuildAlertSoundTables then
    SOUND_PATHS, SOUND_NAMES, SOUND_ORDER = EllesmereUI.BuildAlertSoundTables()
end

local function PlayKey(key)
    local path = key and key ~= "none" and SOUND_PATHS[key]
    if path then PlaySoundFile(path, "Master") end
end

local function FontPath()
    local f = Get("talentsFont")
    if f and f ~= "__global" and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(f)
        if path then return path end
    end
    return EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
end

local function SavedPos()
    local pos = Get("talentsPosition")
    return pos and pos.point and pos or DEFAULT_POS
end

local function Place()
    if not frame then return end
    local pos = SavedPos()
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

-- The "Unspent Talent Points :" colour: the UI Accent Color, or a custom one.
local function LabelHex()
    if Get("talentsLabelColor") == "custom" then
        return string.format("|cff%02x%02x%02x", Get("talentsLabelR") * 255,
            Get("talentsLabelG") * 255, Get("talentsLabelB") * 255)
    end
    return ns.AccentHex()
end

-- One reminder box (background + text): the live frame and the options preview.
local function MakeBox(box)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    box.text = box:CreateFontString(nil, "OVERLAY")
    box.text:SetFontObject(GameFontHighlight) -- a font before the first SetText
    box.text:SetPoint("CENTER")
    box.text:SetShadowOffset(1, -1)
    box.text:SetShadowColor(0, 0, 0, 1)
    return box
end

-- Paints a box with the current settings for n points; it fits its text.
local function StyleBox(box, n)
    EllesmereUI.ApplyModuleFont(box.text, FontPath(), Get("talentsTextSize"))
    box.text:SetText(LabelHex() .. "Unspent Talent Points :|r " .. n)
    box:SetSize(math.ceil(box.text:GetStringWidth()) + PAD_X * 2, TextHeight() + PAD_Y * 2)
    box.bg:SetColorTexture(Get("talentsBgR"), Get("talentsBgG"), Get("talentsBgB"), Get("talentsBgA"))
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "EUI_DworakTalentReminder", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    MakeBox(frame)
    frame:Hide()
    Place()
    return frame
end

-------------------------------------------------------------------------------
--  Options preview: the same box in the content header, with the real count
--  (3 while no point is left), redrawn on every setting change.
-------------------------------------------------------------------------------
local PREVIEW_MIN_H, PREVIEW_MARGIN = 90, 14
local preview

-- The header height that fits the (scaled) box; the box shrinks to the
-- header's width when a large Text Size would make it wider than the page.
local function PreviewHeight()
    local box = preview.box
    local avail = (preview:GetWidth() or 0) - PREVIEW_MARGIN * 2
    local scale = 1
    if avail > 50 and box:GetWidth() > avail then scale = avail / box:GetWidth() end
    box:SetScale(scale)
    return math.max(PREVIEW_MIN_H, math.ceil(box:GetHeight() * scale) + PREVIEW_MARGIN * 2 + 12)
end

local function RefreshPreview()
    if not (preview and preview:IsShown()) then return end
    local n = UnspentPoints()
    StyleBox(preview.box, n > 0 and n or 3)
    local h = PreviewHeight()
    if math.abs(preview:GetHeight() - h) > 1 then
        preview:SetHeight(h)
        local header = preview:GetParent()
        if preview.built and header and header:IsVisible() and EllesmereUI.SetContentHeaderHeightSilent then
            EllesmereUI:SetContentHeaderHeightSilent(h)
        end
    end
    -- Dimmed while the reminder is off.
    preview.box:SetAlpha(Enabled() and 1 or 0.5)
    preview.hint:SetText(Enabled() and "" or "Preview (the reminder is off)")
end

local function HeaderBuilder(header, width)
    if not preview then
        preview = CreateFrame("Frame", nil, header)
        preview.box = MakeBox(CreateFrame("Frame", nil, preview))
        preview.box:SetPoint("CENTER")
        preview.hint = preview:CreateFontString(nil, "OVERLAY")
        preview.hint:SetFontObject(GameFontDisableSmall)
        preview.hint:SetPoint("BOTTOM", preview, "BOTTOM", 0, 6)
    end
    preview:SetParent(header)
    preview:SetFrameStrata(header:GetFrameStrata())
    preview:SetFrameLevel(header:GetFrameLevel() + 5)
    preview.box:SetFrameLevel(preview:GetFrameLevel() + 1)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", header, "TOPLEFT")
    preview:SetPoint("TOPRIGHT", header, "TOPRIGHT")
    if width and width > 0 then preview:SetWidth(width) end
    preview.built = false
    preview:Show()
    RefreshPreview()
    preview.built = true
    return preview:GetHeight()
end

local lastShown, lastCount = false, 0

local function Render()
    RefreshPreview()
    if not frame then return end
    local n = UnspentPoints()
    StyleBox(frame, n)
    local show = Enabled() and (unlocked or n > 0)
    frame:SetShown(show)
    -- The sound: the reminder comes up, or a new point arrives while it is up.
    if show and not unlocked and (not lastShown or n > lastCount) then PlayKey(Get("talentsSound")) end
    lastShown, lastCount = show, n
end

-- Level-ups report the new point a moment after the event.
local function OnEvent()
    Render()
    C_Timer.After(0.5, Render)
end

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "SPELLS_CHANGED",
    "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
    "TRAIT_NODE_CHANGED", "TRAIT_NODE_CHANGED_PARTIAL",
}

local function Apply()
    if events then events:UnregisterAllEvents() end
    if not Enabled() then
        if frame then frame:Hide() end
        lastShown = false
        RefreshPreview()
        return
    end
    Build()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    -- An event this client does not have errors on register: skip it.
    for _, ev in ipairs(EVENTS) do pcall(events.RegisterEvent, events, ev) end
    Place()
    Render()
end

-------------------------------------------------------------------------------
--  Options page (the Dworak > Talents row, added below)
-------------------------------------------------------------------------------
local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    parent._showRowDivider = true
    local function off() return not Enabled() end
    local prebuilding = EllesmereUI.IsSearchPrebuild()
    if not prebuilding then EllesmereUI:SetContentHeader(HeaderBuilder) end

    _, h = W:SectionHeader(parent, "TALENTS", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Unspent Talent Points Reminder",
          tooltip = "Shows \"Unspent Talent Points : N\" on screen while you have talent points left to spend.\n"
              .. "Move it in Unlock Mode.",
          getValue = function() return Enabled() end,
          setValue = function(v)
              Set("talentsEnabled", v)
              Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Sound", dropdownWidth = 220,
          tooltip = "Plays once when the reminder comes up, and when a new talent point arrives.",
          values = SOUND_NAMES, order = SOUND_ORDER,
          disabled = off, disabledTooltip = "Unspent Talent Points Reminder",
          getValue = function() return Get("talentsSound") or "none" end,
          setValue = function(v)
              Set("talentsSound", v)
              PlayKey(v)
          end }
    );  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Font", values = fontValues, order = fontOrder,
          disabled = off, disabledTooltip = "Unspent Talent Points Reminder",
          getValue = function() return Get("talentsFont") or "__global" end,
          setValue = function(v)
              Set("talentsFont", v)
              Render()
          end },
        { type = "slider", text = "Text Size", min = 8, max = 72, step = 1,
          disabled = off, disabledTooltip = "Unspent Talent Points Reminder",
          getValue = function() return Get("talentsTextSize") end,
          setValue = function(v)
              Set("talentsTextSize", v)
              Render()
          end }
    );  y = y - h

    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Background", min = 0, max = 100, step = 1, trackWidth = 120,
          tooltip = "Opacity of the background behind the text. 0 shows no background.",
          disabled = off, disabledTooltip = "Unspent Talent Points Reminder",
          getValue = function() return math.floor(Get("talentsBgA") * 100 + 0.5) end,
          setValue = function(v)
              Set("talentsBgA", v / 100)
              Render()
          end },
        { type = "dropdown", text = "Label Color",
          tooltip = "The color of \"Unspent Talent Points :\". UI Accent Color follows Global Settings; "
              .. "Custom uses the color next to it. The number stays white.",
          values = { accent = "UI Accent Color", custom = "Custom" }, order = { "accent", "custom" },
          disabled = off, disabledTooltip = "Unspent Talent Points Reminder",
          getValue = function() return Get("talentsLabelColor") or "accent" end,
          setValue = function(v)
              Set("talentsLabelColor", v)
              Render()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    if not prebuilding and bgRow and bgRow._rightRegion then
        EllesmereUI.BuildInlineSwatches(bgRow._rightRegion, { {
            tooltip = "Custom Label Color",
            disabled = function() return off() or Get("talentsLabelColor") ~= "custom" end,
            disabledTooltip = function() return off() and "Unspent Talent Points Reminder" or "Label Color: Custom" end,
            getValue = function() return Get("talentsLabelR"), Get("talentsLabelG"), Get("talentsLabelB"), 1 end,
            setValue = function(r, g, b)
                Set("talentsLabelR", r)
                Set("talentsLabelG", g)
                Set("talentsLabelB", b)
                Render()
            end,
        } }, { disabled = off, disabledTooltip = "Unspent Talent Points Reminder" })
    end
    if not prebuilding and bgRow and bgRow._leftRegion then
        EllesmereUI.BuildInlineSwatches(bgRow._leftRegion, { {
            tooltip = "Background Color",
            getValue = function() return Get("talentsBgR"), Get("talentsBgG"), Get("talentsBgB"), 1 end,
            setValue = function(r, g, b)
                Set("talentsBgR", r)
                Set("talentsBgG", g)
                Set("talentsBgB", b)
                Render()
            end,
        } }, { disabled = off, disabledTooltip = "Unspent Talent Points Reminder" })
    end

    return math.abs(y)
end

-- Dworak > Talents row (the section is registered by EllesmereUIDworak at login).
DW.AddModule({
    key         = "Talents",
    title       = "Talents",
    order       = 20,
    description = "Reminds you on screen while you have unspent talent points.",
    pages       = { "Talents" },
    buildPage   = BuildPage,
    -- The preview lives in the content header; declaring the builder makes a
    -- cached page whose header was dropped rebuild with it.
    getHeaderBuilder = function() return HeaderBuilder end,
    onPageCacheRestore = function() RefreshPreview() end,
})

-- /euitalents opens this page.
-- /euitalents debug prints what every talent API of this client reports.
SLASH_EUITALENTS1 = "/euitalents"
SlashCmdList.EUITALENTS = function(msg)
    if msg and msg:lower():match("debug") then
        local P = function(t) EllesmereUI.Print(ns.AccentHex() .. "Talents:|r " .. t) end
        P("enabled = " .. tostring(Enabled()) .. ", frame = " .. (frame and (frame:IsShown() and "shown" or "hidden") or "not built"))
        for _, src in ipairs(Sources()) do P(src[1] .. " = " .. tostring(src[2])) end
        P("shown count = " .. UnspentPoints())
        return
    end
    DW.Open("Talents")
end

-- The UI Accent Color (Global Settings) repaints the label live.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function() Render() end })
end

-------------------------------------------------------------------------------
--  Login: apply, then the Unlock Mode element
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    MigrateFromBagSlots()
    if EllesmereUI.AppendSharedMediaSounds then
        EllesmereUI.AppendSharedMediaSounds(SOUND_PATHS, SOUND_NAMES, SOUND_ORDER)
    end
    Apply()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = "Talent Reminder",
            group    = DW.UNLOCK_GROUP,
            order    = 910,
            noResize = true,
            isHidden = function() return not Enabled() end,
            getFrame = function()
                if not Enabled() then return nil end
                Build()
                Render()
                return frame
            end,
            getSize = function() return FrameSize() end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Set("talentsPosition", { point = point, relPoint = relPoint, x = x, y = y })
                if not (EllesmereUI.IsUnlockModeActive and EllesmereUI:IsUnlockModeActive()) then Place() end
            end,
            loadPos = SavedPos,
            clearPos = function()
                Set("talentsPosition", nil)
                Place()
            end,
            applyPos = function()
                if Enabled() then
                    Build()
                    Place()
                end
            end,
        }),
    }, ns.FOLDER)
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            unlocked = active and Enabled() or false
            Render()
        end)
    end
end)
