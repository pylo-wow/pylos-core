local _, C = ...

-- Every text is English and is its own key (L["Show minimap button"]).
-- C.L holds the core's texts; an addon's ns.L falls back to them, then to the key.

C.L = setmetatable({}, { __index = function(_, key) return key end })

function C.API.NewLocale()
    return setmetatable({}, { __index = function(_, key) return C.L[key] end })
end
