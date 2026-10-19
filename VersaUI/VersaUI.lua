-- Root module: registers the addon namespace. Dual-mode by contract —
-- the global namespace is what the game runtime sees, the returned table is
-- what require-based tooling and specs load from the repo root.
---@class VersaUI
---@field version string
VersaUI = VersaUI or {}

local addon = VersaUI
addon.version = "0.1.0"

return addon
