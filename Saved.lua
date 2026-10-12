local _, C = ...

-- PylosCore.Saved(name, spec) sets up the SavedVariable `name` (a global of the
-- calling addon; call in or after its ADDON_LOADED) and returns it. Provisional API.
--   spec.defaults    key -> value, put in where the key is nil (tables copied)
--   spec.version     current data shape (number, default 1)
--   spec.migrations  [n] = function(db): brings shape n - 1 to n
-- db._schema holds the stored shape: a new table starts at spec.version, one from
-- before shapes were counted is 0. Newer-shape data is left as is, and unknown keys
-- are kept (another addon version may need them); only a migration removes a key.

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end

function C.API.Saved(name, spec)
    spec = spec or {}
    local version = spec.version or 1
    local db = _G[name]
    if type(db) ~= "table" then
        db = { _schema = version }
        _G[name] = db
    end
    local from = tonumber(db._schema) or 0
    if from < version then
        for n = from + 1, version do
            local migrate = spec.migrations and spec.migrations[n]
            if migrate then migrate(db) end
        end
        db._schema = version
    end
    for key, value in pairs(spec.defaults or {}) do
        if db[key] == nil then db[key] = Copy(value) end
    end
    return db
end
