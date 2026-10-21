-- Overrides window: our own non-protected frame. Every control writes to the
-- SavedVariables config (via VersaUI.config) and asks the override engine to
-- re-apply. No Blizzard UI is modified, so this window carries no taint risk.

local VersaUI = VersaUI or {}
local Panel = {}
VersaUI.panel = Panel

local FRAME_FEATURES = {
    { id = "tot", title = "Target of Target" },
    { id = "focusTot", title = "Focus ToT" },
    { id = "targetCastBar", title = "Target cast bar" },
    { id = "focusCastBar", title = "Focus cast bar" },
    { id = "targetLevel", title = "Target level" },
    { id = "focusLevel", title = "Focus level" },
    { id = "petCastBar", title = "Pet cast bar" },
}

local frame = nil ---@type any|nil
local mouseStatus = nil ---@type any|nil

--- Shows the live camera CVar values so a below-slider-minimum speed is
--- visibly in effect (the game slider would keep displaying its clamped end).
local function UpdateMouseSpeedStatus()
    if mouseStatus == nil or C_CVar == nil or C_CVar.GetCVar == nil then
        return
    end
    local parse = VersaUI.overrides.ParseMouseSpeed
    local yaw = parse(C_CVar.GetCVar("cameraYawMoveSpeed"), 0)
    local pitch = parse(C_CVar.GetCVar("cameraPitchMoveSpeed"), 0)
    mouseStatus:SetText(string.format("Live: yaw %g, pitch %g deg/s (game slider range 90-270)", yaw, pitch))
end

---@param parent any
---@param title string
---@param width number
---@return any
local function CreateNumberBox(parent, title, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 24)
    box:SetAutoFocus(false)
    box:SetMaxLetters(7)
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 2, -2)
    label:SetText(title)
    return box
end

--- Wires an editbox to a getter/commit pair: Enter commits (validated and
--- clamped by the caller), Escape reverts the display.
---@param box any
---@param get fun(): number
---@param commit fun(value: number)
local function WireNumberBox(box, get, commit)
    box:SetText(tostring(get()))
    box:SetScript("OnEnterPressed", function(editBox)
        local value = VersaUI.config.ParseNumber(editBox:GetText(), get())
        commit(value)
        editBox:SetText(tostring(get()))
        editBox:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(editBox)
        editBox:SetText(tostring(get()))
        editBox:ClearFocus()
    end)
end

---@param parent any
---@param title string
---@return any
local function CreateCheckBox(parent, title)
    local checkBox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkBox.Text:SetText(title)
    return checkBox
end

---@param parent any
---@param text string
---@param y number
local function CreateHeader(parent, text, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    header:SetText(text)
end

---@param feature {id: string, title: string}
---@param y number
local function CreateFrameFeatureRow(feature, y)
    local db = VersaUI.db.overrides
    local settings = db[feature.id]
    local apply = VersaUI.overrides.ApplyFeature

    local checkBox = CreateCheckBox(frame, feature.title)
    checkBox:SetPoint("TOPLEFT", 16, y)
    checkBox:SetChecked(settings.enabled == true)
    checkBox:SetScript("OnClick", function(self)
        settings.enabled = (self:GetChecked() == true)
        apply(feature.id)
    end)

    local scaleBox = CreateNumberBox(frame, "Scale", 52)
    scaleBox:SetPoint("TOPLEFT", 250, y - 3)
    WireNumberBox(scaleBox, function()
        return settings.scale
    end, function(value)
        settings.scale =
            VersaUI.config.ClampValue(value, VersaUI.config.LIMITS.scaleMin, VersaUI.config.LIMITS.scaleMax)
        if settings.enabled then
            apply(feature.id)
        end
    end)

    local offsetXBox = CreateNumberBox(frame, "X", 52)
    offsetXBox:SetPoint("TOPLEFT", 316, y - 3)
    WireNumberBox(offsetXBox, function()
        return settings.offsetX
    end, function(value)
        settings.offsetX =
            VersaUI.config.ClampValue(value, VersaUI.config.LIMITS.offsetMin, VersaUI.config.LIMITS.offsetMax)
        if settings.enabled then
            apply(feature.id)
        end
    end)

    local offsetYBox = CreateNumberBox(frame, "Y", 52)
    offsetYBox:SetPoint("TOPLEFT", 382, y - 3)
    WireNumberBox(offsetYBox, function()
        return settings.offsetY
    end, function(value)
        settings.offsetY =
            VersaUI.config.ClampValue(value, VersaUI.config.LIMITS.offsetMin, VersaUI.config.LIMITS.offsetMax)
        if settings.enabled then
            apply(feature.id)
        end
    end)

    local relCheck = CreateCheckBox(frame, "")
    relCheck:SetPoint("TOPLEFT", 448, y)
    relCheck:SetChecked(settings.relativeToParent ~= false)
    relCheck:SetScript("OnClick", function(self)
        settings.relativeToParent = (self:GetChecked() == true)
        if settings.enabled then
            apply(feature.id)
        end
    end)
end

---@param title string
---@param y number
---@return any checkBox
local function CreateToggleRow(title, y)
    local checkBox = CreateCheckBox(frame, title)
    checkBox:SetPoint("TOPLEFT", 16, y)
    return checkBox
end

local function CreateWindow()
    frame = CreateFrame("Frame", "VersaUIOverridesPanel", UIParent, "BasicFrameTemplateWithInset")
    -- Height derives from the feature row count (36px per row) plus the fixed
    -- toggles/padding/mouse/notes sections, so adding rows can't overflow again.
    frame:SetSize(520, 560 + #FRAME_FEATURES * 36)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", function()
        UpdateMouseSpeedStatus()
    end)
    -- BasicFrameTemplateWithInset has no SetTitle method; the title is a
    -- named FontString on the template (SharedUIPanelTemplates.xml).
    if frame.TitleText ~= nil then
        frame.TitleText:SetText("VersaUI Overrides")
    end
    tinsert(UISpecialFrames, "VersaUIOverridesPanel")

    local db = VersaUI.db.overrides
    local apply = VersaUI.overrides.ApplyFeature

    CreateHeader(frame, "Frame overrides (Scale / X / Y / Rel-to-parent)", -34)

    local y = -68
    for _, feature in ipairs(FRAME_FEATURES) do
        CreateFrameFeatureRow(feature, y)
        y = y - 36
    end

    CreateHeader(frame, "Toggles", y - 8)
    y = y - 42

    local petAuras = CreateToggleRow("Pet buffs on top of pet frame", y)
    petAuras:SetChecked(db.petAurasOnTop == true)
    petAuras:SetScript("OnClick", function(self)
        db.petAurasOnTop = (self:GetChecked() == true)
        apply("petAurasOnTop")
    end)
    y = y - 30

    local factionColor = CreateToggleRow("Disable unit frame faction color", y)
    factionColor:SetChecked(db.factionColorDisabled == true)
    factionColor:SetScript("OnClick", function(self)
        db.factionColorDisabled = (self:GetChecked() == true)
        apply("factionColorDisabled")
    end)
    y = y - 30

    local hidePvpIcon = CreateToggleRow("Hide PvP badge icon", y)
    hidePvpIcon:SetChecked(db.hidePvpIcon == true)
    hidePvpIcon:SetScript("OnClick", function(self)
        db.hidePvpIcon = (self:GetChecked() == true)
        apply("hidePvpIcon")
    end)
    y = y - 44

    CreateHeader(frame, "MultiBarBottomRight padding", y)
    y = y - 34

    local padding = db.barPadding
    local paddingCheck = CreateCheckBox(frame, "Split padding")
    paddingCheck:SetPoint("TOPLEFT", 16, y)
    paddingCheck:SetChecked(padding.enabled == true)
    paddingCheck:SetScript("OnClick", function(self)
        padding.enabled = (self:GetChecked() == true)
        apply("barPadding")
    end)

    local paddingXBox = CreateNumberBox(frame, "Pad X", 52)
    paddingXBox:SetPoint("TOPLEFT", 250, y - 3)
    WireNumberBox(paddingXBox, function()
        return padding.paddingX
    end, function(value)
        padding.paddingX =
            VersaUI.config.ClampValue(value, VersaUI.config.LIMITS.paddingMin, VersaUI.config.LIMITS.paddingMax)
        if padding.enabled then
            apply("barPadding")
        end
    end)

    local paddingYBox = CreateNumberBox(frame, "Pad Y", 52)
    paddingYBox:SetPoint("TOPLEFT", 316, y - 3)
    WireNumberBox(paddingYBox, function()
        return padding.paddingY
    end, function(value)
        padding.paddingY =
            VersaUI.config.ClampValue(value, VersaUI.config.LIMITS.paddingMin, VersaUI.config.LIMITS.paddingMax)
        if padding.enabled then
            apply("barPadding")
        end
    end)

    y = y - 52

    CreateHeader(frame, "Mouse look speed", y)
    y = y - 34

    local mouse = db.mouseLookSpeed
    local mouseCheck = CreateCheckBox(frame, "Below game minimum")
    mouseCheck:SetPoint("TOPLEFT", 16, y)
    mouseCheck:SetChecked(mouse.enabled == true)
    mouseCheck:SetScript("OnClick", function(self)
        mouse.enabled = (self:GetChecked() == true)
        apply("mouseLookSpeed")
        UpdateMouseSpeedStatus()
    end)

    local mouseYawBox = CreateNumberBox(frame, "Yaw deg/s", 52)
    mouseYawBox:SetPoint("TOPLEFT", 250, y - 3)
    WireNumberBox(mouseYawBox, function()
        return mouse.yaw
    end, function(value)
        mouse.yaw =
            VersaUI.config.ClampValue(value, VersaUI.config.LIMITS.mouseSpeedMin, VersaUI.config.LIMITS.mouseSpeedMax)
        if mouse.enabled then
            apply("mouseLookSpeed")
        end
        UpdateMouseSpeedStatus()
    end)

    local mousePitchBox = CreateNumberBox(frame, "Pitch deg/s", 52)
    mousePitchBox:SetPoint("TOPLEFT", 316, y - 3)
    WireNumberBox(mousePitchBox, function()
        return mouse.pitch
    end, function(value)
        mouse.pitch =
            VersaUI.config.ClampValue(value, VersaUI.config.LIMITS.mouseSpeedMin, VersaUI.config.LIMITS.mouseSpeedMax)
        if mouse.enabled then
            apply("mouseLookSpeed")
        end
        UpdateMouseSpeedStatus()
    end)

    mouseStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mouseStatus:SetPoint("TOPLEFT", 16, y - 28)
    UpdateMouseSpeedStatus()

    y = y - 90

    CreateHeader(frame, "Bar textures", y)
    y = y - 34

    local barTexture = db.barTexture
    local barTextureCheck = CreateCheckBox(frame, "Replace health/mana bars")
    barTextureCheck:SetPoint("TOPLEFT", 16, y)
    barTextureCheck:SetChecked(barTexture.enabled == true)
    barTextureCheck:SetScript("OnClick", function(self)
        barTexture.enabled = (self:GetChecked() == true)
        apply("barTexture")
    end)

    local barTextureDropdown = CreateFrame("Frame", "VersaUIBarTextureDropdown", frame, "UIDropDownMenuTemplate")
    barTextureDropdown:SetPoint("TOPLEFT", 250, y + 6)
    UIDropDownMenu_SetWidth(barTextureDropdown, 150)
    UIDropDownMenu_Initialize(barTextureDropdown, function(_, level)
        for _, option in ipairs(VersaUI.overrides.GetBarTextureOptions()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.title
            info.value = option.id
            info.checked = (barTexture.texture == option.id)
            info.func = function(selfArg)
                barTexture.texture = selfArg.value
                if barTexture.enabled then
                    apply("barTexture")
                end
                UIDropDownMenu_SetSelectedValue(barTextureDropdown, selfArg.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(barTextureDropdown, barTexture.texture)

    local notes = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notes:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 12)
    notes:SetText("Enter commits, Esc reverts. Rel = follow parent. Combat changes queue.")
end

--- Builds the window and registers the /versaui toggle. Called once from
--- bootstrap after the DB is normalized.
function Panel.Init()
    if frame ~= nil then
        return
    end
    CreateWindow()

    SLASH_VERSAUI1 = "/versaui"
    SlashCmdList["VERSAUI"] = function(msg)
        if msg == "debug" then
            VersaUI.overrides.DumpSpellBarDiagnostics()
            return
        end
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

return Panel
