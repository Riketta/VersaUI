-- Override engine: applies VersaUI's own layout/scale/cosmetic overrides on
-- top of the default UI using legal surfaces only:
--   * read-only frame APIs and Edit Mode data,
--   * post-hooks (hooksecurefunc) for Blizzard-managed anchors,
--   * guarded SetPoint/SetScale out of combat (deferred on PLAYER_REGEN_ENABLED).
-- Nothing here writes to Blizzard state that Edit Mode persists; all values
-- live in VersaUI's own SavedVariables.

local VersaUI = VersaUI or {}
local Overrides = {}
VersaUI.overrides = Overrides

Overrides.FEATURES = { "tot", "focusTot", "targetCastBar", "focusCastBar", "targetLevel", "focusLevel", "petCastBar" }

--- One captured Blizzard anchor/scale pair, used as the base for deltas and
--- scale multipliers.
---@class VersaUICapturedAnchor
---@field point string
---@field relativeTo any|nil
---@field relativePoint string
---@field x number
---@field y number
---@field scale number|nil

--- The three regions making up a unit frame's level display: the background
--- circle, the level number and the high-level icon shown instead of it.
--- Blizzard renders them as one visual unit, so VersaUI treats them as a pair.
---@class VersaUILevelPair
---@field circle any|nil
---@field text any|nil
---@field highLevelTexture any|nil

local db = nil ---@type VersaUIOverridesConfig|nil
local guard = nil ---@type VersaUIGuard|nil
local capturedAnchors = {} ---@type table<string, VersaUICapturedAnchor>

-- === Pure helpers (spec-covered) ===

--- Anchor point for a re-applied action bar grid, mirroring Blizzard's rule
--- (ActionBar.lua:UpdateGridLayout).
---@param state {addButtonsToLeft: boolean|nil, addButtonsToTop: boolean|nil, addButtonsToRight: boolean|nil}
---@return string
function Overrides.ResolvePaddingAnchor(state)
    if state.addButtonsToLeft then
        return "LEFT"
    elseif state.addButtonsToTop then
        if state.addButtonsToRight then
            return "BOTTOMLEFT"
        end
        return "BOTTOMRIGHT"
    end
    if state.addButtonsToRight then
        return "TOPLEFT"
    end
    return "TOPRIGHT"
end

-- === Frame resolution ===

--- Frames the game creates by name at runtime (unit frames, spell bars) are
--- not declared globals; this keeps the strict type gate clean.
---@param name string
---@return any
local function GlobalFrame(name)
    return _G[name]
end

---@param id string
---@return any frame, any ownerFrame
local function ResolveFrame(id)
    if id == "tot" then
        return GlobalFrame("TargetFrameToT"), TargetFrame
    elseif id == "focusTot" then
        return GlobalFrame("FocusFrameToT"), FocusFrame
    elseif id == "targetCastBar" then
        return GlobalFrame("TargetFrameSpellBar"), TargetFrame
    elseif id == "focusCastBar" then
        return GlobalFrame("FocusFrameSpellBar"), FocusFrame
    elseif id == "petCastBar" then
        return GlobalFrame("PetCastingBarFrame"), UIParent
    end
    return nil, nil
end

---@param id string
---@return VersaUIFrameOverrideSettings|nil
local function GetFrameSettings(id)
    if db == nil then
        return nil
    end
    if id == "tot" then
        return db.tot
    elseif id == "focusTot" then
        return db.focusTot
    elseif id == "targetCastBar" then
        return db.targetCastBar
    elseif id == "focusCastBar" then
        return db.focusCastBar
    elseif id == "targetLevel" then
        return db.targetLevel
    elseif id == "focusLevel" then
        return db.focusLevel
    elseif id == "petCastBar" then
        return db.petCastBar
    end
    return nil
end

-- === Apply helpers ===

--- Remembers the Blizzard-set anchor of a frame before we touch it. Anchors
--- reset at every login/load, so the capture is always the game's own value.
---@param id string
---@param frame any
---@return VersaUICapturedAnchor|nil
local function CaptureAnchor(id, frame)
    if capturedAnchors[id] ~= nil then
        return capturedAnchors[id]
    end
    if frame == nil or frame:GetNumPoints() == 0 then
        return nil
    end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local anchor = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x,
        y = y,
        scale = frame:GetScale(),
    } ---@type VersaUICapturedAnchor
    capturedAnchors[id] = anchor
    return anchor
end

--- Re-anchors one element: relative mode keeps it attached to its Blizzard
--- base anchor (offsets are deltas, so it follows the parent frame), absolute
--- mode pins it to the screen center coordinates. Scale is a multiplier of the
--- captured Blizzard scale (focus ToT has a non-unit default scale).
--- Idempotent: always derives from the captured base.
---@param captureId string unique key for the captured base anchor
---@param frame any
---@param settings VersaUIFrameOverrideSettings
---@param offsetX number
---@param offsetY number
local function ApplyElementOverride(captureId, frame, settings, offsetX, offsetY)
    local base = CaptureAnchor(captureId, frame)
    if base == nil then
        return
    end
    if settings.relativeToParent then
        local relativeTo = base.relativeTo or frame:GetParent()
        frame:SetPoint(base.point, relativeTo, base.relativePoint, base.x + offsetX, base.y + offsetY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end
    frame:SetScale((base.scale or 1) * settings.scale)
end

---@param id string
---@param frame any
---@param settings VersaUIFrameOverrideSettings
local function ApplyAbsoluteOverride(id, frame, settings)
    ApplyElementOverride(id, frame, settings, settings.offsetX, settings.offsetY)
end

--- Restores a frame to its captured Blizzard anchor and scale.
---@param id string
---@param frame any
local function ResetToCaptured(id, frame)
    local base = capturedAnchors[id]
    frame:SetScale(base and base.scale or 1)
    if base == nil or frame:GetNumPoints() == 0 then
        return
    end
    local relativeTo = base.relativeTo or frame:GetParent()
    frame:ClearAllPoints()
    frame:SetPoint(base.point, relativeTo, base.relativePoint, base.x, base.y)
end

--- Resolves the level display pair of a unit frame: background circle, level
--- number and high-level icon. The circle and text live under
--- TargetFrameContentMain, the icon under TargetFrameContentContextual;
--- missing elements are simply nil so the apply helpers can skip them.
---@param id string "targetLevel" or "focusLevel"
---@return VersaUILevelPair|nil
local function ResolveLevelPair(id)
    local frame = nil ---@type any|nil
    if id == "targetLevel" then
        frame = TargetFrame
    elseif id == "focusLevel" then
        frame = FocusFrame
    end
    if frame == nil then
        return nil
    end
    local content = frame.TargetFrameContent
    local contentMain = content and content.TargetFrameContentMain
    if contentMain == nil then
        return nil
    end
    local contentContextual = content and content.TargetFrameContentContextual
    return {
        circle = contentMain.LevelBackgroundCircle,
        text = contentMain.LevelText,
        highLevelTexture = contentContextual and contentContextual.HighLevelTexture or nil,
    }
end

--- Pure: whether a pair element is anchored to another member of its own pair
--- and therefore already tracks that member's position. Exactly one member
--- anchors outside the pair and carries our offset; on camelot that is the
--- circle (TargetFrameMixin:OnLoad centers text and icon on it), on retail the
--- text anchors beside the name bar and the icon hangs off the text.
---@param base VersaUICapturedAnchor|nil
---@param pair VersaUILevelPair
---@return boolean
function Overrides.LevelElementFollowsPair(base, pair)
    if base == nil then
        return false
    end
    return base.relativeTo == pair.circle or base.relativeTo == pair.text or base.relativeTo == pair.highLevelTexture
end

--- Applies the override to one level pair. The single carrier (see
--- LevelElementFollowsPair) receives anchor and scale; the followers are
--- never re-pointed - they ride along with the carrier in both relative and
--- absolute mode - and only get the scale multiplier.
---@param id string
---@param pair VersaUILevelPair
---@param settings VersaUIFrameOverrideSettings
local function ApplyLevelPair(id, pair, settings)
    local suffixes = { "circle", "text", "highLevelTexture" }
    for _, suffix in ipairs(suffixes) do
        local element = pair[suffix]
        if element ~= nil then
            local captureId = id .. "." .. suffix
            local base = CaptureAnchor(captureId, element)
            if Overrides.LevelElementFollowsPair(base, pair) then
                element:SetScale((base and base.scale or 1) * settings.scale)
            else
                ApplyElementOverride(captureId, element, settings, settings.offsetX, settings.offsetY)
            end
        end
    end
end

--- Restores a level pair to its captured Blizzard anchors and scales.
---@param id string
---@param pair VersaUILevelPair
local function ResetLevelPair(id, pair)
    for _, suffix in ipairs({ "circle", "text", "highLevelTexture" }) do
        local element = pair[suffix]
        if element ~= nil then
            ResetToCaptured(id .. "." .. suffix, element)
        end
    end
end

--- Nudges a spell bar's freshly-set Blizzard anchor by our offsets. Only ever
--- called from the AdjustPosition post-hook, so the current anchor is always
--- the game's own value and the delta is applied exactly once.
---@param bar any
---@param settings VersaUIFrameOverrideSettings
local function NudgeSpellBar(bar, settings)
    if bar == nil or bar:GetNumPoints() == 0 then
        return
    end
    local point, relativeTo, relativePoint, x, y = bar:GetPoint(1)
    local anchorTo = relativeTo or bar:GetParent()
    bar:SetPoint(point, anchorTo, relativePoint, x + settings.offsetX, y + settings.offsetY)
    bar:SetScale(settings.scale)
end

local function ApplyPetAuras(enabled)
    if PetFrame == nil or PetFrame.AuraFrameContainer == nil then
        return
    end
    if enabled then
        PetFrame.AuraFrameContainer:SetPoint("BOTTOMLEFT", PetFrame, "TOPLEFT", 48, 4)
    else
        PetFrame.AuraFrameContainer:SetPoint("TOPLEFT", PetFrame, "TOPLEFT", 48, -42)
    end
end

--- Frames that own a ReputationColor element: the TargetFrameTemplate family
--- (target, focus, boss frames). Safe on flavors without the element - the
--- apply helper nil-guards it.
---@return any[]
local function GetFactionColorFrames()
    local frames = {}
    if TargetFrame ~= nil then
        frames[#frames + 1] = TargetFrame
    end
    if FocusFrame ~= nil then
        frames[#frames + 1] = FocusFrame
    end
    local bossContainer = GlobalFrame("BossTargetFrameContainer")
    if bossContainer ~= nil and bossContainer.BossTargetFrames ~= nil then
        for _, bossFrame in ipairs(bossContainer.BossTargetFrames) do
            frames[#frames + 1] = bossFrame
        end
    end
    return frames
end

--- Purely cosmetic (SetVertexColor/SetAlpha), so this is safe during combat.
--- Disabled hides the texture entirely: the game only ever writes the vertex
--- color, never the alpha, so SetAlpha(0) survives every recolor path. This
--- matters because not all flavors drive the color through CheckFaction -
--- the camelot classic client has no CheckFaction at all.
---@param frame any
---@param disabled boolean
local function ApplyFactionColor(frame, disabled)
    local content = frame and frame.TargetFrameContent
    local contentMain = content and content.TargetFrameContentMain
    if contentMain == nil or contentMain.ReputationColor == nil then
        return
    end
    local color = contentMain.ReputationColor
    if disabled then
        color:SetVertexColor(1, 1, 1, 1)
        color:SetAlpha(0)
    else
        color:SetAlpha(1)
        if frame.CheckFaction ~= nil then
            -- Restore Blizzard's exact semantics (faction color, tap-denied grey).
            frame:CheckFaction()
        end
    end
end

---@param disabled boolean
local function ApplyFactionColorToAll(disabled)
    for _, frame in ipairs(GetFactionColorFrames()) do
        ApplyFactionColor(frame, disabled)
    end
end

-- === Hook handlers ===

---@param bar any
function Overrides.OnSpellBarAdjusted(bar)
    if db == nil or guard == nil then
        return
    end
    local targetSpellBar = GlobalFrame("TargetFrameSpellBar")
    local focusSpellBar = GlobalFrame("FocusFrameSpellBar")
    local id = nil
    if targetSpellBar ~= nil and bar == targetSpellBar then
        id = "targetCastBar"
    elseif focusSpellBar ~= nil and bar == focusSpellBar then
        id = "focusCastBar"
    end
    if id == nil then
        return
    end
    local settings = GetFrameSettings(id)
    if settings == nil or not settings.enabled then
        return
    end
    guard:Run(function()
        NudgeSpellBar(bar, settings)
    end)
end

---@param targetFrame any
function Overrides.OnCheckFaction(targetFrame)
    if db ~= nil and db.factionColorDisabled then
        ApplyFactionColor(targetFrame, true)
    end
end

--- Called from the SetSmallSize post-hook: Blizzard just re-anchored and
--- re-scaled the focus ToT, so refresh the captured base and re-apply our
--- delta/multiplier on top of the fresh values.
---@param focusFrame any
function Overrides.OnFocusSizeChanged(focusFrame)
    if db == nil or guard == nil then
        return
    end
    local settings = GetFrameSettings("focusTot")
    if settings == nil or not settings.enabled then
        return
    end
    local frame = focusFrame and focusFrame.totFrame
    if frame == nil then
        return
    end
    guard:Run(function()
        capturedAnchors.focusTot = nil
        ApplyAbsoluteOverride("focusTot", frame, settings)
    end)
end

---@param bar any
function Overrides.OnUpdateGridLayout(bar)
    if db == nil or not db.barPadding.enabled then
        return
    end
    if MultiBarBottomRight == nil or bar ~= MultiBarBottomRight then
        return
    end
    Overrides.ApplyBarPadding(bar, db.barPadding)
end

--- Re-applies a bar's grid with separate horizontal/vertical padding, using
--- the same public layout utilities Blizzard uses. Containers are plain
--- frames (the secure buttons inside are never re-pointed), so this is safe
--- in and out of combat.
---@param bar any
---@param settings VersaUIPaddingOverrideSettings
function Overrides.ApplyBarPadding(bar, settings)
    if bar == nil or bar.shownButtonContainers == nil or not bar.numRows or bar.numRows < 1 then
        return
    end
    local minPadding = bar.minButtonPadding or 2
    local paddingX = math.max(settings.paddingX, minPadding)
    local paddingY = math.max(settings.paddingY, minPadding)
    local count = #bar.shownButtonContainers
    local stride = math.ceil(count / bar.numRows)
    local xMultiplier = bar.addButtonsToRight and 1 or -1
    local yMultiplier = bar.addButtonsToTop and 1 or -1
    local layout
    if bar.isHorizontal then
        layout = GridLayoutUtil.CreateStandardGridLayout(stride, paddingX, paddingY, xMultiplier, yMultiplier)
    else
        layout = GridLayoutUtil.CreateVerticalGridLayout(stride, paddingX, paddingY, xMultiplier, yMultiplier)
    end
    local anchorPoint = Overrides.ResolvePaddingAnchor(bar)
    GridLayoutUtil.ApplyGridLayout(
        bar.shownButtonContainers,
        AnchorUtil.CreateAnchor(anchorPoint, bar, anchorPoint),
        layout
    )
    bar:Layout()
end

-- === Public API ===

---@param id string one of Overrides.FEATURES, "petAurasOnTop" or "barPadding"
function Overrides.ApplyFeature(id)
    if db == nil or guard == nil then
        return
    end

    if id == "petAurasOnTop" then
        local enabled = (db.petAurasOnTop == true)
        guard:Run(function()
            ApplyPetAuras(enabled)
        end)
        return
    end

    if id == "barPadding" then
        if db.barPadding.enabled then
            Overrides.ApplyBarPadding(MultiBarBottomRight, db.barPadding)
        else
            MultiBarBottomRight:UpdateGridLayout()
        end
        return
    end

    if id == "factionColorDisabled" then
        ApplyFactionColorToAll(db.factionColorDisabled == true)
        return
    end

    local settings = GetFrameSettings(id)
    if settings == nil then
        return
    end

    if id == "targetLevel" or id == "focusLevel" then
        local pair = ResolveLevelPair(id)
        if pair == nil then
            return
        end
        guard:Run(function()
            if settings.enabled then
                ApplyLevelPair(id, pair, settings)
            else
                ResetLevelPair(id, pair)
            end
        end)
        return
    end

    local frame = ResolveFrame(id)
    if frame == nil then
        return
    end

    if settings.enabled then
        if id == "targetCastBar" or id == "focusCastBar" then
            -- Ask Blizzard to anchor freshly; the post-hook then nudges once.
            guard:Run(function()
                frame:SetScale(settings.scale)
                if frame.AdjustPosition ~= nil then
                    frame:AdjustPosition()
                end
            end)
        else
            guard:Run(function()
                ApplyAbsoluteOverride(id, frame, settings)
            end)
        end
    else
        guard:Run(function()
            if id == "targetCastBar" or id == "focusCastBar" then
                frame:SetScale(1)
                if frame.AdjustPosition ~= nil then
                    frame:AdjustPosition()
                end
            else
                ResetToCaptured(id, frame)
            end
        end)
    end
end

function Overrides.ApplyAll()
    if db == nil then
        return
    end
    for _, id in ipairs(Overrides.FEATURES) do
        local settings = GetFrameSettings(id)
        if settings ~= nil and settings.enabled then
            Overrides.ApplyFeature(id)
        end
    end
    if db.petAurasOnTop then
        Overrides.ApplyFeature("petAurasOnTop")
    end
    if db.factionColorDisabled then
        ApplyFactionColorToAll(true)
    end
    if db.barPadding.enabled then
        Overrides.ApplyFeature("barPadding")
    end
end

--- Wires events and post-hooks. Called once from bootstrap on ADDON_LOADED.
---@param overridesDB VersaUIOverridesConfig
function Overrides.Init(overridesDB)
    db = overridesDB
    local Guard = VersaUI.guard
    guard = Guard.New(function()
        return InCombatLockdown()
    end)

    local eventFrame = CreateFrame("Frame", "VersaUIOverridesEventFrame", UIParent)
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventFrame:RegisterEvent("UNIT_FACTION")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
            Overrides.ApplyAll()
        elseif event == "PLAYER_REGEN_ENABLED" then
            guard:FlushPending()
        elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UNIT_FACTION" then
            -- Not every flavor recolors through CheckFaction, so re-whiten on
            -- the unit-change events themselves.
            if db ~= nil and db.factionColorDisabled then
                ApplyFactionColorToAll(true)
            end
        end
    end)

    -- Flavor safety: guard the hook target itself, not just the mixin table -
    -- hooksecurefunc errors when the method is missing (e.g. CheckFaction does
    -- not exist on the camelot classic client), which would abort Init and
    -- silently kill every hook registered after it.
    if TargetSpellBarMixin ~= nil and TargetSpellBarMixin.AdjustPosition ~= nil then
        hooksecurefunc(TargetSpellBarMixin, "AdjustPosition", function(bar)
            Overrides.OnSpellBarAdjusted(bar)
        end)
    end
    if TargetFrameMixin ~= nil and TargetFrameMixin.CheckFaction ~= nil then
        hooksecurefunc(TargetFrameMixin, "CheckFaction", function(targetFrame)
            Overrides.OnCheckFaction(targetFrame)
        end)
    end
    if FocusFrameMixin ~= nil and FocusFrameMixin.SetSmallSize ~= nil then
        hooksecurefunc(FocusFrameMixin, "SetSmallSize", function(focusFrame)
            Overrides.OnFocusSizeChanged(focusFrame)
        end)
    end
    if ActionBarMixin ~= nil and ActionBarMixin.UpdateGridLayout ~= nil then
        hooksecurefunc(ActionBarMixin, "UpdateGridLayout", function(bar)
            Overrides.OnUpdateGridLayout(bar)
        end)
    end
end

return Overrides
