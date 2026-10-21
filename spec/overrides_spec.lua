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

describe("level pair anchoring", function()
    local circle, text, icon = {}, {}, {}
    local pair = { circle = circle, text = text, highLevelTexture = icon } ---@type VersaUILevelPair

    ---@param relativeTo any|nil
    ---@return VersaUICapturedAnchor
    local function MakeAnchor(relativeTo)
        return { point = "CENTER", relativeTo = relativeTo, relativePoint = "CENTER", x = 0, y = 0, scale = 1 }
    end

    it("follows the pair when anchored to the circle (camelot text and icon)", function()
        assert.is_true(Overrides.LevelElementFollowsPair(MakeAnchor(circle), pair))
    end)

    it("follows the pair when anchored to the text (retail icon)", function()
        assert.is_true(Overrides.LevelElementFollowsPair(MakeAnchor(text), pair))
    end)

    it("carries the offset when anchored outside the pair", function()
        assert.is_false(Overrides.LevelElementFollowsPair(MakeAnchor({}), pair))
        assert.is_false(Overrides.LevelElementFollowsPair(MakeAnchor(nil), pair))
    end)

    it("carries the offset without a captured anchor", function()
        assert.is_false(Overrides.LevelElementFollowsPair(nil, pair))
    end)
end)

describe("bar texture resolution", function()
    local function MakeFetch(paths)
        return function(_, name)
            return paths[name]
        end
    end

    it("resolves built-in ids without consulting media", function()
        assert.equals(Overrides.ResolveBarTexturePath("flat", MakeFetch({})), "Interface\\Buttons\\WHITE8X8")
    end)

    it("resolves LibSharedMedia names", function()
        assert.equals(
            Overrides.ResolveBarTexturePath("Solid", MakeFetch({ Solid = "Interface\\Buttons\\WHITE8X8" })),
            "Interface\\Buttons\\WHITE8X8"
        )
    end)

    it("falls back to the flat texture on unknown or broken ids", function()
        assert.equals(Overrides.ResolveBarTexturePath("gone", MakeFetch({})), "Interface\\Buttons\\WHITE8X8")
        assert.equals(Overrides.ResolveBarTexturePath("gone", MakeFetch({ gone = "" })), "Interface\\Buttons\\WHITE8X8")
        assert.equals(Overrides.ResolveBarTexturePath("gone", nil), "Interface\\Buttons\\WHITE8X8")
    end)
end)

describe("mouse look speed cvar parsing", function()
    it("parses CVar strings into numbers", function()
        assert.equals(Overrides.ParseMouseSpeed("180", 90), 180)
        assert.equals(Overrides.ParseMouseSpeed("45.5", 90), 45.5)
    end)

    it("falls back to Blizzard's camera defaults on unreadable values", function()
        assert.equals(Overrides.ParseMouseSpeed(nil, 180), 180)
        assert.equals(Overrides.ParseMouseSpeed("", 90), 90)
        assert.equals(Overrides.ParseMouseSpeed("not-a-number", 180), 180)
    end)
end)
