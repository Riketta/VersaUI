-- Override engine: applies VersaUI's own layout/scale/cosmetic overrides on
-- top of the default UI using legal surfaces only:
--   * read-only frame APIs and Edit Mode data,
--   * post-hooks on frame instances (never mixin tables) for Blizzard-managed
--     anchors, with idempotent capture-based applies as the fallback path,
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
--- Set while we ask Blizzard to anchor an unanchored spell bar purely to
--- capture its base; the SetPoint hook must not re-apply on that call.
local forcedBaseCapture = {} ---@type table<string, boolean>
--- Set while we ourselves re-point a spell bar; our own SetPoint would
--- otherwise re-trigger the SetPoint post-hook. Plain set/clear is enough:
--- the guarded region is two engine calls with clean, cached arguments.
local suppressSetPointHook = false ---@type boolean

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

--- True when the engine handed us a secret placeholder instead of a real
--- value. Secure-managed layout state (e.g. a spell bar currently anchored to
--- its aura container) is returned as secret values to tainted code, and even
--- comparing one errors - so every layout read must be screened before use.
---@param value any
---@return boolean
local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

--- Remembers the Blizzard-set anchor of a frame before we touch it. Anchors
--- reset at every login/load, so the capture is always the game's own value.
--- Secret-safe: when the engine hides the layout (see IsSecret), nothing is
--- stored and a later call retries - only plain, usable numbers ever enter
--- the cache, so our own SetPoint arguments can never be secret.
---@param id string
---@param frame any
---@return VersaUICapturedAnchor|nil
local function CaptureAnchor(id, frame)
    if capturedAnchors[id] ~= nil then
        return capturedAnchors[id]
    end
    if frame == nil then
        return nil
    end
    local numPoints = frame:GetNumPoints()
    if IsSecret(numPoints) then
        -- Secure-managed layout (aura container anchoring): the engine hides
        -- the real base from tainted readers. Relative mode must still apply,
        -- so fall back to Blizzard's own spell bar base from the reference
        -- source (TargetFrame.lua:AdjustPosition, plain-anchor constants).
        -- Deliberately seeded once: a later readable state does not re-capture,
        -- and disabling self-heals because Blizzard re-asserts its real anchor
        -- on the next AdjustPosition.
        if id == "targetCastBar" or id == "focusCastBar" then
            local parent = frame:GetParent()
            if parent ~= nil and not IsSecret(parent) then
                local anchor = {
                    point = "TOPLEFT",
                    relativeTo = parent,
                    relativePoint = "BOTTOMLEFT",
                    x = 43,
                    y = -5,
                    scale = 1,
                } ---@type VersaUICapturedAnchor
                capturedAnchors[id] = anchor
                return anchor
            end
        end
        return nil
    end
    if numPoints == 0 then
        return nil
    end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local scale = frame:GetScale()
    if
        IsSecret(point)
        or IsSecret(relativePoint)
        or IsSecret(x)
        or IsSecret(y)
        or IsSecret(scale)
        or IsSecret(relativeTo)
    then
        return nil
    end
    local anchor = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x,
        y = y,
        scale = scale,
    } ---@type VersaUICapturedAnchor
    capturedAnchors[id] = anchor
    return anchor
end

--- Re-anchors one element: relative mode keeps it attached to its Blizzard
--- base anchor (offsets are deltas, so it follows the parent frame), absolute
--- mode pins it to the screen center coordinates. Scale is a multiplier of the
--- captured Blizzard scale (focus ToT has a non-unit default scale).
--- Idempotent: always derives from the captured base. Absolute mode needs no
--- base at all, so it also works while the layout is secret-managed.
---@param captureId string unique key for the captured base anchor
---@param frame any
---@param settings VersaUIFrameOverrideSettings
---@param offsetX number
---@param offsetY number
local function ApplyElementOverride(captureId, frame, settings, offsetX, offsetY)
    if not settings.relativeToParent then
        frame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        frame:SetScale(settings.scale)
        return
    end
    local base = CaptureAnchor(captureId, frame)
    if base == nil then
        return
    end
    local relativeTo = base.relativeTo or frame:GetParent()
    frame:SetPoint(base.point, relativeTo, base.relativePoint, base.x + offsetX, base.y + offsetY)
    frame:SetScale((base.scale or 1) * settings.scale)
end

---@param id string
---@param frame any
---@param settings VersaUIFrameOverrideSettings
local function ApplyAbsoluteOverride(id, frame, settings)
    ApplyElementOverride(id, frame, settings, settings.offsetX, settings.offsetY)
end

--- Restores a frame to its captured Blizzard anchor and scale. Reads no live
--- layout values, so it is safe on secure-managed frames.
---@param id string
---@param frame any
local function ResetToCaptured(id, frame)
    local base = capturedAnchors[id]
    frame:SetScale(base and base.scale or 1)
    if base == nil then
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

--- Applies a spell bar override from its captured Blizzard base. Idempotent
--- (always derived from the captured base, never from live layout reads), so
--- it is safe to call from the enable path, the SetPoint post-hook and event
--- maintenance without ever double-applying a delta or touching secret
--- layout values. Our own SetPoint is shielded from the post-hook.
---@param id string
---@param frame any
---@param settings VersaUIFrameOverrideSettings
local function ApplySpellBarOverride(id, frame, settings)
    if frame == nil then
        return
    end
    local numPoints = frame:GetNumPoints()
    if not IsSecret(numPoints) and numPoints == 0 then
        -- The bar only receives its Blizzard anchor from AdjustPosition; ask
        -- for a fresh one and suppress the hook for this single call so the
        -- capture stays the clean base. Runs inside pcall: we call a Blizzard
        -- method from tainted execution, and its internals may legitimately
        -- refuse that on some builds. Without an anchor we simply retry later
        -- (the hook captures on the first real anchor). A secret point count
        -- means the layout is managed - never force, never branch on it.
        forcedBaseCapture[id] = true
        if frame.AdjustPosition ~= nil then
            pcall(frame.AdjustPosition, frame)
        end
        forcedBaseCapture[id] = nil
    end
    suppressSetPointHook = true
    ApplyAbsoluteOverride(id, frame, settings)
    suppressSetPointHook = false
end

--- Runs `fn` immediately when `frame` accepts layout writes in the current
--- context, otherwise defers it through the combat guard. Protected frames
--- (secure unit buttons and their children) refuse tainted writes during
--- combat, but a frame that reports unprotected can be re-pointed live -
--- which removes the visible base-position flash entirely. The protection
--- status is checked per call, so no flavor assumptions are baked in.
---@param frame any
---@param fn fun()
local function RunFrameWrite(frame, fn)
    if guard == nil then
        return
    end
    if frame ~= nil and frame.IsProtected ~= nil and not frame:IsProtected() then
        fn()
        return
    end
    guard:Run(fn)
end

--- Re-applies both spell bars one tick later. Blizzard can re-anchor them on
--- many paths (target changes, aura container updates, casts); the tick makes
--- sure we run after Blizzard's own handler in the same event burst. Each bar
--- decides independently whether it can be written right now (see
--- RunFrameWrite) or has to wait for combat to end.
local function ReapplySpellBarsNextTick()
    if guard == nil then
        return
    end
    C_Timer.After(0, function()
        for _, id in ipairs({ "targetCastBar", "focusCastBar" }) do
            local settings = GetFrameSettings(id)
            if settings ~= nil and settings.enabled then
                local frame = ResolveFrame(id)
                RunFrameWrite(frame, function()
                    ApplySpellBarOverride(id, frame, settings)
                end)
            end
        end
    end)
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

---@param targetFrame any
function Overrides.OnCheckFaction(targetFrame)
    if db ~= nil and db.factionColorDisabled then
        ApplyFactionColor(targetFrame, true)
    end
end

--- Called from the SetSmallSize post-hook: Blizzard just re-anchored and
--- re-scaled the focus ToT and the focus spell bar, so refresh the captured
--- bases and re-apply our deltas/multipliers on top of the fresh values.
---@param focusFrame any
function Overrides.OnFocusSizeChanged(focusFrame)
    if db == nil or guard == nil then
        return
    end
    local totSettings = GetFrameSettings("focusTot")
    if totSettings ~= nil and totSettings.enabled then
        local frame = focusFrame and focusFrame.totFrame
        if frame ~= nil then
            guard:Run(function()
                capturedAnchors.focusTot = nil
                ApplyAbsoluteOverride("focusTot", frame, totSettings)
            end)
        end
    end
    local castSettings = GetFrameSettings("focusCastBar")
    if castSettings ~= nil and castSettings.enabled then
        guard:Run(function()
            capturedAnchors.focusCastBar = nil
            ApplySpellBarOverride("focusCastBar", GlobalFrame("FocusFrameSpellBar"), castSettings)
        end)
    end
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

-- === Hook registration ===

-- Frames we already post-hooked, keyed [frame][method]. Keeps the registration
-- idempotent across the Init and PLAYER_LOGIN passes; double hooks would apply
-- our deltas twice.
local hookedFrames = {} ---@type table<any, table<string, boolean>>

--- Post-hooks one frame method. This must target the frame instance, never the
--- shared mixin table: XML mixin methods are copied onto every frame when it is
--- created (the same key/value copy SecureMixin does in
--- Blizzard_SharedXMLBase/Mixin.lua), so the frames Blizzard already made keep
--- calling their own copy and never see a replaced table entry.
---@param frame any
---@param methodName string
---@param handler fun(...)
local function HookFrameMethod(frame, methodName, handler)
    if frame == nil or frame[methodName] == nil then
        return
    end
    local hooked = hookedFrames[frame]
    if hooked == nil then
        hooked = {}
        hookedFrames[frame] = hooked
    end
    if hooked[methodName] then
        return
    end
    hooked[methodName] = true
    hooksecurefunc(frame, methodName, handler)
end

--- Post-hooks a spell bar's SetPoint: every Blizzard re-anchor ends in one -
--- from the cast-start path, the aura container's managed layout, target
--- switches, whichever internal route - so re-asserting here keeps the
--- override in the same execution and no base-position frame can be painted.
--- Our own applies run with suppressSetPointHook set and never re-enter.
---@param id string
---@param bar any
local function HookSpellBarSetPoint(id, bar)
    HookFrameMethod(bar, "SetPoint", function(hookedBar)
        if suppressSetPointHook or forcedBaseCapture[id] or db == nil or guard == nil then
            return
        end
        local settings = GetFrameSettings(id)
        if settings == nil or not settings.enabled then
            return
        end
        RunFrameWrite(hookedBar, function()
            ApplySpellBarOverride(id, hookedBar, settings)
        end)
    end)
end

--- Wires every post-hook onto the live frame instances. Safe to call repeatedly
--- (e.g. again on PLAYER_LOGIN for frames that may appear after Init).
local function HookBlizzardFrames()
    HookSpellBarSetPoint("targetCastBar", GlobalFrame("TargetFrameSpellBar"))
    HookSpellBarSetPoint("focusCastBar", GlobalFrame("FocusFrameSpellBar"))
    HookFrameMethod(FocusFrame, "SetSmallSize", function(focusFrame)
        Overrides.OnFocusSizeChanged(focusFrame)
    end)
    HookFrameMethod(MultiBarBottomRight, "UpdateGridLayout", function(bar)
        Overrides.OnUpdateGridLayout(bar)
    end)
    for _, frame in ipairs(GetFactionColorFrames()) do
        HookFrameMethod(frame, "CheckFaction", function(targetFrame)
            Overrides.OnCheckFaction(targetFrame)
        end)
    end
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
        if id == "targetCastBar" or id == "focusCastBar" or id == "petCastBar" then
            RunFrameWrite(frame, function()
                if id == "petCastBar" then
                    ApplyAbsoluteOverride(id, frame, settings)
                else
                    ApplySpellBarOverride(id, frame, settings)
                end
            end)
        else
            RunFrameWrite(frame, function()
                ApplyAbsoluteOverride(id, frame, settings)
            end)
        end
    else
        guard:Run(function()
            ResetToCaptured(id, frame)
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

--- Prints the runtime facts about the spell bars the override engine depends
--- on, for diagnosing client builds whose behavior drifts from the reference
--- dump. Secret-safe: managed layout state is reported as <secret> instead of
--- erroring. Usage: /versaui debug
function Overrides.DumpSpellBarDiagnostics()
    for _, id in ipairs({ "targetCastBar", "focusCastBar" }) do
        local frame = ResolveFrame(id)
        if frame == nil then
            print("|cffa335eeVersaUI:|r " .. id .. ": frame missing")
        else
            local anchor = "none"
            local numPoints = frame:GetNumPoints()
            if IsSecret(numPoints) then
                anchor = "<secret>"
            elseif numPoints > 0 then
                local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
                if IsSecret(point) or IsSecret(relativePoint) or IsSecret(x) or IsSecret(y) then
                    anchor = "<secret>"
                else
                    local relativeName = "nil"
                    if relativeTo ~= nil and relativeTo.GetName ~= nil then
                        relativeName = tostring(relativeTo:GetName() or "<anonymous>")
                    end
                    anchor = string.format(
                        "%s %s %s (%s, %s)",
                        tostring(point),
                        relativeName,
                        tostring(relativePoint),
                        tostring(x),
                        tostring(y)
                    )
                end
            end
            print(
                string.format(
                    "|cffa335eeVersaUI:|r %s name=%s AdjustPosition=%s hooked=%s scale=%s anchor: %s",
                    id,
                    tostring(frame:GetName()),
                    type(frame.AdjustPosition),
                    tostring(hookedFrames[frame] ~= nil and hookedFrames[frame].AdjustPosition == true),
                    string.format("%.2f", frame:GetScale() or 0),
                    anchor
                )
            )
        end
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
    eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "target", "focus")
    eventFrame:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target", "focus")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_LOGIN" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
            HookBlizzardFrames()
            Overrides.ApplyAll()
        elseif event == "PLAYER_REGEN_ENABLED" then
            guard:FlushPending()
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            if unit == "target" or unit == "focus" then
                ReapplySpellBarsNextTick()
            end
        elseif event == "UNIT_AURA" or event == "UNIT_CLASSIFICATION_CHANGED" then
            -- Aura container and classification switches re-anchor the bar.
            if unit == "target" or unit == "focus" then
                ReapplySpellBarsNextTick()
            end
        elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
            ReapplySpellBarsNextTick()
            -- Not every flavor recolors through CheckFaction, so re-whiten on
            -- the unit-change events themselves.
            if db ~= nil and db.factionColorDisabled then
                ApplyFactionColorToAll(true)
            end
        elseif event == "UNIT_FACTION" then
            if db ~= nil and db.factionColorDisabled then
                ApplyFactionColorToAll(true)
            end
        end
    end)

    HookBlizzardFrames()
end

return Overrides
