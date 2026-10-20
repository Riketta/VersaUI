-- Specs for the override engine's pure helpers. The game-facing parts are not
-- load-time dependent, so requiring the module is safe without the game.
require("VersaUI.VersaUI")
local Overrides = require("VersaUI.overrides")

describe("padding anchor resolution", function()
    it("mirrors Blizzard's left-growing rule", function()
        assert.equals(Overrides.ResolvePaddingAnchor({ addButtonsToLeft = true }), "LEFT")
    end)

    it("mirrors Blizzard's top-growing rules", function()
        assert.equals(
            Overrides.ResolvePaddingAnchor({ addButtonsToTop = true, addButtonsToRight = true }),
            "BOTTOMLEFT"
        )
        assert.equals(Overrides.ResolvePaddingAnchor({ addButtonsToTop = true }), "BOTTOMRIGHT")
    end)

    it("mirrors Blizzard's default rules", function()
        assert.equals(Overrides.ResolvePaddingAnchor({ addButtonsToRight = true }), "TOPLEFT")
        assert.equals(Overrides.ResolvePaddingAnchor({}), "TOPRIGHT")
    end)
end)
