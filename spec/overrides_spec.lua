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

describe("level text pairing", function()
    local circle = {}

    ---@param relativeTo any|nil
    ---@return VersaUICapturedAnchor
    local function MakeAnchor(relativeTo)
        return { point = "CENTER", relativeTo = relativeTo, relativePoint = "CENTER", x = 0, y = 0, scale = 1 }
    end

    it("follows the circle when the text is anchored to it (camelot)", function()
        assert.is_true(Overrides.LevelTextFollowsCircle(MakeAnchor(circle), circle))
    end)

    it("does not follow when the text is anchored elsewhere (retail)", function()
        assert.is_false(Overrides.LevelTextFollowsCircle(MakeAnchor({}), circle))
        assert.is_false(Overrides.LevelTextFollowsCircle(MakeAnchor(nil), circle))
    end)

    it("does not follow without a captured anchor", function()
        assert.is_false(Overrides.LevelTextFollowsCircle(nil, circle))
    end)
end)
