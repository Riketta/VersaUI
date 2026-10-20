-- Pure configuration layer for the overrides system: defaults, parsing and
-- clamping. No game API access here, so specs can cover everything.

local Config = {}

local VersaUI = VersaUI or {}
VersaUI.config = Config

Config.LIMITS = {
    scaleMin = 0.3,
    scaleMax = 3,
    offsetMin = -500,
    offsetMax = 500,
    paddingMin = 0,
    paddingMax = 40,
}

---@class VersaUIFrameOverrideSettings
---@field enabled boolean
---@field scale number
---@field offsetX number
---@field offsetY number

---@class VersaUIPaddingOverrideSettings
---@field enabled boolean
---@field paddingX number
---@field paddingY number

---@class VersaUIOverridesConfig
---@field tot VersaUIFrameOverrideSettings
---@field targetCastBar VersaUIFrameOverrideSettings
---@field focusCastBar VersaUIFrameOverrideSettings
---@field petCastBar VersaUIFrameOverrideSettings
---@field petAurasOnTop boolean
---@field factionColorDisabled boolean
---@field barPadding VersaUIPaddingOverrideSettings

---@return VersaUIFrameOverrideSettings
local function DefaultFrameOverride()
    return { enabled = false, scale = 1, offsetX = 0, offsetY = 0 }
end

---@return VersaUIOverridesConfig
function Config.GetDefaults()
    return {
        tot = DefaultFrameOverride(),
        targetCastBar = DefaultFrameOverride(),
        focusCastBar = DefaultFrameOverride(),
        petCastBar = DefaultFrameOverride(),
        petAurasOnTop = false,
        factionColorDisabled = false,
        barPadding = { enabled = false, paddingX = 2, paddingY = 2 },
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
    if db.petCastBar == nil then
        db.petCastBar = DefaultFrameOverride()
    end
    if db.petAurasOnTop == nil then
        db.petAurasOnTop = false
    end
    if db.factionColorDisabled == nil then
        db.factionColorDisabled = false
    end
    if db.barPadding == nil then
        db.barPadding = { enabled = false, paddingX = 2, paddingY = 2 }
    end

    Config.NormalizeFrameOverride(db.tot)
    Config.NormalizeFrameOverride(db.targetCastBar)
    Config.NormalizeFrameOverride(db.focusCastBar)
    Config.NormalizeFrameOverride(db.petCastBar)
    db.petAurasOnTop = (db.petAurasOnTop == true)
    db.factionColorDisabled = (db.factionColorDisabled == true)
    Config.NormalizePaddingOverride(db.barPadding)
    return db
end

return Config
