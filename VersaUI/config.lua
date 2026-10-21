-- Pure configuration layer for the overrides system: defaults, parsing and
-- clamping. No game API access here, so specs can cover everything.

local Config = {}

local VersaUI = VersaUI or {}
VersaUI.config = Config

Config.LIMITS = {
    scaleMin = 0.3,
    scaleMax = 3,
    offsetMin = -2000,
    offsetMax = 2000,
    paddingMin = 0,
    paddingMax = 40,
    mouseSpeedMin = 1,
    mouseSpeedMax = 720,
}

---@class VersaUIFrameOverrideSettings
---@field enabled boolean
---@field scale number
---@field offsetX number
---@field offsetY number
---@field relativeToParent boolean

---@class VersaUIPaddingOverrideSettings
---@field enabled boolean
---@field paddingX number
---@field paddingY number

--- Camera look-speed override. The game's Mouse Look Speed slider only writes
--- cameraYawMoveSpeed/cameraPitchMoveSpeed through a UI-side clamp (90-270 in
--- Blizzard_SettingsDefinitions_Frame/Controls.lua); the CVars themselves are
--- plain degrees/sec, so anything below that is legal. The original* fields
--- record the pre-VersaUI values on first apply so disabling restores them
--- across sessions (SetCVar persists to Config.wtf).
---@class VersaUIMouseLookSpeedSettings
---@field enabled boolean
---@field yaw number
---@field pitch number
---@field originalYaw number|nil
---@field originalPitch number|nil

---@class VersaUIOverridesConfig
---@field tot VersaUIFrameOverrideSettings
---@field focusTot VersaUIFrameOverrideSettings
---@field targetCastBar VersaUIFrameOverrideSettings
---@field focusCastBar VersaUIFrameOverrideSettings
---@field targetLevel VersaUIFrameOverrideSettings
---@field focusLevel VersaUIFrameOverrideSettings
---@field petCastBar VersaUIFrameOverrideSettings
---@field petAurasOnTop boolean
---@field factionColorDisabled boolean
---@field barPadding VersaUIPaddingOverrideSettings
---@field mouseLookSpeed VersaUIMouseLookSpeedSettings
---@field hidePvpIcon boolean

---@return VersaUIFrameOverrideSettings
local function DefaultFrameOverride()
    return { enabled = false, scale = 1, offsetX = 0, offsetY = 0, relativeToParent = true }
end

---@return VersaUIOverridesConfig
function Config.GetDefaults()
    return {
        tot = DefaultFrameOverride(),
        focusTot = DefaultFrameOverride(),
        targetCastBar = DefaultFrameOverride(),
        focusCastBar = DefaultFrameOverride(),
        targetLevel = DefaultFrameOverride(),
        focusLevel = DefaultFrameOverride(),
        petCastBar = DefaultFrameOverride(),
        petAurasOnTop = false,
        factionColorDisabled = false,
        hidePvpIcon = false,
        barPadding = { enabled = false, paddingX = 2, paddingY = 2 },
        mouseLookSpeed = { enabled = false, yaw = 60, pitch = 30, originalYaw = nil, originalPitch = nil },
    }
end

--- Parses user text into a number, falling back when blank or invalid.
---@param text any user input (expected string, may be anything)
---@param fallback number
---@return number
function Config.ParseNumber(text, fallback)
    local value = tonumber(text)
    if value == nil then
        return fallback
    end
    return value
end

---@param value number
---@param minValue number
---@param maxValue number
---@return number
function Config.ClampValue(value, minValue, maxValue)
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

--- Normalizes one frame-override table in place: fills missing fields and
--- clamps values into the configured limits. Input is untrusted (saved
--- variables / raw panel text), so the param is deliberately untyped.
---@param settings any
---@return VersaUIFrameOverrideSettings
function Config.NormalizeFrameOverride(settings)
    settings.enabled = (settings.enabled == true)
    settings.scale =
        Config.ClampValue(Config.ParseNumber(settings.scale, 1), Config.LIMITS.scaleMin, Config.LIMITS.scaleMax)
    settings.offsetX =
        Config.ClampValue(Config.ParseNumber(settings.offsetX, 0), Config.LIMITS.offsetMin, Config.LIMITS.offsetMax)
    settings.offsetY =
        Config.ClampValue(Config.ParseNumber(settings.offsetY, 0), Config.LIMITS.offsetMin, Config.LIMITS.offsetMax)
    if settings.relativeToParent == nil then
        settings.relativeToParent = true
    end
    settings.relativeToParent = (settings.relativeToParent == true)
    return settings
end

---@param settings any
---@return VersaUIPaddingOverrideSettings
function Config.NormalizePaddingOverride(settings)
    settings.enabled = (settings.enabled == true)
    settings.paddingX =
        Config.ClampValue(Config.ParseNumber(settings.paddingX, 2), Config.LIMITS.paddingMin, Config.LIMITS.paddingMax)
    settings.paddingY =
        Config.ClampValue(Config.ParseNumber(settings.paddingY, 2), Config.LIMITS.paddingMin, Config.LIMITS.paddingMax)
    return settings
end

--- Normalizes one mouse-look-speed table in place. Input is untrusted.
---@param settings any
---@return VersaUIMouseLookSpeedSettings
function Config.NormalizeMouseLookSpeed(settings)
    settings.enabled = (settings.enabled == true)
    settings.yaw = Config.ClampValue(
        Config.ParseNumber(settings.yaw, 60),
        Config.LIMITS.mouseSpeedMin,
        Config.LIMITS.mouseSpeedMax
    )
    settings.pitch = Config.ClampValue(
        Config.ParseNumber(settings.pitch, 30),
        Config.LIMITS.mouseSpeedMin,
        Config.LIMITS.mouseSpeedMax
    )
    if type(settings.originalYaw) ~= "number" then
        settings.originalYaw = nil
    end
    if type(settings.originalPitch) ~= "number" then
        settings.originalPitch = nil
    end
    return settings
end

--- Normalizes the whole overrides config in place. Input is untrusted.
---@param db any
---@return VersaUIOverridesConfig
function Config.Normalize(db)
    if db.tot == nil then
        db.tot = DefaultFrameOverride()
    end
    if db.targetCastBar == nil then
        db.targetCastBar = DefaultFrameOverride()
    end
    if db.focusCastBar == nil then
        db.focusCastBar = DefaultFrameOverride()
    end
    if db.targetLevel == nil then
        db.targetLevel = DefaultFrameOverride()
    end
    if db.focusLevel == nil then
        db.focusLevel = DefaultFrameOverride()
    end
    if db.petCastBar == nil then
        db.petCastBar = DefaultFrameOverride()
    end
    if db.petAurasOnTop == nil then
        db.petAurasOnTop = false
    end
    if db.factionColorDisabled == nil then
        db.factionColorDisabled = false
    end
    if db.hidePvpIcon == nil then
        db.hidePvpIcon = false
    end
    if db.barPadding == nil then
        db.barPadding = { enabled = false, paddingX = 2, paddingY = 2 }
    end
    if db.mouseLookSpeed == nil then
        db.mouseLookSpeed = { enabled = false, yaw = 60, pitch = 30, originalYaw = nil, originalPitch = nil }
    end

    if db.focusTot == nil then
        db.focusTot = DefaultFrameOverride()
    end
    Config.NormalizeFrameOverride(db.tot)
    Config.NormalizeFrameOverride(db.focusTot)
    Config.NormalizeFrameOverride(db.targetCastBar)
    Config.NormalizeFrameOverride(db.focusCastBar)
    Config.NormalizeFrameOverride(db.targetLevel)
    Config.NormalizeFrameOverride(db.focusLevel)
    Config.NormalizeFrameOverride(db.petCastBar)
    db.petAurasOnTop = (db.petAurasOnTop == true)
    db.factionColorDisabled = (db.factionColorDisabled == true)
    db.hidePvpIcon = (db.hidePvpIcon == true)
    Config.NormalizePaddingOverride(db.barPadding)
    Config.NormalizeMouseLookSpeed(db.mouseLookSpeed)
    return db
end

return Config
