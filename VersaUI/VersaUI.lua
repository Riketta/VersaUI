-- Root module: registers the addon namespace. Dual-mode by contract —
-- the global namespace is what the game runtime sees, the returned table is
-- what require-based tooling and specs load from the repo root.
---@class VersaUI
---@field version string
---@field db VersaUIDB
---@field config any module handle: VersaUI/config.lua (pure layer)
---@field guard any module handle: VersaUI/guard.lua
---@field overrides any module handle: VersaUI/overrides.lua
---@field panel any module handle: VersaUI/panel.lua
VersaUI = VersaUI or {}

local addon = VersaUI
addon.version = "0.1.0"

return addon
