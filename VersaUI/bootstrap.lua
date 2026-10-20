-- Composition root: wires SavedVariables, the override engine and the panel
-- together. Must be last in the TOC.

---@class VersaUIDB
---@field overrides VersaUIOverridesConfig

local VersaUI = VersaUI or {}

local function NormalizeDB()
    local Config = VersaUI.config
    VersaUIDB = VersaUIDB or {}
    if VersaUIDB.overrides == nil then
        VersaUIDB.overrides = {}
    end
    Config.Normalize(VersaUIDB.overrides)
    VersaUI.db = VersaUIDB
end

local bootstrapFrame = CreateFrame("Frame", "VersaUIBootstrapFrame")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "VersaUI" then
        self:UnregisterEvent("ADDON_LOADED")
        NormalizeDB()
        VersaUI.overrides.Init(VersaUI.db.overrides)
        VersaUI.panel.Init()
    end
end)
