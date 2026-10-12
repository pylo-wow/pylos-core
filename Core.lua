local addonName, C = ...

-- Base of all Pylos addons; holds no game data. PylosCore (global, service "core" 1.0)
-- is the public API; C (the core's own ns) is shared by the core's files only.
--   public    Module (stable); Provide, Get, NewLocale, Saved (provisional)
--   internal  everything else on C
-- A service is a table an addon offers under a name and a version "major.minor":
-- a new minor only adds to it, a new major may change or drop things.
local API = {}
PylosCore = API
C.API = API

C.CHAT_NAME = "|cffffd100%s|r"

-- Versions

-- major, minor of "1.4" (a plain "1" is 1.0); nil if not a version
function C.ParseVersion(version)
    local major, minor = tostring(version or ""):match("^(%d+)%.?(%d*)$")
    if not major then return nil end
    return tonumber(major), tonumber(minor) or 0
end
local Parse = C.ParseVersion

-- Services

local services = {} -- name -> major -> { minor, impl, by, names }

-- names: public fields the service promises (checked at login, see CheckContracts).
-- An older copy of the same major offered later is ignored; returns the one kept.
function API.Provide(name, version, impl, by, names)
    local major, minor = Parse(version)
    if not major or type(impl) ~= "table" then
        error(("PylosCore.Provide: bad version or table for %s"):format(tostring(name)), 2)
    end
    local list = services[name]
    if not list then
        list = {}
        services[name] = list
    end
    local have = list[major]
    if have and have.minor >= minor then return have.impl end
    list[major] = { minor = minor, impl = impl, by = by, names = names }
    return impl
end

-- the service with the same major and at least that minor, or nil
function API.Get(name, version)
    local major, minor = Parse(version)
    local have = major and services[name] and services[name][major]
    if have and have.minor >= minor then return have.impl end
    return nil
end

-- offered versions as "1.4, 2.0"; nil if none
function C.Version(name)
    local list = services[name]
    if not list then return nil end
    local majors = {}
    for major in pairs(list) do majors[#majors + 1] = major end
    if #majors == 0 then return nil end
    table.sort(majors)
    for i, major in ipairs(majors) do majors[i] = major .. "." .. list[major].minor end
    return table.concat(majors, ", ")
end

-- the addon offering the newest major of a service
local function ProviderOf(name)
    local list, best = services[name], nil
    for major in pairs(list or {}) do
        if not best or major > best then best = major end
    end
    return best and list[best].by
end

local function OldestMajor(name)
    local oldest
    for major in pairs(services[name] or {}) do
        if not oldest or major < oldest then oldest = major end
    end
    return oldest
end

-- Modules

local function Metadata(addon, field)
    local value = C_AddOns.GetAddOnMetadata(addon, field)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local modules, byName = {}, {} -- in load order; name -> module

local function NewModule(name, ns, requires)
    local module = { name = name, ns = ns, requires = requires or {}, problems = {},
        title = Metadata(name, "Title") or name, version = Metadata(name, "Version") or "?" }
    modules[#modules + 1] = module
    byName[name] = module
    return module
end
NewModule(addonName, C)

-- shown in chat and on the "Pylos" page at login
function C.AddProblem(name, problem)
    local problems = byName[name].problems
    problems[#problems + 1] = problem
end

-- The core writes only off, L, db, minimapButton, GetColor, SetOption,
-- IsModifierHeld and SetAlert into an addon's ns (frozen with 1.0; new things go
-- into ns.options or PylosCore), never a field the addon set itself (db excepted).
-- rawget: an ns may have an __index.
function C.Offer(ns, key, value)
    if rawget(ns, key) == nil then ns[key] = value end
end

-- Called in an addon's first file (Init.lua):
--   if not PylosCore.Module(addonName, ns, { requires = { data = "1.0" } }) then return end
-- Gives the addon ns.L; its options page is built from ns.options at its ADDON_LOADED.
-- If a required service is missing or too old, ns.off = true: the addon's files
-- return at once ("if ns.off then return end") and the chat and "Pylos" page say
-- what to update. Returns whether the addon may run.
function API.Module(name, ns, info)
    if byName[name] then return not ns.off end -- announced twice: the first counts
    local module = NewModule(name, ns, info and info.requires)
    C.Offer(ns, "L", API.NewLocale())
    local wanted = {}
    for service in pairs(module.requires) do wanted[#wanted + 1] = service end
    table.sort(wanted)
    for _, service in ipairs(wanted) do
        local version = module.requires[service]
        if not API.Get(service, version) then
            module.problems[#module.problems + 1] = { service = service, wants = version, have = C.Version(service) }
        end
    end
    if #module.problems > 0 then ns.off = true end
    return not ns.off
end

-- every announced addon (core first): { name, title, version, problems, ns }
function C.Modules() return modules end

function C.ProblemText(module, problem)
    local L = C.L
    if problem.missing then
        return L["%s: %s lacks %s."]:format(module.title, problem.service, problem.missing)
    elseif problem.unknownType then
        return L["%s: the option type \"%s\" is unknown, its row is left out."]:format(module.title,
            tostring(problem.unknownType))
    elseif problem.noSavedVariable then
        return L["%s: its options name no savedVariable, they are not built."]:format(module.title)
    elseif problem.optionsFailed then
        return L["%s: building its options failed (see the Lua error)."]:format(module.title)
    end
    local by = ProviderOf(problem.service)
    local provider = by and byName[by] and byName[by].title or by
    local wanted = Parse(problem.wants)
    if problem.have and provider and wanted and OldestMajor(problem.service) > wanted then
        -- every major there is newer than the wanted one: the addon is the old one
        return L["%s is off: it needs %s (%s %s), you have %s, which is newer. Update %s."]:format(module.title,
            provider, problem.service, problem.wants, problem.have, module.title)
    end
    if problem.have and provider then
        return L["%s is off: it needs %s (%s %s), you have %s. Update %s."]:format(module.title, provider,
            problem.service, problem.wants, problem.have, provider)
    end
    return L["%s is off: it needs %s %s, which is missing."]:format(module.title, problem.service, problem.wants)
end

-- a promised field missing from a service is its author's mistake
local function CheckContracts()
    for name, list in pairs(services) do
        for major, have in pairs(list) do
            for _, field in ipairs(have.names or {}) do
                if have.impl[field] == nil then
                    local module = byName[have.by]
                    if module then
                        module.problems[#module.problems + 1] = { service = name .. " " .. major .. "." .. have.minor,
                            missing = field }
                    end
                end
            end
        end
    end
end

local function Report()
    local chat = C.CHAT_NAME:format("Pylos") .. ": "
    for _, module in ipairs(modules) do
        for _, problem in ipairs(module.problems) do print(chat .. C.ProblemText(module, problem)) end
    end
end

-- Events
-- Made before any other family addon loads, so options are built before the
-- addon's own ADDON_LOADED handlers run.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        local module = byName[name]
        if module and module.ns ~= C and not module.ns.off and module.ns.options and not module.built then
            -- an error in an addon's options (or onLoad/migration) stays with that addon
            if not xpcall(function() C.Options(name, module.ns) end, geterrorhandler()) then
                C.AddProblem(name, { optionsFailed = true })
            end
            module.built = true
        end
    else
        frame:UnregisterEvent("PLAYER_LOGIN")
        -- "Pylos" first: every addon's page hangs on it, whatever fails after
        C.RegisterRoot()
        CheckContracts()
        C.ListModules()
        Report()
    end
end)

API.Provide("core", "1.0", API, addonName, { "Module" })
