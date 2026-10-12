local _, C = ...

-- The settings category "Pylos": a page listing every family addon, with each
-- addon's own page (Options.lua, C.ModuleCategory) below it. Registered once at
-- PLAYER_LOGIN, after every addon made its page (Core.lua).

local L = C.L
local root, rootLayout, registered

local function Root()
    if not root then root, rootLayout = Settings.RegisterVerticalLayoutCategory("Pylos") end
    return root, rootLayout
end

function C.ModuleCategory(title)
    return Settings.RegisterVerticalLayoutSubcategory(Root(), title)
end

function C.RegisterRoot()
    if registered then return end
    registered = true
    local _, layout = Root()
    C.AddTextRow(layout, 32, L["Pylos addons. Each has its own page below this one."])
    Settings.RegisterAddOnCategory(root)
end

-- one line per addon (after RegisterRoot): its first problem, "off" if it does not run
function C.ListModules()
    local _, layout = Root()
    for _, module in ipairs(C.Modules()) do
        local problem = module.problems[1]
        if not problem then
            C.AddTextRow(layout, 24, L["%s %s: OK"]:format(module.title, module.version), "green")
        elseif module.ns.off then
            C.AddTextRow(layout, 36, L["%s %s: off - %s"]:format(module.title, module.version,
                C.ProblemText(module, problem)), "red")
        else
            C.AddTextRow(layout, 36, L["%s %s: problem - %s"]:format(module.title, module.version,
                C.ProblemText(module, problem)), "orange")
        end
    end
end
