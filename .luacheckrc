-- VersaUI lint rules.
--
-- Game globals are allowlisted per folder. Any new game API usage must be
-- added both here and to `.luarc.json` (`diagnostics.globals`).

std = "lua51"
cache = true

-- LuaLS annotations are single-line by design (`@field fun(...)` types do
-- not wrap), so this limit sits above stylua's 120 code columns (which the
-- formatter enforces on its own).
max_line_length = 150
-- Methods may legitimately ignore the implicit self.
self = false

-- Vendored toolchain trees: CI's luarocks install lands in .luarocks, the
-- local LuaLS/StyLua distributions live under tools/.
exclude_files = { ".luarocks/**", "tools/**" }

globals = {
	"VersaUI",
}

files["VersaUI"] = {
	globals = {
		"VersaUIDB",
		"VersaUI",
		"AnchorUtil",
		"C_CVar",
		"C_EditMode",
		"C_Timer",
		"issecretvalue",
		"EditModeManagerFrame",
		"EventRegistry",
		"CreateFrame",
		"FocusFrame",
		"GridLayoutUtil",
		"GetBuildInfo",
		"GetTime",
		"InCombatLockdown",
		"MultiBarBottomRight",
		"PetCastingBarFrame",
		"PetFrame",
		"SLASH_VERSAUI1",
		"SlashCmdList",
		"SetCVar",
		"TargetFrame",
		"UISpecialFrames",
		"UIParent",
		"hooksecurefunc",
		"tinsert",
		"time",
	},
}

files["spec"] = {
	ignore = { "212" },
	globals = {
		"VersaUI",
		"describe",
		"it",
		"before_each",
		"after_each",
		"setup",
		"teardown",
		"pending",
		"insulate",
		"expose",
	},
}

files["scripts"] = {
	globals = {
		"assert",
		"describe",
		"it",
		"before_each",
		"after_each",
		"setup",
		"teardown",
	},
}
