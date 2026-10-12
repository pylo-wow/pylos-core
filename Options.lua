local _, C = ...

-- Options framework of every Pylos addon: C.Options builds the SavedVariables,
-- settings page, minimap button and slash command from the addon's ns.options.
-- Called by the core at the addon's ADDON_LOADED.
--
-- ns.options = {
--     savedVariable = "MyAddonDB",          -- name from the TOC
--     title = "My Addon",                   -- optional display name, default addonName
--     intro = "One sentence what the addon does.",
--     icon = "Interface\\Icons\\...",       -- minimap button
--     slash = "/myaddon",                   -- opens the options
--     slashLeftClick = true,                -- optional: "/myaddon" acts like a left-click,
--                                           -- "/myaddon options" opens the options, else help
--     defaults = { list = {} },             -- optional stored values without a menu entry
--     schema = { version = 2, migrations = { [2] = function(db) end } }, -- optional (Saved.lua)
--     onLoad = function(db) end,            -- optional, after the menu is built
--     onLeftClick = function() end,         -- optional, replaces the master toggle
--     leftClickText = "...",                -- tooltip line for onLeftClick
--     onMiddleClick = function() end,       -- optional: middle-click on the minimap button
--     middleClickText = "...",              -- tooltip line for onMiddleClick
--     onTooltip = function(tooltip) end,    -- optional extra lines in the button tooltip
--     alertDims = true,                     -- optional: icon gray while there is no alert (ns.SetAlert)
--     { type = "checkbox", key = "enabled", label = "...", default = true,
--       master = true, toggleText = "..." }, -- master switch
--     { type = "header", label = "..." },
--     { type = "checkbox", key = "...", label = "...", default = false, tooltip = "..." },
--     { type = "dropdown", key = "...", label = "...", default = "a",
--       values = { { "a", "Text A" }, { "b", "Text B" } } },
--     { type = "color", key = "...", label = "...", default = "lightgray" },
--     { type = "modifier", key = "...", label = "...", default = "none" },
--     { type = "slider", key = "...", label = "...", default = 100, min = 50, max = 150,
--       step = 5, format = function(value) return value .. "%" end },
--     { type = "button", label = "...", text = "Button text", func = function() end, tooltip = "..." },
--     { type = "keybinding", command = "MYADDON_ACTION" }, -- key from Bindings.xml
--     { type = "minimap" },                 -- "Show minimap button"
--     { type = "text", text = "...", height = 24 }, -- plain string, height in pixels (default 24)
--     { type = "page", label = "...", init = function(frame) end }, -- own subpage
-- }
-- These are all the types: a row of any other type is left out and reported as a
-- problem of the addon.
-- keybinding: Blizzard's key binding control for a command from the addon's
-- Bindings.xml; the label is the command's BINDING_NAME_ text.
-- page: a subpage below the addon for content too tall for a row (lists: a
-- scrolling list inside the scrolling menu gets cut off). init(frame) runs on
-- every show; frame is the area below the page title.
-- Entries with a key, and minimap, may have onChange = function(value) end.
-- dependsOn = "otherKey", enabledWhen = value: grayed out unless that option has
-- that value. enabledIf = function() -> bool: grayed out while false.
-- visibleWhen = { "otherKey", value } (any entry, also header/row): listed only
-- while that option has that value; the list rebuilds when it changes.
-- The master switch is also toggled by left-clicking the minimap button
-- (toggleText is used in the chat line and tooltip); all other options except
-- minimap are grayed out while it is off.
-- Offered to the addon: ns.db (values), ns.minimapButton (.icon is its texture),
-- ns.SetOption(key, value) (as the menu would), ns.GetColor, ns.IsModifierHeld,
-- ns.SetAlert(on) (pulsing ring on the minimap button). Never overrides a field
-- the addon set itself, except db (Core.lua, C.Offer).
--
-- Page layout: intro; general switches without header (master first, minimap
-- last); "Display"; further sections; "Status". A section needs at least three
-- entries, smaller ones join a neighbour. Large custom rows go last so the rest
-- stays visible without scrolling.
--
-- Saved keys no option names any more are kept; only a schema migration removes them.
local L = C.L

-- key, menu label, r, g, b; the order is the order in the dropdown
local COLOR_LIST = {
    { "gray", "Gray", 0.62, 0.62, 0.62 },
    { "lightgray", "Light gray", 0.8, 0.8, 0.8 },
    { "white", "White", 1, 1, 1 },
    { "yellow", "Yellow", 1, 0.82, 0 },
    { "orange", "Orange", 1, 0.6, 0.2 },
    { "red", "Red", 1, 0.4, 0.4 },
    { "pink", "Pink", 1, 0.6, 0.8 },
    { "purple", "Purple", 0.75, 0.55, 1 },
    { "blue", "Light blue", 0.5, 0.8, 1 },
    { "turquoise", "Turquoise", 0.3, 0.9, 0.8 },
    { "green", "Green", 0.4, 1, 0.4 },
}
local COLORS = {} -- key -> { r, g, b }
for _, entry in ipairs(COLOR_LIST) do
    COLORS[entry[1]] = { entry[3], entry[4], entry[5] }
end

function C.GetColor(key)
    return COLORS[key] or COLORS.white
end

local function ColorCode(key)
    local color = C.GetColor(key)
    return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

local MODIFIERS = { shift = IsShiftKeyDown, ctrl = IsControlKeyDown, alt = IsAltKeyDown }

-- true if the chosen "modifier" key is held (always for "none")
local function IsModifierHeld(key)
    local isHeld = MODIFIERS[key]
    return not isHeld or isHeld()
end

local PRESETS = {
    color = function()
        local values = {}
        for i, entry in ipairs(COLOR_LIST) do
            values[i] = { entry[1], ColorCode(entry[1]) .. L[entry[2]] .. "|r" } -- label in its color
        end
        return values
    end,
    modifier = function()
        return { { "none", L["Always"] }, { "shift", L["Only with Shift"] }, { "ctrl", L["Only with Ctrl"] }, { "alt", L["Only with Alt"] } }
    end,
}

local TYPES = { checkbox = true, minimap = true, header = true, text = true, button = true, page = true,
    keybinding = true, slider = true, dropdown = true, color = true, modifier = true }

-- Uses the template from Options.xml. The menu recycles row frames between custom
-- rows, so each row builds in its own child frame and the others are hidden.
local function AddRow(layout, height, init)
    local function Show(frame)
        frame.parts = frame.parts or {}
        for owner, part in pairs(frame.parts) do part:SetShown(owner == init) end
        local part = frame.parts[init]
        if not part then
            part = CreateFrame("Frame", nil, frame)
            part:SetAllPoints()
            frame.parts[init] = part
        end
        init(part)
    end
    local initializer = Settings.CreateElementInitializer("PylosCoreOptionsRowTemplate", { init = Show })
    initializer.GetExtent = function() return height end
    layout:AddInitializer(initializer)
    return initializer
end

local function TextRow(text, color)
    return function(frame)
        if not frame.Text then
            frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            frame.Text:SetPoint("TOPLEFT", 37, -4)
            frame.Text:SetPoint("TOPRIGHT", -20, -4) -- full row width, wraps only when needed
            frame.Text:SetJustifyH("LEFT")
        end
        local rgb = color and C.GetColor(color) or { 1, 1, 1 }
        frame.Text:SetTextColor(rgb[1], rgb[2], rgb[3])
        frame.Text:SetText(text)
    end
end

-- color: optional color key; height in pixels
function C.AddTextRow(layout, height, text, color) return AddRow(layout, height, TextRow(text, color)) end

function C.Options(addonName, ns)
    C.Offer(ns, "GetColor", C.GetColor)
    C.Offer(ns, "IsModifierHeld", IsModifierHeld)
    local options -- ns.options
    local entries = {} -- the entries of ns.options of a known type
    local db
    local category
    local settings = {} -- key -> Settings object
    local minimapButton
    local master -- entry of the master switch, if any
    local title -- display name

    local function OpenOptions()
        Settings.OpenToCategory(category:GetID())
    end

    -- Changes an option the way the menu would, so checkbox and callbacks follow
    local function SetOption(key, value)
        if settings[key] then
            settings[key]:SetValue(value)
        else
            db[key] = value
        end
    end
    C.Offer(ns, "SetOption", SetOption)

    local alert = false -- ns.SetAlert's state; kept while the button is hidden
    local alertFrame

    local function UpdateButtonState()
        -- gray while the master switch is off, with alertDims also while no alert
        if master or options.alertDims then
            local off = master and not db[master.key]
            local idle = options.alertDims and not alert
            minimapButton.icon:SetDesaturated(off or idle or false)
        end
    end

    -- exists from the button's creation (the addon's ADDON_LOADED) on; on a hidden
    -- button only the state changes (the alert frame is its child)
    local function SetAlert(on)
        alert = on and true or false
        alertFrame:SetShown(alert)
        UpdateButtonState()
    end

    local function LeftClick()
        if options.onLeftClick then
            options.onLeftClick()
        elseif master then
            SetOption(master.key, not db[master.key])
            UpdateButtonState()
            print(L[db[master.key] and "%s: %s on" or "%s: %s off"]:format(C.CHAT_NAME:format(title), master.toggleText))
        else
            OpenOptions()
        end
    end

    local function CreateMinimapButton()
        local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
        button:SetSize(31, 31)
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(8)
        button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        background:SetSize(24, 24)
        background:SetPoint("CENTER", 0, 1)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(options.icon)
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER", 0, 1)
        button.icon = icon

        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetSize(50, 50)
        border:SetPoint("TOPLEFT")

        -- alert: highlight ring plus additive copy of the border, pulsing
        alertFrame = CreateFrame("Frame", nil, button)
        alertFrame:SetAllPoints()
        local ring = alertFrame:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        ring:SetBlendMode("ADD")
        ring:SetAllPoints()
        local rim = alertFrame:CreateTexture(nil, "OVERLAY")
        rim:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        rim:SetBlendMode("ADD")
        rim:SetSize(50, 50)
        rim:SetPoint("TOPLEFT")
        local pulse = alertFrame:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.15)
        fade:SetToAlpha(1)
        fade:SetDuration(0.6)
        fade:SetSmoothing("IN_OUT")
        -- OnShow, not SetAlert: the animation would stop after the minimap was hidden
        alertFrame:SetScript("OnShow", function() pulse:Play() end)
        alertFrame:SetScript("OnHide", function() pulse:Stop() end)
        alertFrame:Hide()

        local function UpdatePosition()
            local angle = math.rad(db.minimapAngle)
            local radius = Minimap:GetWidth() / 2 + 5
            button:ClearAllPoints()
            button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
        end

        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local centerX, centerY = Minimap:GetCenter()
                local cursorX, cursorY = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                db.minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
                UpdatePosition()
            end)
        end)
        button:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                OpenOptions()
            elseif mouseButton == "MiddleButton" then
                if options.onMiddleClick then options.onMiddleClick() end
            else
                LeftClick()
            end
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(title)
            if options.onTooltip then options.onTooltip(GameTooltip) end
            local leftClick = options.leftClickText or (master and L["%s on/off"]:format(master.toggleText))
            if leftClick then
                GameTooltip:AddLine(L["Left-click: %s"]:format(leftClick), 1, 1, 1)
            end
            GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
            if options.onMiddleClick and options.middleClickText then
                GameTooltip:AddLine(L["Middle-click: %s"]:format(options.middleClickText), 1, 1, 1)
            end
            GameTooltip:AddLine(L["Drag: move button"], 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)

        minimapButton = button
        C.Offer(ns, "minimapButton", button)
        C.Offer(ns, "SetAlert", SetAlert)
        UpdatePosition()
        UpdateButtonState()
        button:SetShown(db.minimap)
    end

    -- One Blizzard callback per option calls all handlers. Blizzard passes
    -- (owner, setting, value) (Blizzard_Setting.lua:266); the value is read from db instead.
    local changeHandlers = {} -- key -> list of handlers
    local function OnChange(key, handler)
        local handlers = changeHandlers[key]
        if handlers then
            handlers[#handlers + 1] = handler
            return
        end
        handlers = { handler }
        changeHandlers[key] = handlers
        local function callback()
            for _, each in ipairs(handlers) do each(db[key]) end
        end
        Settings.SetOnValueChangedCallback(addonName:upper() .. "_" .. key:upper(), callback)
    end

    local function AddPage(entry)
        local panel = CreateFrame("Frame")
        local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
        heading:SetPoint("TOPLEFT", 7, -22)
        heading:SetText(entry.label)
        local content = CreateFrame("Frame", nil, panel)
        content:SetPoint("TOPLEFT", 0, -56)
        content:SetPoint("BOTTOMRIGHT")
        panel:SetScript("OnShow", function() entry.init(content) end)
        Settings.RegisterCanvasLayoutSubcategory(category, panel, entry.label)
    end

    local function BuildMenu()
        local layout
        category, layout = C.ModuleCategory(title)

        local function Register(key, label, default)
            local setting = Settings.RegisterAddOnSetting(category, addonName:upper() .. "_" .. key:upper(),
                key, db, type(default), label, default)
            settings[key] = setting
            return setting
        end

        if options.intro then AddRow(layout, 32, TextRow(options.intro)) end

        local masterInitializer
        local function MasterOn() return db[master.key] end
        local initializers = {} -- key -> initializer, for dependsOn
        local visibilityKeys = {} -- keys other entries' visibleWhen depends on

        for _, entry in ipairs(entries) do
            local kind = entry.type
            local initializer
            if kind == "header" then
                initializer = CreateSettingsListSectionHeaderInitializer(entry.label)
                layout:AddInitializer(initializer)
            elseif kind == "text" then
                initializer = AddRow(layout, entry.height or 24, TextRow(entry.text))
            elseif kind == "button" then
                initializer = CreateSettingsButtonInitializer(entry.label, entry.text, entry.func, entry.tooltip, true)
                layout:AddInitializer(initializer)
            elseif kind == "page" then
                AddPage(entry)
            elseif kind == "keybinding" then
                for index = 1, GetNumBindings() do
                    if GetBinding(index) == entry.command then
                        initializer = CreateKeybindingEntryInitializer(index, true)
                        layout:AddInitializer(initializer)
                        break
                    end
                end
            elseif kind == "slider" then
                local setting = Register(entry.key, entry.label, entry.default)
                local sliderOptions = Settings.CreateSliderOptions(entry.min, entry.max, entry.step or 1)
                if entry.format then
                    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, entry.format)
                end
                initializer = Settings.CreateSlider(category, setting, sliderOptions, entry.tooltip)
            elseif kind == "checkbox" or kind == "minimap" then
                local key = entry.key or "minimap"
                local default = kind == "minimap" or entry.default
                local setting = Register(key, kind == "minimap" and L["Show minimap button"] or entry.label, default)
                initializer = Settings.CreateCheckbox(category, setting, entry.tooltip)
            elseif kind == "dropdown" or PRESETS[kind] then -- color and modifier: dropdowns with ready values
                local values = PRESETS[kind] and PRESETS[kind]() or entry.values
                local setting = Register(entry.key, entry.label, entry.default)
                initializer = Settings.CreateDropdown(category, setting, function()
                    local container = Settings.CreateControlTextContainer()
                    for _, value in ipairs(values) do
                        container:Add(value[1], value[2])
                    end
                    return container:GetData()
                end, entry.tooltip)
            end

            -- GetIndent = 0 below keeps the layout flat
            if entry.key then initializers[entry.key] = initializer end
            if entry.visibleWhen and initializer then
                local key, value = entry.visibleWhen[1], entry.visibleWhen[2]
                local baseShouldShow = initializer.ShouldShow
                initializer.ShouldShow = function(self)
                    return db[key] == value and baseShouldShow(self)
                end
                visibilityKeys[key] = true
            end
            local parent = entry.dependsOn and initializers[entry.dependsOn]
            if entry.master then
                masterInitializer = initializer
            elseif initializer and parent then
                local key, value = entry.dependsOn, entry.enabledWhen
                initializer:SetParentInitializer(parent, function()
                    return (not master or db[master.key]) and db[key] == value
                end)
                initializer.GetIndent = function() return 0 end
            elseif initializer and masterInitializer and kind ~= "minimap" then
                initializer:SetParentInitializer(masterInitializer, MasterOn)
                initializer.GetIndent = function() return 0 end
            end

            if initializer and entry.enabledIf then
                initializer:AddModifyPredicate(entry.enabledIf)
            end

            if kind == "minimap" then
                OnChange("minimap", function(shown)
                    minimapButton:SetShown(shown)
                    if entry.onChange then entry.onChange(shown) end
                end)
            elseif entry.master or entry.onChange then
                OnChange(entry.key, function(value)
                    if entry.master then UpdateButtonState() end
                    if entry.onChange then entry.onChange(value) end
                end)
            end
        end

        -- rebuild the list when an option that decides row visibility changes
        for key in pairs(visibilityKeys) do
            OnChange(key, function()
                SettingsInbound.RepairDisplay()
            end)
        end
    end

    options = ns.options
    title = options.title or addonName
    if type(options.savedVariable) ~= "string" then
        C.AddProblem(addonName, { noSavedVariable = true })
        return
    end
    for _, entry in ipairs(options) do
        if TYPES[entry.type] then
            entries[#entries + 1] = entry
        else
            C.AddProblem(addonName, { unknownType = tostring(entry.type) })
        end
    end

    local defaults = { minimap = true, minimapAngle = 200 }
    for key, value in pairs(options.defaults or {}) do defaults[key] = value end
    for _, entry in ipairs(entries) do
        if entry.key then defaults[entry.key] = entry.default end
        if entry.master then master = entry end
    end

    local schema = options.schema or {}
    db = C.API.Saved(options.savedVariable, { defaults = defaults, version = schema.version, migrations = schema.migrations })
    ns.db = db -- even when set: some addons hold false here until now

    CreateMinimapButton()
    BuildMenu()

    if options.slash then
        local name = addonName:upper()
        _G["SLASH_" .. name .. "1"] = options.slash
        if options.slashLeftClick then
            SlashCmdList[name] = function(text)
                local command = strtrim(text):lower()
                if command == "" then
                    LeftClick()
                elseif command == "options" then
                    OpenOptions()
                else
                    print(C.CHAT_NAME:format(title) .. ":")
                    print(("  %s - %s"):format(options.slash, options.leftClickText or L["same as left-clicking the minimap button"]))
                    print("  " .. L["%s options - open the options"]:format(options.slash))
                end
            end
        else
            SlashCmdList[name] = OpenOptions
        end
    end

    if options.onLoad then options.onLoad(db) end
end
