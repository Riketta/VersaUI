-- Smoke specs for the root module: the dual-mode namespace contract.
local addon = require("VersaUI.VersaUI")

describe("VersaUI root module", function()
    it("exposes the addon namespace", function()
        assert.is_true(type(addon) == "table")
    end)

    it("declares a version", function()
        assert.equals(addon.version, "0.1.0")
    end)
end)
