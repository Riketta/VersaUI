-- Combat-lockdown guard. `Run` executes immediately when the injected check
-- says we are out of combat, otherwise it defers the closure until the next
-- flush (PLAYER_REGEN_ENABLED in-game). The combat check is injected so the
-- logic is testable without the game.

---@class VersaUIGuard
---@field IsInCombat fun(): boolean
---@field pending fun()[]
local Guard = {}
Guard.__index = Guard

local VersaUI = VersaUI or {}
VersaUI.guard = Guard

---@param isInCombat fun(): boolean
---@return VersaUIGuard
function Guard.New(isInCombat)
    return setmetatable({ IsInCombat = isInCombat, pending = {} }, Guard)
end

--- Runs `fn` now when safe, or queues it for the next flush.
---@param fn fun()
function Guard:Run(fn)
    if self.IsInCombat() then
        self.pending[#self.pending + 1] = fn
    else
        fn()
    end
end

--- Runs and clears every deferred closure, in queue order.
function Guard:FlushPending()
    local pending = self.pending
    self.pending = {}
    for index = 1, #pending do
        pending[index]()
    end
end

---@return number
function Guard:PendingCount()
    return #self.pending
end

return Guard
