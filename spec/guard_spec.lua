-- Specs for the combat-lockdown guard.
local Guard = require("VersaUI.guard")

describe("guard", function()
    it("runs immediately when out of combat", function()
        local guard = Guard.New(function()
            return false
        end)
        local ran = false
        guard:Run(function()
            ran = true
        end)
        assert.is_true(ran)
        assert.equals(guard:PendingCount(), 0)
    end)

    it("defers while in combat", function()
        local guard = Guard.New(function()
            return true
        end)
        local ran = false
        guard:Run(function()
            ran = true
        end)
        assert.is_false(ran)
        assert.equals(guard:PendingCount(), 1)
    end)

    it("flushes deferred closures in queue order", function()
        local guard = Guard.New(function()
            return true
        end)
        local order = {}
        guard:Run(function()
            order[#order + 1] = "first"
        end)
        guard:Run(function()
            order[#order + 1] = "second"
        end)
        guard:FlushPending()
        assert.equals(order[1], "first")
        assert.equals(order[2], "second")
        assert.equals(guard:PendingCount(), 0)
    end)

    it("clears the queue so a second flush runs nothing", function()
        local guard = Guard.New(function()
            return true
        end)
        local count = 0
        guard:Run(function()
            count = count + 1
        end)
        guard:FlushPending()
        guard:FlushPending()
        assert.equals(count, 1)
    end)
end)
